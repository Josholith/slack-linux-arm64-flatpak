#!/usr/bin/env bash
#
# 02-detect-versions.sh — Read the Electron version + native module versions from
# the payload and emit $BUILD/versions.env (sourced by stages 03/04). Never
# hardcode: everything is read from the package so new Slack versions "just work".
#
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[ -f "$APP_ROOT/version" ] || die "missing $APP_ROOT/version"
ELECTRON_VERSION="$(tr -d '[:space:]' < "$APP_ROOT/version")"
log "Electron version: $ELECTRON_VERSION"

APPASAR="$APP_ROOT/resources/app.asar"
[ -f "$APPASAR" ] || die "missing app.asar"

ASAR_DIR="$BUILD/asar"
rm -rf "$ASAR_DIR"
log "Extracting app.asar to inspect native module versions"
# Extract exactly once (npx --yes is non-interactive). No fragile fallback that
# can race on the first asar download.
npx --yes asar extract "$APPASAR" "$ASAR_DIR"
[ -d "$ASAR_DIR/node_modules" ] || die "asar extract produced no node_modules (asar CLI issue)"

pjson() { # $1 = node_modules path (relative), $2 = field
  # Note: the key must be quoted in the emitted JS (obj["version"], not obj[version]).
  node -e "try{console.log(require('$ASAR_DIR/node_modules/$1/package.json')[\"$2\"]||'')}catch(e){}" 2>/dev/null
}

ENA_VER="$(pjson electron-native-auth version)"
FHI_VER="$(pjson file-handler-info version)"
SDU_VER="$(pjson @tinyspeck/slack-desktop-utils version)"
NKM_SCOPED_VER="$(pjson @tinyspeck/native-keymap version)"
NAPI_VER="$(node -e "try{console.log(require('$ASAR_DIR/node_modules/@tinyspeck/slack-desktop-utils/package.json').binary.napi_versions[0])}catch(e){}" 2>/dev/null)"

[ -n "$ENA_VER" ] || die "could not read electron-native-auth version from app.asar"
[ -n "$FHI_VER" ] || die "could not read file-handler-info version from app.asar"
[ -n "$SDU_VER" ] || die "could not read slack-desktop-utils version from app.asar"
NAPI_VER="${NAPI_VER:-8}"

# Public `native-keymap` fork (npm dist-tag or semver). Slack's private
# @tinyspeck/native-keymap versioning differs, so pin the public fork explicitly.
NATIVE_KEYMAP_VERSION="${NATIVE_KEYMAP_VERSION:-2.5.0}"

log "electron-native-auth=$ENA_VER  file-handler-info=$FHI_VER  slack-desktop-utils=$SDU_VER  napi-v$NAPI_VER  native-keymap=$NATIVE_KEYMAP_VERSION (scoped=$NKM_SCOPED_VER)"

cat > "$BUILD/versions.env" <<EOF
ELECTRON_VERSION=$ELECTRON_VERSION
SLACK_VERSION=$SLACK_VERSION
ENA_VER=$ENA_VER
FHI_VER=$FHI_VER
SDU_VER=$SDU_VER
NAPI_VER=$NAPI_VER
NKM_SCOPED_VER=$NKM_SCOPED_VER
NATIVE_KEYMAP_VERSION=$NATIVE_KEYMAP_VERSION
EOF
log "Stage 02 done (wrote $BUILD/versions.env)"
