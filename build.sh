#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p bin
/opt/homebrew/bin/python3 generate_config.py
/usr/bin/swiftc Launcher.swift -o bin/AgentControlCenter -framework Cocoa -framework ApplicationServices -framework WebKit
branding/screensaver/build.sh
/usr/bin/codesign --force --sign - branding/screensaver/build/OMAC.saver
/usr/bin/codesign --force --sign - branding/screensaver/build/OMAC-Preview.app
/opt/homebrew/bin/python3 -m unittest discover -p 'test_*.py'
/usr/bin/plutil -lint launchd/*.plist
