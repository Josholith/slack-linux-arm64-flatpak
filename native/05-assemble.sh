#!/usr/bin/env bash
#
# 05-assemble.sh — Package the adapted app tree into slack-<VER>-arm64.tar.xz and
# write build-inputs.json (versions + hashes) so the build is reproducible.
#
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
. "$BUILD/versions.env"

STAGE_ROOT="$BUILD/payload"
STAGE="$STAGE_ROOT/slack-$SLACK_VERSION-arm64"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -a "$APP_ROOT/." "$STAGE/"

# Icon (the Flatpak layer generates the .desktop entry; keep the reference assets).
[ -f "$BUILD/meta/slack.png" ]     && cp -a "$BUILD/meta/slack.png"     "$STAGE/slack.png"
[ -f "$BUILD/meta/slack.desktop" ] && cp -a "$BUILD/meta/slack.desktop" "$STAGE/slack.desktop"
true

# Hard fail if any x86-64 ELF remains in the payload.
X86="$(find "$STAGE" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.node' -o -name 'slack' -o -name 'chrome_crashpad_handler' -o -name 'chrome-sandbox' \) -exec file {} \; 2>/dev/null | grep 'x86-64' || true)"
[ -z "$X86" ] || die "x86-64 binaries remain in payload:
$X86"
echo "Arch check OK: no x86-64 binaries in payload."

log "Tarring payload -> $OUT/slack-$SLACK_VERSION-arm64.tar.xz"
tar -C "$STAGE_ROOT" -cJf "$OUT/slack-$SLACK_VERSION-arm64.tar.xz" "slack-$SLACK_VERSION-arm64"
PAYLOAD_SHA="$(sha256sum "$OUT/slack-$SLACK_VERSION-arm64.tar.xz" | awk '{print $1}')"

cat > "$OUT/build-inputs.json" <<EOF
{
  "slack_version": "$SLACK_VERSION",
  "electron_version": "$ELECTRON_VERSION",
  "native_keymap_version": "$NATIVE_KEYMAP_VERSION",
  "electron_native_auth_version": "$ENA_VER",
  "file_handler_info_version": "$FHI_VER",
  "slack_desktop_utils_version": "$SDU_VER",
  "napi_version": "$NAPI_VER",
  "input_package_sha256": "$(cat "$BUILD/input-sha256.txt" 2>/dev/null || echo unknown)",
  "electron_zip_sha256": "$(cat "$BUILD/electron-zip-sha256.txt" 2>/dev/null || echo unknown)",
  "slack_desktop_utils_prebuild_sha256": "$(cat "$BUILD/sdu-sha256.txt" 2>/dev/null || echo unknown)",
  "payload_sha256": "$PAYLOAD_SHA"
}
EOF
log "Stage 05 done (payload sha256=$PAYLOAD_SHA)"
