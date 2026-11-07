#!/usr/bin/env bash
#
# common.sh — shared environment + helpers for the native build stage scripts.
# Sourced by 01..05. Location-agnostic so the scripts can also be exercised on
# the host (set SLACK_WORK to a local dir) or inside the container (default /work).
#
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SLACK_VERSION="${SLACK_VERSION:?SLACK_VERSION must be set (env or .env)}"
export WORK="${SLACK_WORK:-/work}"
export SRC="$WORK/src"
export BUILD="$WORK/build"
export OUT="$WORK/out"
# Persistent cache for the (large, ~100 MB) Slack source package so repeated
# builds don't re-download it. Kept across runs (unlike the per-build $BUILD dir),
# and lives in the repo tree (git-ignored) rather than /tmp, so it survives
# small tmpfs/ramfs /tmp mounts. CI typically clears the workspace, so this is a
# no-op there.
export CACHE="${SLACK_CACHE_DIR:-$WORK/cache}"
export APP_ROOT="$BUILD/app"
export SCRIPTS

mkdir -p "$BUILD" "$OUT" "$CACHE"

log() { printf '\n\033[1;33m[%s] %s\033[0m\n' "$(basename "${BASH_SOURCE[0]}")" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
