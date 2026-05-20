#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BrowserSwitch"
AGENT_ID="local.mac-browser-switch"

DEST_APP="/Applications/$APP_NAME.app"
LEGACY_USER_APP="$HOME/Applications/$APP_NAME.app"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_ID.plist"

launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" >/dev/null 2>&1 || true
pkill -f "$DEST_APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
pkill -f "$LEGACY_USER_APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
rm -f "$AGENT_PLIST"
rm -rf "$DEST_APP"
rm -rf "$LEGACY_USER_APP"

echo "Uninstalled $APP_NAME"
