#!/bin/sh
#
# slack-install.sh — runs inside the flatpak build sandbox. The extracted
# payload (slack-<VER>-arm64/) and this script share the current directory.
# Installs the app into /app. (build.sh seds @APP_ID@ before running.)
#
set -e

APP_ID="@APP_ID@"
SRC_DIR="$(ls -d slack-*-arm64 | head -1)"
[ -n "$SRC_DIR" ] || { echo "payload dir not found"; exit 1; }

# 1) app tree: Electron binary + libs + resources + native modules
mkdir -p /app/slack
cp -a "$SRC_DIR/." /app/slack/

# 2) launcher on PATH. The setuid chrome-sandbox is not usable inside a sandbox,
#    so disable the SUID sandbox (Electron falls back to/without the ns sandbox).
mkdir -p /app/bin
cat > /app/bin/slack <<'LAUNCHER'
#!/bin/sh
exec /app/slack/slack --no-sandbox --disable-gpu-sandbox "$@"
LAUNCHER
chmod 755 /app/bin/slack /app/slack/slack

# 3) desktop entry
mkdir -p /app/share/applications
cat > "/app/share/applications/${APP_ID}.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Slack
Comment=Slack Desktop
Exec=slack
Icon=slack
Terminal=false
Categories=Network;InstantMessaging;
MimeType=x-scheme-handler/slack;
StartupWMClass=Slack
DESK

# 4) icon
mkdir -p /app/share/icons/hicolor/256x256/apps
cp -f /app/slack/slack.png /app/share/icons/hicolor/256x256/apps/slack.png

echo "slack installed into /app (app_id=$APP_ID)"
