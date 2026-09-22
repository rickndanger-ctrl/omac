#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/build/OMAC-Wallpaper.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
MIN_OS="14.0"
mkdir -p "$BUILD_DIR/Contents/MacOS" "$BUILD_DIR/Contents/Resources"
for wallpaper in emerald-glass storm-forge crimson-etch; do
  cp "$SCRIPT_DIR/../../../omac-visual-concepts/$wallpaper.png" "$BUILD_DIR/Contents/Resources/$wallpaper.png"
done
cp "$SCRIPT_DIR/../Omac.png" "$BUILD_DIR/Contents/Resources/Omac.png"
swiftc -sdk "$SDK" -target "$ARCH-apple-macosx$MIN_OS" -framework AppKit \
  "$SCRIPT_DIR/OmacRenderer.swift" "$SCRIPT_DIR/OmacWallpaper.swift" \
  -emit-executable -o "$BUILD_DIR/Contents/MacOS/OMAC-Wallpaper"
cp "$SCRIPT_DIR/OmacWallpaper-Info.plist" "$BUILD_DIR/Contents/Info.plist"
echo "Built $BUILD_DIR"
