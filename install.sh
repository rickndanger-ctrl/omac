#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
identity="${OMAC_SIGN_IDENTITY:?Set OMAC_SIGN_IDENTITY to the existing Apple Development identity}"
app=/Applications/Omac.app
if [[ -d '/Applications/Agent Control Center.app' && ! -d "$app" ]]; then
 mv '/Applications/Agent Control Center.app' "$app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp bin/AgentControlCenter "$app/Contents/MacOS/AgentControlCenter"
cp Info.plist "$app/Contents/Info.plist"
cp branding/Omac.icns "$app/Contents/Resources/Omac.icns"
codesign --force --deep --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
launchctl bootout "gui/$(id -u)/com.richard.acc.menu" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PWD/launchd/menu.plist"
launchctl kickstart "gui/$(id -u)/com.richard.acc.menu"
/opt/homebrew/bin/python3 control.py enable-login
