#!/bin/zsh
# Build-only. Does not install, restart services, register login, or notarize.
set -euo pipefail
cd "${0:A:h}"
python_cmd="${OMAC_BUILD_PYTHON:-$(command -v python3)}"
identity="${OMAC_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
 identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1)"
fi
identity="${identity:--}"
version=1.2.4-preview
build_number=124
source_commit="$(git rev-parse HEAD)"
arch="$(uname -m)"
out="$PWD/dist"
stage="$out/staging"
app="$stage/Omac.app"
[[ ! -e "$app" ]] || { print -u2 'Existing staging app: move dist aside before rebuilding.'; exit 1; }
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Payload/config" "$app/Contents/Resources/Payload/branding/wallpapers"
cat Launcher.swift WindowCycle.swift FocusBorder.swift AppShelf.swift ShelfPanel.swift AppFavorites.swift > "$stage/main.swift"
swiftc -O -target "$arch-apple-macosx14.0" "$stage/main.swift" -o "$app/Contents/MacOS/AgentControlCenter" -framework Cocoa -framework ApplicationServices -framework WebKit -framework ServiceManagement
rm "$stage/main.swift"
cp Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :OmacSourceCommit string $source_commit" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$app/Contents/Info.plist"
cp branding/Omac.png "$app/Contents/Resources/Payload/branding/"
cp branding/Omac.icns "$app/Contents/Resources/"
cp tile_modes.py control.py watcher.py portable_paths.py generate_config.py mac_switch.py Guide.html "$app/Contents/Resources/Payload/"
cp config/ghostty.conf "$app/Contents/Resources/Payload/config/"
cp branding/wallpapers/omac-{amber-forge,silver-ice,jungle,sky,ghost,grim-reaper}.png "$app/Contents/Resources/Payload/branding/wallpapers/"
cp LICENSE "$app/Contents/Resources/LICENSE"
codesign --force --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
cp DISTRIBUTION.md "$stage/START HERE.md"
cp LICENSE "$stage/LICENSE"
cp "Install Omac.command" "$stage/Install Omac.command"
chmod +x "$stage/Install Omac.command"
ln -s /Applications "$stage/Applications"
"$python_cmd" -m unittest discover -p 'test_*.py'
hdiutil create -volname "Omac Preview" -srcfolder "$stage" -format UDZO "$out/Omac-$version-$arch.dmg"
hdiutil verify "$out/Omac-$version-$arch.dmg"
(cd "$out" && shasum -a 256 "Omac-$version-$arch.dmg" > "Omac-$version-$arch.dmg.sha256")
print "Built $out/Omac-$version-$arch.dmg — development preview, not a notarized public release."
