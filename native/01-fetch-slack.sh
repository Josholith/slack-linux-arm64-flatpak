#!/usr/bin/env bash
#
# 01-fetch-slack.sh — Obtain + extract the official Slack package (amd64 .deb or
# x86_64 .rpm) and normalize its app tree to $APP_ROOT plus meta files (desktop,
# icon, metainfo). A local package is the reliable path; download is best-effort.
#
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PKG=""
if [ -f "$SRC/slack-package" ]; then
  PKG="$SRC/slack-package"
  log "Using local Slack package: $PKG"
else
  log "No local package staged ($SRC/slack-package) — attempting download"
  candidates=()
  [ -n "${SLACK_SOURCE_URL:-}" ] && candidates+=("$SLACK_SOURCE_URL")
  # Official Slack CDN. Confirmed working with plain curl (no special headers,
  # no WAF block): HTTP 200, ~100 MB/s. Pattern comes from the Arch AUR
  # slack-desktop PKGBUILD: <ver> and <ver> appear in both the path and filename.
  candidates+=(
    "https://downloads.slack-edge.com/desktop-releases/linux/x64/${SLACK_VERSION}/slack-desktop-${SLACK_VERSION}-amd64.deb"
  )
  for u in "${candidates[@]}"; do
    log "Trying: $u"
    if curl -fL --retry 2 --max-time 300 -A "$SLACK_DOWNLOAD_UA" -o "$SRC/slack-package" "$u"; then
      PKG="$SRC/slack-package"; break
    fi
  done
  [ -n "$PKG" ] && [ -s "$PKG" ] || die "Could not obtain the Slack package. Download the official amd64 .deb (or x86_64 .rpm) from https://slack.com/download and set SLACK_SOURCE_FILE in .env"
fi

sha256sum "$PKG" | awk '{print $1}' > "$BUILD/input-sha256.txt"
case "$PKG" in
  *.deb) TYPE=deb ;;
  *.rpm) TYPE=rpm ;;
  *)
    case "$(file -b "$PKG" 2>/dev/null || true)" in
      *'Debian binary package'*) TYPE=deb ;;
      *'RPM'* | *'ar archive'*)   TYPE=rpm ;;
      *) die "Unknown package type for: $PKG (expected .deb or .rpm)" ;;
    esac ;;
esac

log "Extracting ($TYPE) to $BUILD/extracted"
mkdir -p "$BUILD/extracted"
if [ "$TYPE" = deb ]; then
  dpkg-deb -x "$PKG" "$BUILD/extracted"
else
  bsdtar -xf "$PKG" -C "$BUILD/extracted"
fi

# Locate the app tree (dir that holds the `slack` binary + resources/).
APP_SRC=""
for d in "$BUILD/extracted/opt/slack" "$BUILD/extracted/usr/lib/slack"; do
  [ -d "$d" ] && { APP_SRC="$d"; break; }
done
[ -n "$APP_SRC" ] || die "Could not find the app tree (opt/slack or usr/lib/slack) in the package"
log "App tree: $APP_SRC"

mkdir -p "$APP_ROOT"
cp -a "$APP_SRC/." "$APP_ROOT/"

# Capture desktop entry / icon (paths vary by Slack build; Slack ships no
# .metainfo.xml). Best-effort: find_meta must never fail the build, so it always
# returns 0 even when nothing is found (matters under `set -e` when it's the
# last command of an `||` list).
mkdir -p "$BUILD/meta"
find_meta() { # $1=basename, $2=search-root
  local hit
  hit="$(find "$2" -name "$1" 2>/dev/null | head -1 || true)"
  [ -n "$hit" ] && cp -a "$hit" "$BUILD/meta/$1"
  return 0
}
find_meta "slack.desktop" "$BUILD/extracted"
find_meta "slack.png"     "$BUILD/extracted/usr/share"
[ -f "$BUILD/meta/slack.png" ] || find_meta "slack.png" "$BUILD/extracted"
[ -f "$BUILD/meta/slack.metainfo.xml" ] || find_meta "slack.metainfo.xml" "$BUILD/extracted"

[ -f "$APP_ROOT/slack" ]                || die "app tree has no 'slack' binary"
[ -f "$APP_ROOT/resources/app.asar" ]   || die "app tree has no resources/app.asar"
echo "meta files: $(ls -1 "$BUILD/meta" 2>/dev/null | tr '\n' ' ')"
log "Stage 01 done (input sha256=$(cat "$BUILD/input-sha256.txt"))"
