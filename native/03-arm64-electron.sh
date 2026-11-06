#!/usr/bin/env bash
#
# 03-arm64-electron.sh — Download the matching arm64 Electron and swap the
# architecture-specific runtime files into the payload. resources/ (the JS app)
# is left untouched.
#
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
. "$BUILD/versions.env"

log "Downloading Electron $ELECTRON_VERSION (linux-arm64)"
ZIP="$BUILD/electron-arm64.zip"
URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-arm64.zip"
curl -fL --retry 3 --max-time 600 -o "$ZIP" "$URL"
sha256sum "$ZIP" | awk '{print $1}' > "$BUILD/electron-zip-sha256.txt"

mkdir -p "$BUILD/electron"
unzip -q -o "$ZIP" -d "$BUILD/electron"
[ -f "$BUILD/electron/electron" ] || die "electron binary missing from download"

# Electron ships its main binary as `electron`; Slack names it `slack`.
cp -f "$BUILD/electron/electron" "$APP_ROOT/slack"

log "Swapping arm64 runtime files into $APP_ROOT"
RUNTIME_FILES=(
  chrome_crashpad_handler
  chrome-sandbox
  libEGL.so
  libGLESv2.so
  libffmpeg.so
  libvk_swiftshader.so
  libvulkan.so.1
  snapshot_blob.bin
  v8_context_snapshot.bin
  icudtl.dat
  resources.pak
  chrome_100_percent.pak
  chrome_200_percent.pak
  vk_swiftshader_icd.json
)
for f in "${RUNTIME_FILES[@]}"; do
  if [ -f "$BUILD/electron/$f" ]; then
    cp -f "$BUILD/electron/$f" "$APP_ROOT/$f"
  else
    echo "  (warn) '$f' not in download; keeping existing copy"
  fi
done
mkdir -p "$APP_ROOT/locales"
cp -f "$BUILD/electron/locales/"*.pak "$APP_ROOT/locales/" 2>/dev/null || true

chmod 755 "$APP_ROOT/slack"
file -b "$APP_ROOT/slack" | grep -qi 'aarch64' || die "swapped slack binary is not aarch64: $(file -b "$APP_ROOT/slack")"
log "Stage 03 done (electron zip sha256=$(cat "$BUILD/electron-zip-sha256.txt"))"
