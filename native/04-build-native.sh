#!/usr/bin/env bash
#
# 04-build-native.sh — Produce aarch64 versions of every native module under
# app.asar.unpacked:
#   * electron-native-auth, file-handler-info  -> built from public npm (node-gyp)
#   * @tinyspeck/native-keymap                 -> built from the public `native-keymap` fork
#   * @tinyspeck/slack-desktop-utils           -> arm64 prebuild from Slack's S3 (proprietary)
#   * cf-prefs / registry-js / windows-focus-assist / macos-notification-state
#                                                   -> minimal arm64 N-API stub (Linux no-op)
#
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
. "$BUILD/versions.env"

UNPACKED="$APP_ROOT/resources/app.asar.unpacked/node_modules"
[ -d "$UNPACKED" ] || die "missing $UNPACKED"

copy_node() { # $1=built .node, $2=dest
  local built="$1" dest="$2"
  [ -f "$built" ] || die "built .node not found: $built"
  file -b "$built" | grep -qi 'aarch64' || die "$built is not aarch64: $(file -b "$built")"
  mkdir -p "$(dirname "$dest")"
  cp -f "$built" "$dest"
  echo "  $(basename "$dest")  <-  $built"
}

# --- 1) public npm modules -----------------------------------------------------
log "Building native modules from source (aarch64)"
WS="$BUILD/native"
rm -rf "$WS"; mkdir -p "$WS"; cd "$WS"
npm init -y >/dev/null 2>&1
# Install sources WITHOUT running lifecycle scripts (npm's script policy varies by
# version, e.g. npm 12's "allowScripts" gating). We then build each module explicitly
# with node-gyp, which is version-independent. All three are node-gyp modules (binding.gyp).
npm install --no-audit --no-fund --ignore-scripts \
    "native-keymap@$NATIVE_KEYMAP_VERSION" \
    "electron-native-auth@$ENA_VER" \
    "file-handler-info@$FHI_VER"

build_module() { # $1 = package dir name
  local dir="$WS/node_modules/$1"
  [ -d "$dir" ] || die "module dir missing: $dir"
  [ -f "$dir/binding.gyp" ] || die "no binding.gyp in $dir (expected a node-gyp module)"
  log "node-gyp rebuild: $1"
  ( cd "$dir" && npx --yes node-gyp rebuild ) || die "node-gyp rebuild failed for $1"
}
build_module native-keymap
build_module electron-native-auth
build_module file-handler-info

find_built() { find "$WS/node_modules/$1" -path '*/build/Release/*.node' 2>/dev/null | head -1; }
NKM_NODE="$(find_built native-keymap)"
ENA_NODE="$(find_built electron-native-auth)"
FHI_NODE="$(find_built file-handler-info)"
[ -n "$NKM_NODE" ] || die "native-keymap build produced no .node"
[ -n "$ENA_NODE" ] || die "electron-native-auth build produced no .node"
[ -n "$FHI_NODE" ] || die "file-handler-info build produced no .node"

copy_node "$NKM_NODE" "$UNPACKED/@tinyspeck/native-keymap/build/Release/keymapping.node"
copy_node "$ENA_NODE" "$UNPACKED/electron-native-auth/build/Release/electron_native_auth.node"
copy_node "$FHI_NODE" "$UNPACKED/file-handler-info/build/Release/file_handler_info.node"

# --- 2) proprietary slack-desktop-utils: arm64 prebuild from Slack S3 ----------
log "Downloading slack-desktop-utils v$SDU_VER arm64 prebuild (napi-v$NAPI_VER)"
SDU_TAR="$BUILD/sdu.tar.gz"
SDU_URL="https://slack-desktop-native-prebuilds.s3.amazonaws.com/slackdesktoputils-v${SDU_VER}-napi-v${NAPI_VER}-linux-arm64.tar.gz"
curl -fL --retry 3 --max-time 300 -o "$SDU_TAR" "$SDU_URL"
sha256sum "$SDU_TAR" | awk '{print $1}' > "$BUILD/sdu-sha256.txt"
mkdir -p "$BUILD/sdu"; tar xzf "$SDU_TAR" -C "$BUILD/sdu"
SDU_NODE="$(find "$BUILD/sdu" -name 'slackdesktoputils.node' 2>/dev/null | head -1)"
[ -n "$SDU_NODE" ] || die "slackdesktoputils.node not found in prebuild (does Slack publish an arm64 build for v$SDU_VER?)"
copy_node "$SDU_NODE" "$UNPACKED/@tinyspeck/slack-desktop-utils/lib/binding/napi-v${NAPI_VER}/slackdesktoputils.node"

# --- 3) platform no-op modules -> arm64 N-API stub -----------------------------
log "Compiling arm64 N-API stub for no-op modules"
gcc -shared -fPIC -o "$BUILD/empty_module.node" "$SCRIPTS/stubs/empty_napi_module.c"
for m in \
  "cf-prefs/build/Release/cf-prefs.node" \
  "registry-js/build/Release/registry.node" \
  "windows-focus-assist/build/Release/focusassist.node" \
  "macos-notification-state/build/Release/notificationstate.node"
do
  if [ -e "$UNPACKED/$m" ]; then
    mkdir -p "$(dirname "$UNPACKED/$m")"
    cp -f "$BUILD/empty_module.node" "$UNPACKED/$m"
    echo "  stub -> $m"
  fi
done

# --- 4) verify every .node in the payload is aarch64 ---------------------------
log "Verifying all native modules are aarch64"
BAD=""
while IFS= read -r f; do
  file -b "$f" | grep -qi 'aarch64' || BAD="$BAD$f
"
done < <(find "$APP_ROOT/resources/app.asar.unpacked" -name '*.node')
[ -z "$BAD" ] || die "non-aarch64 native modules:
$BAD"
log "Stage 04 done"
