#!/usr/bin/env bash
#
# build.sh — Build the Slack Desktop aarch64 Flatpak, entirely inside Docker.
#
# Slack publishes an x86_64 Flatpak; this repo builds the aarch64 complement.
# The output is a self-contained .flatpak bundle — the sole deliverable of this
# project. (The arm64 payload .tar.xz is only an intermediate for flatpak-builder.)
#
# Run on a native aarch64 Docker host. (BUILD_PLATFORM=linux/arm64 cross-builds
# via QEMU on an x86_64 box — slower, for prototyping only.)
#
# Usage:
#   ./build.sh                                        # reads ./.env
#   SLACK_SOURCE_FILE=~/Downloads/slack-4.50.143-amd64.deb ./build.sh
#
# Outputs (in ./dist/):
#   com.slack.Slack.aarch64.flatpak   self-contained, installable on any distro
#   slack-<VER>-arm64.tar.xz          intermediate payload
#   build-inputs.json                 versions + hashes (reproducibility record)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$HERE"   # build.sh lives at the repo root

# ---- config ----
[ -f "$HERE/.env" ] && { set -a; . "$HERE/.env"; set +a; }
: "${SLACK_VERSION:?SLACK_VERSION must be set (./.env or env)}"
: "${SLACK_APP_ID:=com.slack.Slack}"
: "${FLATPAK_RUNTIME:=org.gnome.Platform}"
: "${FLATPAK_RUNTIME_VERSION:=51}"
: "${FLATPAK_SDK:=org.gnome.Sdk}"
: "${FLATPAK_ARCH:=aarch64}"
: "${FLATPAK_REMOTE_URL:=https://dl.flathub.org/repo/flathub.flatpakrepo}"
: "${FLATPAK_RUNTIME_REPO:=https://dl.flathub.org/repo/}"
: "${NATIVE_BASE_IMAGE:=node:24.22.2-trixie}"
: "${FLATPAK_BASE_IMAGE:=debian:13.7}"
# The flatpak stage needs user namespaces for bubblewrap; these Docker flags
# enable that. Defaults work on a normal Docker host; override as needed.
: "${FLATPAK_DOCKER_FLAGS:=--security-opt seccomp=unconfined --privileged --cap-add SYS_ADMIN}"
: "${SLACK_DOWNLOAD_UA:=Mozilla/5.0 (X11; Linux aarch64)}"
: "${NATIVE_KEYMAP_VERSION:=2.5.0}"
# Auto-detect the Docker build platform. The native stage must run as aarch64
# (node-gyp compiles native modules for the container's *runtime* arch), so when
# the host is not itself aarch64 we cross-build via `--platform linux/arm64`
# (QEMU/binfmt emulation). An explicit BUILD_PLATFORM still takes precedence.
if [ -z "${BUILD_PLATFORM:-}" ]; then
  case "$(uname -m)" in
    aarch64|arm64) BUILD_PLATFORM="" ;;  # native aarch64 host: build natively
    *) BUILD_PLATFORM="linux/arm64" ;;   # e.g. x86_64 host: cross-build aarch64
  esac
fi

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }

WORK="$HERE/.work"
CACHE_DIR="${SLACK_CACHE_DIR:-$HERE/.cache}"
OUT_DIR="$REPO_ROOT/dist"
# Best-effort clean of the per-build dir. It may hold root-owned files from a
# prior run (the native stage runs as root in its container); a sudo-less host
# user can't delete those, so don't abort on it. Each stage recreates/overwrites
# what it needs, and the flatpak stage uses its own user-owned dir ($HERE/.fp).
# Persistent caches (.cache, .npm-cache) are kept so repeat builds don't
# re-download. (CI runners typically clear the whole workspace anyway.)
rm -rf "$WORK" 2>/dev/null || true
mkdir -p "$CACHE_DIR" "$WORK/out" "$OUT_DIR"

PLATFORM_ARGS=()
[ -n "$BUILD_PLATFORM" ] && PLATFORM_ARGS+=(--platform "$BUILD_PLATFORM")

log(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# ---- 1) secure the Slack source package ----
# Staged into the persistent cache (keyed by version), so a later build reuses it
# and the ~100 MB package is downloaded at most once per version.
CACHED_PKG="$CACHE_DIR/slack-desktop-${SLACK_VERSION}-amd64.deb"
log "Securing Slack source package (cache: $CACHE_DIR)"
if [ -n "${SLACK_SOURCE_FILE:-}" ] && [ -f "${SLACK_SOURCE_FILE}" ]; then
  cp -f "$SLACK_SOURCE_FILE" "$CACHED_PKG"
  echo "Cached local package -> $CACHED_PKG"
elif [ -f "$CACHED_PKG" ]; then
  echo "Reusing cached Slack package: $CACHED_PKG"
elif [ -n "${SLACK_SOURCE_URL:-}" ]; then
  echo "Will download from: $SLACK_SOURCE_URL (into $CACHE_DIR)"
else
  echo "No SLACK_SOURCE_FILE / SLACK_SOURCE_URL set — will download into $CACHE_DIR."
fi

# ---- 2) native stage -> aarch64 payload ----
log "Building aarch64 payload (native Docker image: $NATIVE_BASE_IMAGE)"
docker build "${PLATFORM_ARGS[@]}" \
  --build-arg BASE_IMAGE="$NATIVE_BASE_IMAGE" \
  -t slack-flatpak-native:latest \
  -f "$HERE/Dockerfile.native" "$HERE"

docker run --rm "${PLATFORM_ARGS[@]}" \
  -e SLACK_VERSION="$SLACK_VERSION" \
  -e SLACK_SOURCE_URL="${SLACK_SOURCE_URL:-}" \
  -e SLACK_DOWNLOAD_UA="$SLACK_DOWNLOAD_UA" \
  -e NATIVE_KEYMAP_VERSION="$NATIVE_KEYMAP_VERSION" \
  -v "$CACHE_DIR:/work/cache" \
  -v "$WORK/out:/work/out" \
  -v "$HERE/native:/work/scripts:ro" \
  -v "$HERE/.npm-cache:/root/.npm" \
  slack-flatpak-native:latest \
  bash /work/scripts/build-all.sh

PAYLOAD="$WORK/out/slack-$SLACK_VERSION-arm64.tar.xz"
[ -f "$PAYLOAD" ] || { echo "payload not produced: $PAYLOAD" >&2; exit 1; }
echo "Payload: $PAYLOAD ($(du -h "$PAYLOAD" | cut -f1))"

# ---- 3) stage the flatpak build dir (fresh, USER-OWNED) ----
# A dedicated user-owned dir (not .work, which may hold root-owned files from an
# earlier root run that a sudo-less host user cannot remove). It holds the
# manifest, payload, install script, and — across builds — the cached aarch64
# runtime, so the runtime is downloaded once and reused.
FP_DIR="$HERE/.fp"
log "Staging Flatpak build dir ($FP_DIR)"
mkdir -p "$FP_DIR"
cp -f "$HERE/manifest/com.slack.Slack.json" "$FP_DIR/manifest.json"
cp -f "$HERE/manifest/slack-install.sh"     "$FP_DIR/slack-install.sh"
cp -f "$HERE/build-flatpak.sh"              "$FP_DIR/build-flatpak.sh"
cp -f "$PAYLOAD"                            "$FP_DIR/slack-arm64.tar.xz"
chmod +x "$FP_DIR/slack-install.sh" "$FP_DIR/build-flatpak.sh"
# Render runtime/app-id into the manifest + install script.
for f in manifest.json slack-install.sh; do
  sed -i \
    -e "s|@APP_ID@|$SLACK_APP_ID|g" \
    -e "s|@RUNTIME@|$FLATPAK_RUNTIME|g" \
    -e "s|@RUNTIME_VERSION@|$FLATPAK_RUNTIME_VERSION|g" \
    -e "s|@RUNTIME_SDK@|$FLATPAK_SDK|g" \
    "$FP_DIR/$f"
done

# ---- 4) flatpak stage -> self-contained bundle ----
# Arch rule: flatpak-builder must run on the HOST arch (no --platform) so its
# bubblewrap creates the build namespaces natively — under QEMU aarch64
# user-mode emulation, bwrap's namespace creation fails. The aarch64 app is still
# produced because flatpak-builder runs the aarch64 runtime (from Flathub) in
# the build sandbox. It runs as the container's default user (root — the Docker
# default); we simply don't set `docker --user`. The aarch64 runtime is cached in
# the host state dir, so it's downloaded once and reused.
log "Building Flatpak bundle (image: $FLATPAK_BASE_IMAGE)"
docker build \
  --build-arg BASE_IMAGE="$FLATPAK_BASE_IMAGE" \
  -t slack-flatpak-builder:latest \
  -f "$HERE/Dockerfile.flatpak" "$HERE"

# shellcheck disable=SC2086
docker run --rm \
  $FLATPAK_DOCKER_FLAGS \
  -e FLATPAK_ARCH="$FLATPAK_ARCH" \
  -e FLATPAK_RUNTIME="$FLATPAK_RUNTIME" \
  -e FLATPAK_RUNTIME_VERSION="$FLATPAK_RUNTIME_VERSION" \
  -e FLATPAK_SDK="$FLATPAK_SDK" \
  -e SLACK_APP_ID="$SLACK_APP_ID" \
  -e FLATPAK_REMOTE_URL="$FLATPAK_REMOTE_URL" \
  -v "$FP_DIR:/work" \
  -v "$HERE/.flatpak-user:/root/.local/share/flatpak" \
  -v "$HERE/.flatpak-cache:/var/cache/flatpak" \
  -v "$HERE/.flatpak:/var/lib/flatpak" \
  slack-flatpak-builder:latest \
  bash /work/build-flatpak.sh

BUNDLE="$FP_DIR/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
[ -f "$BUNDLE" ] || { echo "bundle not produced: $BUNDLE" >&2; exit 1; }

# ---- 5) collect outputs ----
log "Collecting outputs -> $OUT_DIR"
cp -f "$PAYLOAD" "$OUT_DIR/"
cp -f "$BUNDLE"  "$OUT_DIR/"

echo
echo "Done."
echo "  Payload : $OUT_DIR/slack-$SLACK_VERSION-arm64.tar.xz"
echo "  Bundle  : $OUT_DIR/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
echo
echo "Install on any distro with Flatpak:"
echo "  flatpak install $OUT_DIR/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
echo "  flatpak run $SLACK_APP_ID"
