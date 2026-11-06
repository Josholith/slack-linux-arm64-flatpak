#!/usr/bin/env bash
#
# build-all.sh — run the native build stages in order (inside the native image,
# or on the host for arch-agnostic stages). Produces:
#   $WORK/out/slack-<VER>-arm64.tar.xz
#   $WORK/out/build-inputs.json
#
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

S="$SCRIPTS"
for stage in \
    01-fetch-slack.sh \
    02-detect-versions.sh \
    03-arm64-electron.sh \
    04-build-native.sh \
    05-assemble.sh
do
  echo
  echo "======================== $stage ========================"
  bash "$S/$stage"
done

PAYLOAD="$OUT/slack-$SLACK_VERSION-arm64.tar.xz"
[ -f "$PAYLOAD" ] || die "payload was not produced: $PAYLOAD"
echo
echo "PAYLOAD OK: $PAYLOAD ($(du -h "$PAYLOAD" | cut -f1))"
