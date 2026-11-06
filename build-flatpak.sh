#!/usr/bin/env bash
#
# build-flatpak.sh — runs INSIDE the flatpak Docker image. Builds a
# self-contained `.flatpak` bundle from the staged manifest + payload tarball,
# both located in /work.
#
set -euo pipefail
cd /work
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

echo "flatpak:      $(flatpak --version 2>/dev/null || echo n/a)"
echo "builder:      $(flatpak-builder --version 2>/dev/null || echo n/a)"
echo "arch=$FLATPAK_ARCH  runtime=$FLATPAK_RUNTIME/$FLATPAK_RUNTIME_VERSION  app=$SLACK_APP_ID"

# Make the base resolvable and PRE-INSTALL the exact base refs. Flathub serves
# org.gnome.{Sdk,Platform} for every arch (incl. aarch64). flatpak-builder 1.4.x
# expects them already present and will not pull them itself, so install them
# explicitly. Use FULL refs (id/arch/branch) — "id:branch" is rejected by
# flatpak 1.16.
: "${FLATPAK_SDK:=org.gnome.Sdk}"
flatpak remote-add --if-not-exists --user flathub "$FLATPAK_REMOTE_URL"
flatpak install --user -y --noninteractive flathub \
  "$FLATPAK_SDK/$FLATPAK_ARCH/$FLATPAK_RUNTIME_VERSION" \
  "$FLATPAK_RUNTIME/$FLATPAK_ARCH/$FLATPAK_RUNTIME_VERSION"

# Build the app layer: runs the (copy-only) module against the installed base,
# and emits a local repo for build-bundle.
flatpak-builder --force-clean --user --arch="$FLATPAK_ARCH" \
  --repo=repo build-dir manifest.json

# Sanity: the base + built app should now be present in the user installation.
flatpak --user list

# Produce a self-contained bundle. flatpak (1.16+) signature:
#   build-bundle [OPTION...] LOCATION FILENAME NAME [BRANCH]
# LOCATION = the repo dir (from flatpak-builder --repo), FILENAME = output,
# NAME = app-id. Arch + the runtime's source repo are option flags, NOT positionals.
mkdir -p /out
OUT="/out/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
flatpak build-bundle \
  --arch="$FLATPAK_ARCH" \
  --runtime-repo="$FLATPAK_REMOTE_URL" \
  repo "$OUT" "$SLACK_APP_ID"

echo
echo "BUNDLE OK: $OUT ($(du -h "$OUT" | cut -f1))"
