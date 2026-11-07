#!/usr/bin/env bash
#
# build-flatpak.sh — runs INSIDE the flatpak Docker image (as root). Builds a
# self-contained `.flatpak` bundle from the staged manifest + payload tarball in
# /work. Root is required: flatpak-builder's rofiles-fuse helper can't resolve a
# bare non-root UID that isn't in the sandbox's /etc/passwd. The aarch64
# runtime is cached in the (host-mounted) user-install state dir.
#
set -euo pipefail
cd /work

# Runs as ROOT: flatpak-builder's rofiles-fuse helper (fusermount3) cannot
# resolve a bare non-root UID that isn't in the sandbox's /etc/passwd, so the
# build fails for a non-root user ("could not determine username"). Root is
# resolvable and works. User-install state lives under /root/.local/share/
# flatpak, mounted from a host dir so the aarch64 runtime is cached across
# builds. (The host dir ends up root-owned; a sudo-less host user can't clean
# it, but CI runners clear the workspace, so it's a non-issue in CI.)
export XDG_RUNTIME_DIR=/tmp/runtime-root
export FLATPAK_USER_DATA=/root/.local/share/flatpak
mkdir -p "$FLATPAK_USER_DATA" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

echo "flatpak:   $(flatpak --version 2>/dev/null || echo n/a)"
echo "builder:   $(flatpak-builder --version 2>/dev/null || echo n/a)"
echo "arch=$FLATPAK_ARCH  runtime=$FLATPAK_RUNTIME/$FLATPAK_RUNTIME_VERSION  app=$SLACK_APP_ID"
echo "state:     $FLATPAK_USER_DATA"

# Make the base resolvable and PRE-INSTALL the exact base refs (SDK + runtime)
# into the USER installation. Flathub serves org.gnome.{Sdk,Platform} for every
# arch (incl. aarch64). flatpak-builder expects them present and won't pull them
# itself, so install explicitly. FULL refs (id/arch/branch) — "id:branch" is
# rejected by flatpak 1.16.
: "${FLATPAK_SDK:=org.gnome.Sdk}"
flatpak remote-add --if-not-exists --user flathub "$FLATPAK_REMOTE_URL"
flatpak install --user -y --noninteractive flathub \
  "$FLATPAK_SDK/$FLATPAK_ARCH/$FLATPAK_RUNTIME_VERSION" \
  "$FLATPAK_RUNTIME/$FLATPAK_ARCH/$FLATPAK_RUNTIME_VERSION"

# Build the app layer against the installed base (aarch64 runtime sandbox), then
# emit a local repo for build-bundle. (elfutils/eu-strip is in the image for the
# debuginfo strip step.)
flatpak-builder --force-clean --user --arch="$FLATPAK_ARCH" \
  --repo=repo build-dir manifest.json

flatpak --user list

# Produce a self-contained bundle into /work (the user-owned mount).
# build-bundle (flatpak 1.16): LOCATION FILENAME NAME [BRANCH]; arch + the
# runtime's source repo are option flags, not positionals.
OUT="/work/$SLACK_APP_ID.$FLATPAK_ARCH.flatpak"
flatpak build-bundle \
  --arch="$FLATPAK_ARCH" \
  --runtime-repo="$FLATPAK_REMOTE_URL" \
  repo "$OUT" "$SLACK_APP_ID"

echo
echo "BUNDLE OK: $OUT ($(du -h "$OUT" | cut -f1))"
