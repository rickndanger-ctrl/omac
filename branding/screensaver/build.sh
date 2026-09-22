#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/build"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
MIN_OS="14.0"
ARCH="$(uname -m)"
mkdir -p "$BUILD_DIR/OMAC.saver/Contents/MacOS" "$BUILD_DIR/OMAC.saver/Contents/Resources" "$BUILD_DIR/OMAC-Preview.app/Contents/MacOS" "$BUILD_DIR/OMAC-Preview.app/Contents/Resources"
for wallpaper in emerald-glass storm-forge crimson-etch; do
  cp "$SCRIPT_DIR/../wallpapers/omac-$wallpaper.png" "$BUILD_DIR/OMAC.saver/Contents/Resources/$wallpaper.png"
  cp "$SCRIPT_DIR/../wallpapers/omac-$wallpaper.png" "$BUILD_DIR/OMAC-Preview.app/Contents/Resources/$wallpaper.png"
done

swiftc -sdk "$SDK" -target "$ARCH-apple-macosx$MIN_OS" -framework AppKit -framework ScreenSaver \
  "$SCRIPT_DIR/OmacRenderer.swift" "$SCRIPT_DIR/OmacScreenSaver.swift" \
  -emit-library -module-name OmacScreenSaver -Xlinker -bundle -Xlinker -undefined -Xlinker dynamic_lookup \
  -o "$BUILD_DIR/OMAC.saver/Contents/MacOS/OmacScreenSaver"
cp "$SCRIPT_DIR/Info.plist" "$BUILD_DIR/OMAC.saver/Contents/Info.plist"

swiftc -sdk "$SDK" -target "$ARCH-apple-macosx$MIN_OS" -framework AppKit \
  "$SCRIPT_DIR/OmacRenderer.swift" "$SCRIPT_DIR/OmacPreview.swift" \
  -emit-executable -o "$BUILD_DIR/OMAC-Preview.app/Contents/MacOS/OMAC-Preview"
cat > "$BUILD_DIR/OMAC-Preview.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OMAC-Preview</string>
<key>CFBundleIdentifier</key><string>com.richardholguin.omac.preview</string>
<key>CFBundleName</key><string>OMAC Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
</dict></plist>
PLIST
cp "$SCRIPT_DIR/../Omac.png" "$BUILD_DIR/OMAC.saver/Contents/Resources/Omac.png"
cp "$SCRIPT_DIR/../Omac.png" "$BUILD_DIR/OMAC-Preview.app/Contents/Resources/Omac.png"
echo "Built $BUILD_DIR/OMAC.saver and $BUILD_DIR/OMAC-Preview.app"
