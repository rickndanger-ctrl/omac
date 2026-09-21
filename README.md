# Terminal Control Center

Open Agent Control Center in Applications, then choose Open / Arrange 4 Terminals or Open / Arrange 6 Terminals in the ▦ menu. These are plain Ghostty shells; launch any agents yourself. No agent, browser, or desktop app is started automatically.

Guide.html lists the shortcuts. Command substitutes for Omarchy Super for directional focus, swapping, terminal launch, and fullscreen. Resizing uses AeroSpace semantics. Four windows form two columns of two, six form three columns of two. Existing fifth/sixth windows are preserved when selecting four. New Terminal adds one up to six.

The source and isolated configuration live in this Git repository. Commit changes before restarting services. Menu and AeroSpace helpers run under launchd; terminal jobs use open -W to track Ghostty instances. No jobs are installed for login startup. Existing agent launch jobs and wrapper are retired.

Pause releases window management and shortcuts. Exit also stops the owned manager and attempts to restore pre-existing window geometry. Terminal sessions remain open. Closing terminals or rebooting does not preserve their foreground sessions.

Rollback: run `/opt/homebrew/bin/python3 control.py rollback` from this repository. This disables Control Center without closing terminals. Dependency apps remain installed.

Build Launcher.swift using swiftc with Cocoa and ApplicationServices, install its executable into /Applications/Agent Control Center.app/Contents/MacOS, then codesign the bundle. generate_config.py regenerates dedicated config and launchd plists. Run test_controller.py for lifecycle checks. See VERIFICATION.md for live testing limits.

## Window controls and appearance
Command-K opens the native shortcut panel. Command-O toggles a terminal between centered floating and tiled. Command-T also toggles floating/tiled. Command-F enlarges within the workspace; Command-Option-F toggles native macOS fullscreen. Option-Tab cycles windows and Command-B (also Command-Shift-equals) balances the Terminals workspace. New terminal instances load config/ghostty.conf (85% opacity and blur 16); running sessions retain their existing appearance until reopened. Native macOS fullscreen disables transparency. Build now also links WebKit.
