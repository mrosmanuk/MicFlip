#!/usr/bin/env bash
#
# Builds MicFlip into a runnable, ad-hoc-signed .app bundle.
#
#   ./build.sh            # release build -> ./build/MicFlip.app
#   ./build.sh --debug    # debug build
#   ./build.sh --run      # build, then launch the app
#
set -euo pipefail

CONFIG="release"
RUN=0
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --run)   RUN=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MicFlip"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Compiling ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_PATH="$(swift build -c "$CONFIG" --product "$APP_NAME" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/LICENSE" "$RES_DIR/LICENSE"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Prefer a stable self-signed identity so macOS privacy grants (Input
# Monitoring, Microphone) survive rebuilds. Falls back to ad-hoc.
SIGN_ID="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "MicFlip Dev"; then
    SIGN_ID="MicFlip Dev"
    echo "==> Signing with stable identity 'MicFlip Dev'…"
else
    echo "==> Signing ad-hoc (run ./setup-signing.sh once for a persistent identity)…"
fi
codesign --force --sign "$SIGN_ID" \
    --entitlements "$ROOT/Resources/MicFlip.entitlements" \
    "$APP_DIR"

echo "==> Done: $APP_DIR"

if [[ "$RUN" -eq 1 ]]; then
    echo "==> Launching…"
    # Kill any previous instance so permissions/state reload cleanly.
    killall "$APP_NAME" 2>/dev/null || true
    open "$APP_DIR"
fi
