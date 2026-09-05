#!/bin/bash
# Optional recovery when macOS rejects the upstream downloaded release.
# Requires full Xcode 26+. Compiles source locally; never changes Gatekeeper.
set -euo pipefail
SOURCE_COMMIT=8830219a8b390e6ca7cec93b3574e1d0e4331c15
DESTINATION="$HOME/Library/Application Support/MacBedrock/Runtime"
APP_NAME='Minecraft Bedrock Launcher.app'
if [ "$(uname -m)" != arm64 ]; then
  echo 'Run this script natively on an Apple Silicon Mac.' >&2
  exit 1
fi
xcrun --find actool >/dev/null
if [ -e "$DESTINATION/$APP_NAME" ]; then
  echo "An app already exists at $DESTINATION/$APP_NAME. Move it aside first; no files were changed." >&2
  exit 1
fi
BUILD_WORK="$(mktemp -d "${TMPDIR:-/tmp}/MacBedrock-source.XXXXXX")"
STAGING=""
cleanup() {
  rm -rf "$BUILD_WORK"
  if [ -n "$STAGING" ]; then rm -rf "$STAGING"; fi
}
trap cleanup EXIT
git clone --depth 1 --branch v0.1.13 https://github.com/hugonote/mcpelauncher-swift.git "$BUILD_WORK/source"
if [ "$(git -C "$BUILD_WORK/source" rev-parse HEAD)" != "$SOURCE_COMMIT" ]; then
  echo 'Upstream tag changed unexpectedly. Refusing to build.' >&2
  exit 1
fi
APP_VERSION=0.1.13 "$BUILD_WORK/source/Scripts/build-app-bundle.sh"
BUILT_APP="$BUILD_WORK/source/.build/app/$APP_NAME"
codesign --verify --deep --strict "$BUILT_APP"
mkdir -p "$DESTINATION"
STAGING="$(mktemp -d "$DESTINATION/.source-install.XXXXXX")"
ditto "$BUILT_APP" "$STAGING/$APP_NAME"
# Rename is no-clobber, and stays on the destination volume.
mv -n "$STAGING/$APP_NAME" "$DESTINATION/$APP_NAME"
if [ -e "$STAGING/$APP_NAME" ]; then
  echo 'Another installation appeared while building. It was left untouched.' >&2
  exit 1
fi
printf 'Local source build installed. Open MacBedrock and choose Open Bedrock launcher.\n'
