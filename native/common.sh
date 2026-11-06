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
export APP_ROOT="$BUILD/app"
export SCRIPTS
export SLACK_DOWNLOAD_UA="${SLACK_DOWNLOAD_UA:-Mozilla/5.0 (X11; Linux aarch64)}"

mkdir -p "$BUILD" "$OUT"

log() { printf '\n\033[1;33m[%s] %s\033[0m\n' "$(basename "${BASH_SOURCE[0]}")" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
