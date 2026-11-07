# Slack Desktop for Linux aarch64 — Flatpak

A **self-contained Flatpak bundle** of Slack Desktop that runs natively on
**aarch64 (arm64)** on any distro with Flatpak. Slack publishes the x86_64
Flatpak; this project builds the **aarch64 complement**, using the official
Slack package as the source of truth and Docker for a clean, reproducible build.

The deliverable is a single file: `dist/com.slack.Slack.aarch64.flatpak`.

> **Maintainers:** see **AGENTS.md** for the non-obvious implementation rationale and
> gotchas (arch asymmetry, root requirements, flatpak-builder quirks, and the rule
> against committing build artifacts) before modifying the build.

## How it works

```
official Slack package (.deb/.rpm, x86_64)
    │  native/01-fetch-slack.sh       extract + normalize the app tree
    │  native/02-detect-versions.sh   read Electron + native-module versions
    │  native/03-arm64-electron.sh    swap in the matching arm64 Electron
    │  native/04-build-native.sh      build/fetch arm64 native modules
    │  native/05-assemble.sh          package slack-<VER>-arm64.tar.xz
    ▼
dist/slack-<VER>-arm64.tar.xz   (intermediate payload)
    │  manifest/ (org.gnome.Platform:51, zero build modules)
    ▼
dist/com.slack.Slack.aarch64.flatpak   (the deliverable)
```

All stages run inside Docker (see `Dockerfile.native`, `Dockerfile.flatpak`),
so the host stays clean.

### Native modules (aarch64)
| Module | Source |
|--------|--------|
| `native-keymap` | built from public npm `native-keymap` via node-gyp |
| `electron-native-auth` | built from public npm `electron-native-auth` |
| `file-handler-info` | built from public npm `file-handler-info` |
| `@tinyspeck/slack-desktop-utils` | arm64 prebuild from Slack's S3 |
| `cf-prefs`, `registry-js`, `windows-focus-assist`, `macos-notification-state` | arm64 N-API stub (Linux no-ops) |

### Base runtime: `org.gnome.Platform:51`
Slack's Electron links only against libraries that `org.gnome.Platform` already
ships, so the app is a **pure file copy — zero build modules**. Flathub serves
`org.gnome.Platform` for aarch64 (current branch **51**). See **AGENTS.md** for the
full list of linked libraries and the reasoning.

## Requirements (build host)
- **Docker** on a **native aarch64** host (Raspberry Pi 5, Graviton, aarch64 VPS).
  Cross-prototype on x86_64 with `BUILD_PLATFORM=linux/arm64` (QEMU, slow).
- **Unprivileged user namespaces** enabled (flatpak-builder's bubblewrap sandbox):
  on Debian/Ubuntu `sysctl kernel.unprivileged_userns_clone=1` + the container
  seccomp/caps in `FLATPAK_DOCKER_FLAGS`.
- **Outbound network**: Slack CDN, `github.com` (Electron),
  `slack-desktop-native-prebuilds.s3.amazonaws.com`, `npmjs.com`, `dl.flathub.org`.
- ~10 GB free disk.

## Quick start
```sh
# The build downloads the official amd64 .deb from Slack's CDN automatically
# (no browser needed) — just make sure SLACK_VERSION points at a real release.
cp .env.example .env
$EDITOR .env        # set SLACK_VERSION (and SLACK_SOURCE_FILE to pin a local file)
./build.sh
```

Outputs in `dist/`:

| File | What |
|------|------|
| `com.slack.Slack.aarch64.flatpak` | **the deliverable** — self-contained, install anywhere |
| `slack-<VER>-arm64.tar.xz` | intermediate aarch64 payload |
| `build-inputs.json` | versions + SHA-256 (reproducibility record) |

Install on any machine with Flatpak:
```sh
flatpak install dist/com.slack.Slack.aarch64.flatpak
flatpak run com.slack.Slack
```

## Updating to a new Slack version
1. Download the new official `.deb`/`.rpm`.
2. Set `SLACK_VERSION` + `SLACK_SOURCE_FILE` in `.env`.
3. `./build.sh` — Electron, native-module, napi and S3-prebuild versions are
   **auto-detected** from the package.

## Configuration
See `.env.example`. Key knobs:

| Variable | Meaning |
|----------|---------|
| `SLACK_SOURCE_FILE` / `SLACK_SOURCE_URL` | the official package to build from |
| `SLACK_APP_ID` | `com.slack.Slack` (default) or `com.slack.Slack.aarch64` |
| `FLATPAK_RUNTIME` / `FLATPAK_RUNTIME_VERSION` | base (default `org.gnome.Platform/51`) |
| `FLATPAK_SDK` | matching build base (default `org.gnome.Sdk`) |
| `NATIVE_BASE_IMAGE` / `FLATPAK_BASE_IMAGE` | pinned build images (`node:24.22.2-trixie`, `debian:13.7`) |

## Layout
```
AGENTS.md                 # implementation rationale + gotchas (read before modifying)
build.sh                  # host orchestrator (drives Docker)
build-flatpak.sh          # flatpak-builder driver (runs in the flatpak image)
Dockerfile.native         # node + toolchain + X11/xkbfile headers
Dockerfile.flatpak        # flatpak + flatpak-builder
.env.example              # all knobs
native/                   # 01-fetch → 02-detect → 03-electron → 04-native → 05-assemble (+ stubs/)
manifest/                 # com.slack.Slack.json + slack-install.sh
```

## Known limitations
- **Screen share** (Slack "Share Screen") depends on the Wayland/X11 screencast
  portal — the least reliable sandboxed feature. Audio/video calls work.
- **Tray** needs a StatusNotifierWatcher (GNOME "App Indicator" ext, KDE, Xfce…).
- Building the Flatpak in Docker needs unprivileged user namespaces.

## Troubleshooting
- `could not obtain the Slack package` → check `SLACK_VERSION` matches a real
  release (Slack download page or the Arch AUR `slack-desktop` PKGBUILD), or pin a
  local file via `SLACK_SOURCE_FILE`. The CDN (`downloads.slack-edge.com`) serves
  the `.deb` to plain curl — there is no WAF/UA workaround to set up.
- Re-downloading the Slack package on every build → it's cached in the repo's
  `.cache/` dir (git-ignored), keyed by version; a second build for the same
  version reuses it. Delete `.cache/` to force a fresh download.
- `org.gnome.Platform … not found` for aarch64 → confirm the aarch64 host + that
  `dl.flathub.org` is reachable; Flathub serves the aarch64 runtime automatically.
- flatpak-builder hangs in Docker → enable user namespaces + `FLATPAK_DOCKER_FLAGS`.

## Acknowledgments

This project stands on the shoulders of a couple of open efforts:

- **`hamza72x/slack-linux-arm64`** — <https://github.com/hamza72x/slack-linux-arm64>.
  This repo was originally intended to fork from that project, but so much was
  reworked from first principles that the result is a fresh, standalone
  implementation rather than a fork. It is best described as a **spiritual
  ancestor and guiding inspiration** for this work, not a direct lineage.
- **The Arch AUR `slack-desktop` PKGBUILD** —
  <https://aur.archlinux.org/packages/slack-desktop>. Credit for the working
  Slack CDN download URL (`downloads.slack-edge.com`) that the fetch stage uses.

## Provenance

For provenance — and to encourage the use of open-weights AI — this repository
(design, Docker pipeline, Flatpak manifest, and build scripts) was produced
almost entirely by an **open-weights AI model running locally**: **Qwen3.8 27B**
with a **250k-token context window**, driven by **Cline** (<https://cline.bot/>)
as the coding-agent harness. None of this is required to use or contribute to
the code; it is noted here for provenance and to promote awareness of
open-weights models.