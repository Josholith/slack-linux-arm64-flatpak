# AGENTS.md

Guidance for AI agents (and humans) **modifying the build** in this repo. It captures
the non-obvious *why* behind the implementation choices so edits don't silently break
things. It deliberately does **not** duplicate the user-facing README — read that first
for how the tool is used and what it produces.

## Hard rule: never commit build outputs

Do **not** commit any build artifact or downloaded input as code. These are all
git-ignored and must stay that way:

- `dist/` — the deliverable `.flatpak` bundle + the arm64 payload tarball
- `.cache/` — the downloaded Slack source package (~100 MB)
- `.fp/`, `.work/` — per-build work dirs (staging, build trees)
- `.npm-cache/` — npm cache
- `.flatpak/`, `.flatpak-cache/`, `.flatpak-user/` — flatpak state + the aarch64
  runtime (multi-GB)

This is a **rule**, not just hygiene, for two reasons:

1. **Repo bloat** — these are hundreds of MB to GBs; committing them wrecks the repo.
2. **Licensing / distribution** — the Slack `.deb`, the aarch64 Electron build, and
   the repackaged Slack bundle are Slack's (or Electron's) binaries. Committing and
   redistributing them from this repo risks violating Slack's licensing/distribution
   terms. This repo ships **source + build scripts only**; the binaries are produced
   at build time from Slack's official package.

If a test or check needs an artifact, generate it into `dist/` / `.work` (ignored),
never into a tracked path.

## Non-obvious implementation notes

### The two stages build for *different* architectures (on purpose)
The build targets aarch64, but the Docker stages are intentionally asymmetric
(`build.sh`):

- **Native stage** (`Dockerfile.native`, node-gyp): cross-builds with
  `--platform linux/arm64` (QEMU) when the host isn't aarch64, because node-gyp
  compiles against the container's **runtime** arch. An explicit `BUILD_PLATFORM`
  still takes precedence.
- **Flatpak stage** (`Dockerfile.flatpak`, flatpak-builder): runs flatpak-builder on
  the **HOST arch — never `--platform`**. Reason: flatpak-builder sandboxes its build
  with **bubblewrap**, and bwrap cannot create the namespaces it needs under QEMU
  aarch64 user-mode emulation ("Creating new namespace failed"). It still yields a
  **genuinely aarch64** app because flatpak-builder runs the **aarch64 runtime**
  (`org.gnome.Platform/aarch64`, pulled from Flathub) *inside* the sandbox.

Don't "fix" this by putting `--platform` on the flatpak stage — that reintroduces the
bwrap failure.

### The flatpak stage runs as root, with full base refs
- **Root is required**: flatpak-builder's `rofiles-fuse` helper can't resolve a bare
  non-root UID that isn't in the sandbox's `/etc/passwd` → `fusermount3: could not
  determine username`. So `build.sh` runs it as root (no `--user`), with the
  user-install state on host mounts (`.flatpak-user`, …) so the aarch64 runtime is
  cached and downloaded once.
- **Base refs must be full** `id/arch/branch` (e.g. `org.gnome.Sdk/aarch64/51`) and
  **pre-installed** with `flatpak install --user`. flatpak-builder won't pull them
  itself, and flatpak **rejects the `id:branch` form**.

### Missing tool: `eu-strip` (elfutils)
flatpak-builder strips debuginfo and shells out to `eu-strip`, which the base `debian`
image lacks. `Dockerfile.flatpak` installs `elfutils` for this — don't drop it.

### flatpak-builder manifest quirks (see `manifest/com.slack.Slack.json`)
- The manifest **must** declare `sdk` **and** `sdk-version` (aarch64: `org.gnome.Sdk`
  / `51`); current flatpak-builder rejects manifests without them.
- Local sources use `type: "file"` + `path:` (the local payload tarball + install
  script) — not `url:`.
- The payload is extracted with `tar … --no-same-owner` (the sandbox refuses the
  default owner remap for a root-owned tarball).
- `flatpak build-bundle` positional order is `LOCATION FILENAME NAME [BRANCH]`;
  `--arch` and `--runtime-repo` are **options**, not positionals (see
  `build-flatpak.sh`).

### Slack's Electron version is the linchpin
You must match Slack's **exact** Electron version (read at build time by
`native/02-detect-versions.sh` from the package's `version` file) and pull the
**aarch64** Electron release for it (`native/03-arm64-electron.sh`). A mismatch gives
you ABI-incompatible native modules. **Don't hardcode the version** — it changes every
Slack release.

### Where each aarch64 `.node` comes from (`native/04-build-native.sh`)
- **Open npm, built from source** — `native-keymap` (public fork),
  `electron-native-auth`, `file-handler-info`. Installed with `npm install
  --ignore-scripts`, then built explicitly with `npx node-gyp rebuild`. The
  `--ignore-scripts` + explicit node-gyp is deliberate: it dodges npm's varying
  lifecycle-script policy (e.g. npm 12's "allowScripts" gating). Keep it.
- **Proprietary prebuild from Slack's S3** (not on npm) —
  `@tinyspeck/slack-desktop-utils`, URL pattern
  `…/slackdesktoputils-v<VER>-napi-v<NAPI>-linux-arm64.tar.gz`. **This is the one step
  that isn't fully automatic**: if Slack hasn't published the arm64 prebuild for a new
  version, stage 04 fails with a clear `die`. There's no local fallback.
- **Platform no-ops → compiled N-API stub** — `cf-prefs`, `registry-js`,
  `windows-focus-assist`, `macos-notification-state`. These are macOS/Windows-only and
  export nothing on Linux; they're replaced with a tiny empty module
  (`native/stubs/empty_napi_module.c`). If a **new** similar tiny module appears,
  inspect its exported symbols — if it's a no-op, add it to the stub list.

### Slack CDN: it's the URL, not a WAF
The `.deb` downloads with **plain curl** — there's no WAF/UA wall. The original "403"
was a wrong host: use `downloads.slack-edge.com` (per the AUR `slack-desktop`
PKGBUILD), not `download.slack.com`. `SLACK_DOWNLOAD_UA` is vestigial.

### `.gitignore` gotcha (bit us once)
A `#` **mid-line** is part of the pattern, not a comment — `.cache/  # hi` does **not**
ignore `.cache/`. Put comments on their own line.

## Base runtime: why `org.gnome.Platform` (zero build modules)
Slack's Electron links GTK3, GLib, ATK/atspi, Cairo/Pango, X11, GBM, xkbcommon, udev,
ALSA, NSS, CUPS and DBus, and dlopens **libsecret** (keyring) + **libnotify**; the tray
uses StatusNotifierItem (D-Bus). `org.gnome.Platform` ships all of these, so the app is
a **pure file copy with zero build modules** — `manifest/slack-install.sh` is essentially
`cp -a` + a launcher, and no cross-compile toolchain is needed at the flatpak stage.
Flathub serves `org.gnome.Platform` for aarch64 (current branch **51**).

## Updating to a new Slack version
Bump `SLACK_VERSION` (`.env`); Electron / native-module / napi / S3-prebuild versions
are **auto-detected** from the package. Watch stage 04 — the proprietary S3 prebuild is
the only piece that depends on Slack having published an arm64 build for that version.