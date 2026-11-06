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
: "${FLATPAK_DOCKER_FLAGS:=}"
: "${SLACK_DOWNLOAD_UA:=Mozilla/5.0 (X11; Linux aarch64)}"
: "${NATIVE_KEYMAP_VERSION:=2.5.0}"
: "${BUILD_PLATFORM:=}"

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }

WORK="$HERE/.work"
OUT_DIR="$REPO_ROOT/dist"
rm -rf "$WORK"
mkdir -p "$WORK/src" "$WORK/out" "$WORK/flatpak-src" "$OUT_DIR"

PLATFORM_ARGS=()
[ -n "$BUILD_PLATFORM" ] && PLATFORM_ARGS+=(--platform "$BUILD_PLATFORM")

log(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# ---- 1) secure the Slack source package ----
log "Securing Slack source package"
if [ -n "${SLACK_SOURCE_FILE:-}" ] && [ -f "${SLACK_SOURCE_FILE}" ]; then
  cp -f "$SLACK_SOURCE_FILE" "$WORK/src/slack-package"
  echo "Using local package: $SLACK_SOURCE_FILE"
elif [ -n "${SLACK_SOURCE_URL:-}" ]; then
  echo "Will download from: $SLACK_SOURCE_URL"
else
  echo "No SLACK_SOURCE_FILE / SLACK_SOURCE_URL set."
  echo "  -> the build container will attempt Slack's CDN (best effort)."
  echo "  -> RELIABLE: set SLACK_SOURCE_FILE to an official Slack .deb/.rpm."
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
  -v "$WORK/src:/work/src:ro" \
  -v "$WORK/out:/work/out" \
  -v "$HERE/native:/work/scripts:ro" \
  -v "$HERE/.npm-cache:/root/.npm" \
  slack-flatpak-native:latest \
  bash /work/scripts/build-all.sh

PAYLOAD="$WORK/out/slack-$SLACK_VERSION-arm64.tar.xz"
[ -f "$PAYLOAD" ] || { echo "payload not produced: $PAYLOAD" >&2; exit 1; }
echo "Payload: $PAYLOAD ($(du -h "$PAYLOAD" | cut -f1))"

# ---- 3) stage the flatpak build dir ----
log "Staging Flatpak build dir"
cp -f "$HERE/manifest/com.slack.Slack.json" "$WORK/flatpak-src/manifest.json"
cp -f "$HERE/manifest/slack-install.sh"   "$WORK/flatpak-src/slack-install.sh"
cp -f "$HERE/build-flatpak.sh"            "$WORK/flatpak-src/build-flatpak.sh"
cp -f "$PAYLOAD"                          "$WORK/flatpak-src/slack-arm64.tar.xz"
chmod +x "$WORK/flatpak-src/slack-install.sh" "$WORK/flatpak-src/build-flatpak.sh"
# Render runtime/app-id into the manifest + install script.
for f in manifest.json slack-install.sh; do
  sed -i \
    -e "s|@APP_ID@|$SLACK_APP_ID|g" \
    -e "s|@RUNTIME@|$FLATPAK_RUNTIME|g" \
    -e "s|@RUNTIME_VERSION@|$FLATPAK_RUNTIME_VERSION|g" \
    -e "s|@RUNTIME_SDK@|$FLATPAK_SDK|g" \
    "$WORK/flatpak-src/$f"
done

# ---- 4) flatpak stage -> self-contained bundle ----
log "Building Flatpak bundle (flatpak Docker image: $FLATPAK_BASE_IMAGE)"
docker build "${PLATFORM_ARGS[@]}" \
  --build-arg BASE_IMAGE="$FLATPAK_BASE_IMAGE" \
  -t slack-flatpak-builder:latest \
  -f "$HERE/Dockerfile.flatpak" "$HERE"

# shellcheck disable=SC2086
docker run --rm "${PLATFORM_ARGS[@]}" \
  $FLATPAK_DOCKER_FLAGS \
  -e FLATPAK_ARCH="$FLATPAK_ARCH" \
  -e FLATPAK_RUNTIME="$FLATPAK_RUNTIME" \
  -e FLATPAK_RUNTIME_VERSION="$FLATPAK_RUNTIME_VERSION" \
  -e FLATPAK_SDK="$FLATPAK_SDK" \
  -e SLACK_APP_ID="$SLACK_APP_ID" \
  -e FLATPAK_REMOTE_URL="$FLATPAK_REMOTE_URL" \
  -e FLATPAK_RUNTIME_REPO="$FLATPAK_RUNTIME_REPO" \
  -v "$WORK/flatpak-src:/work" \
  -v "$WORK/out:/out" \
  -v "$HERE/.flatpak-cache:/var/cache/flatpak" \
  -v "$HERE/.flatpak:/var/lib/flatpak" \
  -v "$HERE/.flatpak-user:/root/.local/share/flatpak" \
  slack-flatpak-builder:latest \
  bash /work/build-flatpak.sh

BUNDLE="$WORK/out/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
[ -f "$BUNDLE" ] || { echo "bundle not produced: $BUNDLE" >&2; exit 1; }

# ---- 5) collect outputs ----
log "Collecting outputs -> $OUT_DIR"
cp -f "$PAYLOAD"  "$OUT_DIR/"
cp -f "$BUNDLE"   "$OUT_DIR/"
[ -f "$WORK/out/build-inputs.json" ] && cp -f "$WORK/out/build-inputs.json" "$OUT_DIR/"

echo
echo "Done."
echo "  Payload : $OUT_DIR/slack-$SLACK_VERSION-arm64.tar.xz"
echo "  Bundle  : $OUT_DIR/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
echo
echo "Install on any distro with Flatpak:"
echo "  flatpak install $OUT_DIR/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
echo "  flatpak run $SLACK_APP_ID"
