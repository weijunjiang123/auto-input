#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AutoInput"
APP_VERSION="${APP_VERSION:-$(<"$ROOT_DIR/VERSION")}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_STAGE_DIR="$ROOT_DIR/.build/dmg"
DMG_NAME="${DMG_NAME:-$APP_NAME-$APP_VERSION-macOS.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME $APP_VERSION}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle: $APP_DIR" >&2
  echo "Run Scripts/build_app.sh before creating the DMG." >&2
  exit 1
fi

rm -rf "$DMG_STAGE_DIR" "$DMG_PATH"
mkdir -p "$DMG_STAGE_DIR" "$DIST_DIR"

cp -R "$APP_DIR" "$DMG_STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

sync

for attempt in {1..5}; do
  if hdiutil verify "$DMG_PATH" >/dev/null; then
    echo "$DMG_PATH"
    exit 0
  fi

  echo "DMG verification failed, retrying ($attempt/5)..." >&2
  sleep 2
done

hdiutil verify "$DMG_PATH"
