# Terminal Control Center

Open Agent Control Center in Applications, then choose Open / Arrange 4 Terminals or Open / Arrange 6 Terminals in the ▦ menu. These are plain Ghostty shells; launch any agents yourself. No agent, browser, or desktop app is started automatically.

Guide.html lists the shortcuts. Command substitutes for Omarchy Super for directional focus, swapping, terminal launch, and fullscreen. Resizing uses AeroSpace semantics. Four windows form two columns of two, six form three columns of two. Existing fifth/sixth windows are preserved when selecting four. New Terminal adds one up to six.

The source and isolated configuration live in this Git repository. Commit changes before restarting services. Menu and AeroSpace helpers run under launchd; terminal jobs use open -W to track Ghostty instances. No jobs are installed for login startup. Existing agent launch jobs and wrapper are retired.

Pause releases window management and shortcuts. Exit also stops the owned manager and attempts to restore pre-existing window geometry. Terminal sessions remain open. Closing terminals or rebooting does not preserve their foreground sessions.

Rollback: run `/opt/homebrew/bin/python3 control.py rollback` from this repository. This disables Control Center without closing terminals. Dependency apps remain installed.

Build Launcher.swift using swiftc with Cocoa and ApplicationServices, install its executable into /Applications/Agent Control Center.app/Contents/MacOS, then codesign the bundle. generate_config.py regenerates dedicated config and launchd plists. Run test_controller.py for lifecycle checks. See VERIFICATION.md for live testing limits.

## Window controls and appearance
Command-K opens the native shortcut panel. Command-O toggles a terminal between centered floating and tiled. Command-T also toggles floating/tiled. Command-F enlarges within the workspace; Command-Option-F toggles native macOS fullscreen. Option-Tab cycles windows and Command-B (also Command-Shift-equals) balances the Terminals workspace. New terminal instances load config/ghostty.conf (85% opacity and blur 16); running sessions retain their existing appearance until reopened. Native macOS fullscreen disables transparency. Build now also links WebKit.

## Desktop shortcuts
While Control Center is active: Command-Option-C opens Claude; H opens Hermes; G opens Codex (using its verified com.openai.codex bundle identifier); B opens Chrome; E opens Finder. Layout resets now send one batched request and preserve the focused terminal.

## Five pages
Command–1 through Command–5 selects that page. Command–Shift–1 through 5 moves the focused window there without following it. Pages start empty; current windows migrate once to page 1. New normal app windows tile on the current page. Existing app launch shortcuts may focus their existing window on another page. App minimum sizes cannot be overridden.

Enter / Resume Five Pages does not create terminals. Command–Return creates one terminal (maximum six per page, thirty managed terminals total). Four / Six arrange only the current page. Command–O centers or returns any focused window to tiling.

Page membership persists while switching and pausing. Orderly Exit saves membership for still-running windows on re-entry; exact tile trees are not restored after manager termination. Abrupt manager crashes and macOS restarts are not guaranteed to restore page assignments. No terminal sessions are closed by Exit. AeroSpace pages are virtual workspaces, separate from Mission Control Spaces.

Rollback for this update: git revert the five-page commit, regenerate configuration with generate_config.py, then rebuild Launcher.swift and reload the configuration. To disable all management without stopping terminal sessions, run control.py rollback.

Adding a terminal with Command–Return rebuilds the current page’s terminal grid, matching Four / Six: pairs form rows within columns. Other pages are untouched.

The compact shortcut guide uses an 85% opaque dark background and neutral text. Command–K brings it to the current page. The menu bar now includes Apps and Settings. New Command–Option shortcuts: R Cursor, V VS Code, T Telegram, I Messages, M Mail, S System Settings. App launch shortcuts open/focus existing apps; use their New Window command to create a window on another page.
