# Current portable checkpoint — September 21, 2026

Remote keyboard routing: native activation observer releases host AeroSpace bindings while Screen Sharing is frontmost and restores them for local apps. Committed in both repositories, compiled successfully; installed on Mini 1 with its existing signing identity and menu-helper restart only. Live settled mode observations confirmed main for Screen Sharing and active for local Codex, then main again when returning remotely. Synthetic remote page/Settings keystrokes did not establish delivery; physical acceptance remains pending. Mini 2 and the distribution image have not received this routing update yet.

Focused controls check during voice session: all five active-mode page bindings selected the requested page on both Macs; original pages and all window ID/PID/page assignments were preserved. CLI dispatch returned in 24–87 ms on Mini 1 and 15–28 ms on Mini 2. These timings do not measure physical-key-to-painted-frame latency. All 18 portable tests pass. The menu counter refreshes every 1.5 seconds and may lag the actual workspace; no performance fix was deployed in this pass.

Screensaver report: Screen Sharing visibly showed macOS's password field over the animated Omac background. After Richard entered his password, the desktop appeared and he confirmed his screen was usable. Mini 2 has both a virtual and physical display; prompt placement on the user's physical display remains unverified. This establishes successful dismissal for that occurrence, not a permanent fix or a reason to weaken lock-screen security.

User acceptance update: Richard confirmed “command esc works” after the focus-rescue update. This resolves the physical Command–Escape acceptance gate for his reported workflow. It does not establish minimized-window recovery, all other shortcuts, reboot startup, or sleep/wake behavior. The earlier physical-key uncertainty below is historical and superseded for this shortcut.

Focus audit, ccbe119: fixed whitespace parsing of live layout names, skip floating entries when walking the current tree, reject snapshots from previous boots, and require the saved app instance/title and a confirmed minimized window for AX fallback. Main/portable suites pass 17/18 tests. Live Finder binding dispatch selected the expected first window on page 3. Synthetic Command-Escape sent by computer use did not produce the same result; physical-key delivery remains unproven. A minimized Finder test also did not restore: while other pages retained windows, the watcher discarded that individual window's saved entry. Earlier statements that minimized recovery was verified are superseded by this result. Test Finder windows were closed and page 1 restored. Do not claim full input or minimized-window acceptance yet.

Mini 2 portable aa37223: all five four-terminal grids, native login registration, branded bar, floating guide, repeated entry, disengage preservation, menu/watcher/AeroSpace restart preservation verified live. 16 automated tests and successful/failed installer integration runs pass. Actual reboot, sleep/wake, multiple displays, physical shortcut interception and native idle screensaver activation remain unverified. Historical entries below describe earlier builds and are not current blockers where superseded.

Command-Escape focus rescue was hardened and verified on both Macs. In each live test, focus started on the second of two tiled windows, rescue selected the first upper-left window, and the current Omac page did not change. Mini 2 had two active displays during this check; its test apps were returned to floating afterward. The watcher now preserves its last non-empty page checkpoint while AeroSpace temporarily reports no windows. The portable suite now has 17 passing tests. Direct typing into Ghostty after rescue still needs a hands-on check because the computer-control tool cannot operate Ghostty.

# Verification

## Working checkpoint — September 21, 2026

- The same Apple Development identity signs the installed app on both Macs. Replacing it with an ad-hoc build was the confirmed cause of the disappearing Device Control grant and yellow focus border; packaging now discovers and reuses the stable identity.
- macOS 27 routes Omac's permission control to **Device Control and Data Access**. Earlier macOS versions retain the Accessibility route.
- Mini 1 and Mini 2 both ran the signed helper with the animated wallpaper service enabled. The user visually confirmed Mini 2's yellow border; a separate WindowServer inventory also found Omac's visible border panel.
- The keyboard-only Screen Sharing handoff was physically confirmed in both directions. Screen Sharing remains outside the tile tree, and ShareMouse was removed without touching LAN Mouse.
- An upgrade-specific false alarm was reproduced: a running, Omac-owned AeroSpace config from the earlier checkout was mistaken for a foreign config by the portable controller. Omac now recognizes that guarded legacy state while continuing to refuse unrelated configurations.
- These checks establish the current working checkpoint. First install, a new signing identity, or a macOS permission reset still requires the user to grant control access. Reboot, sleep/wake, and every display topology are not exhaustively certified.

- macOS: 27.0 (26A428).
- Claude Code 2.1.274 and Codex CLI 0.149.0 version commands passed; Hermes help passed.
- Local Qwen launcher found and inspected; existing Full Local mode prerequisite preserved. No generation sent.
- Native menu application compiled and signed.
- Ghostty version command passed. Validation with launch options returned code 1 without diagnostics; terminal launch remains unresolved.
- No existing AeroSpace, skhd, or Hammerspoon configuration found at their usual paths; no running conflicting tiling manager found.
- No enabled macOS symbolic shortcut using precisely Control–Option found. Third-party and per-app shortcuts require interactive checking.
- Lifecycle unit tests cover repeated entry, preserving sessions on pause/exit, permission failure, and refusing a foreign AeroSpace configuration.

Pending live acceptance: Accessibility grants, four visible terminal launches, 2x2 geometry, Research tiling, real keyboard shortcuts, trackpad use, native dialogs/fullscreen, sleep/wake, monitor changes, crash recovery, and best-effort geometry restoration. Do not treat this first build as production-certified until those pass.

## Live run checkpoint

AeroSpace configuration loaded successfully after its v2 callback correction. ChatGPT, Claude, and Google Chrome appeared in the manager and were assigned to Research. One C27F390 display was detected. Window snapshot captured two pre-existing windows. Four supervised Ghostty launch attempts exited without producing the expected agent windows; a plain Ghostty launch remained running but produced no window visible to AeroSpace. Direct Ghostty UI inspection was blocked by the Computer Use tool for safety reasons. Enter now refuses to report success if any agent tile is missing and returns to inactive mode. Keyboard, physical trackpad, sleep/wake, crash recovery, and all-agent acceptance remain pending. Usage meter: 39% at start, 40% at this checkpoint.

## Terminal-only revision
User simplified scope to plain terminal windows. Removed automatic agent and Research-app launches. Native menu now offers four, six, or one added terminal. Live controller successfully opened/arranged six managed terminal windows. Re-entry count checked; title notification badges are normalized to prevent duplicate launches. Directional focus ignores floating nonterminal windows. Full physical keyboard/trackpad, sleep/wake, and monitor-change acceptance remains unverified.

## Shortcut panel and window controls
Native Terminal Shortcuts panel verified through its accessibility tree. Center action executed successfully via the Accessibility API, followed by return to tiling. AeroSpace fullscreen on/off commands passed. Updated AeroSpace config passed dry-run. Ghostty +validate-config accepted dedicated 94%-opacity / blur configuration. Existing terminal instances are preserved; transparency is only configured for subsequently launched instances and has not been visually verified. Native macOS fullscreen shortcut is configured but not exercised.

## Incremental opening
Command-Return live test increased managed windows from four to five, retained all original window IDs, and left Ghostty focused. Six lifecycle tests passed. New Terminal now skips reload/rearrange during an active session; non-help URL actions use background activation. Dark background config validates. Visual startup flash elimination remains unconfirmed.

## Reversible center and balance
Live center action changed the focused terminal from tiled to floating, then back to v_tiles on the second invocation. Resized a tile and successfully dispatched both cmd-b and cmd-shift-equal against the explicit Terminals workspace. Physical key delivery and pixel-equal geometry were not independently measured.

## Batched layouts and app shortcuts
Six-terminal reset completed in 0.167 seconds with the same window IDs. Seven tests pass, including one-batch layout and focus preservation. All five shortcut dispatches accepted; Claude, Hermes, Chrome, and Finder observed running. ChatGPT app-name ambiguity identified: ChatGPT.app is com.openai.codex, so the ChatGPT desktop shortcut targets ChatGPT Classic.app (com.openai.chat).

## Five-page update — 2026-09-21
- Ten controller tests pass; AeroSpace dry-run accepts generated configuration.
- Live trigger-binding checks passed for Command–1…5, and Command–Shift–2/3 moving the new page-2 terminal.
- Page switches preserved all existing window IDs and membership. Page 2 has one new empty terminal; pages 3–5 remain empty.
- Pause/Resume and orderly Exit/re-entry preserved window IDs and page membership without duplicate terminals.
- Finder and Ghostty tiled together on page 2 and survived switching away/back. Finder returned to its original page afterward.
- Fixed a real restore defect: generic `tiling` could return accordion stacks; explicit `h_tiles` passed the repeated lifecycle test. Page 1 was reset to the six-terminal grid afterward.
- No Ghostty processes were restarted or agents launched. Usage remained 41% at checkpoints.
- Not fully verified: physical key interception, visual transition quality, every app's minimum sizing, sleep/wake, multiple displays, abrupt AeroSpace crash recovery. Page assignments after abrupt crashes are not guaranteed. Exact nested tile trees are not persisted across Exit.

## Compact guide and everyday apps — 2026-09-21
- Live Command–K binding tests passed on pages 2, 4, and 1 without changing the selected page. The fixed-size nonactivating panel is intentionally outside AeroSpace's tile tree.
- Computer Use inspected the rendered 620×570 guide: neutral text, compact two-column layout, complete footer. Background opacity is configured at 0.85; text remains opaque.
- Computer Use sent Escape successfully; subsequent window inspection found no accessible guide window (the inspection tool reports a timeout when the window is dismissed).
- New Command–Option R/V/T/I/M/S bindings were triggered. AeroSpace's live app inventory confirmed Cursor, VS Code, Telegram, Messages, Mail, and System Settings running with the intended bundle IDs. Account setup and app-specific workflows were not changed.
- Apps and Settings menus are implemented; individual submenu selection and every Settings deep link still need interactive acceptance testing.
- Ten controller tests and the AeroSpace configuration dry-run pass.
- Not a claim of exhaustive reliability: sleep/wake, all display arrangements, every app's minimum sizes, and abrupt manager crash recovery remain unverified.

## Daily-use hardening and Omac branding — 2026-09-21
- Build, 14 controller/hardening tests, plist validation and configuration dry-run pass.
- Added event-driven launchd-supervised page checkpoint watcher and an AeroSpace startup recovery hook. Cold-boot identity checks reject stale window IDs/PIDs; corrupt checkpoint tests pass. Live forced-crash testing remains pending.
- Added RunAtLoad GUI-login initialization. First live startup FAILED with Device Control permission under launchd. Reworked startup to enter through the native app and signed it with the user's existing Apple Development identity; signature validation passes. An existing ad-hoc TCC record remained stale despite toggling. Native re-registration is awaiting the macOS unlock prompt. Latest observed login exit code was 2; login startup is configured but NOT yet proven successful.
- Three current wallpaper choices saved: supplied Green Glass plus generated matching Silver and Amber variants. Settings visibly reported omac-obsidian as the selected desktop image. Earlier design directions retained in branding/wallpapers/archive.
- Native OMAC.saver compiled and its principal class loaded successfully through Bundle.load. Fixed explicit Objective-C principal-class naming. Plugin installed in ~/Library/Screen Savers and appears under Other in macOS Wallpaper > Screen Saver.
- Preview rendered original sage ASCII OMAC animation; preview dismissed. Plugin selection and idle activation are NOT yet confirmed; Settings still showed Start Screen Saver: Never. No password/lock policy was changed.
- macOS 27.0 build 26A428; one physical C27F390 display available. Actual reboot, sleep/wake, and alternate display configurations remain unverified.
- Management paused at the permission checkpoint; terminal sessions preserved. User approved a 45% usage ceiling; latest meter check was 43%.

## Omac branding and recovery — September 21
- Signed Omac.app installed with supplied logo; persistent Dock entry configured, green status title and Engage/Disengage controls added. Internal identity retained.
- Stale Accessibility registration resolved by resetting only this bundle's Accessibility entry and re-adding the signed app in Settings. Actual launchd login job exited 0 and reached Active.
- Live restart tests for menu, watcher, and AeroSpace preserved all 23 window ID/PID pairs and their workspace memberships; focus remained page 1.
- Native screensaver preview rendered; installed saver is listed in System Settings. Idle activation and native selection are not yet confirmed.
- Actual reboot, sleep/wake and alternate physical display configurations remain untested.
- Disengage and re-engage live run preserved all 24 window ID/PID pairs (zero lost) and returned Active. This includes the temporary Settings sheet; no agents were stopped.
- Revised native preview visually checked with multicolor wordmark and cyan lightning scene; key 3 selects lightning successfully. Four eight-second scenes cycle. Installed updated signed saver after committing sources. Preview left open for user review; native idle activation remains unverified.

## Native packaging preview — isolated branch

The daily-use installation has not been replaced. Preview build uses bundled resources and per-user generated configs; native SMAppService login code is compiled but NOT registered/tested on this machine.

- 15 tests passed, including a relocated resource path containing spaces/apostrophes and checks that generated jobs do not point to the original source checkout.
- A signed app was copied to a separate temporary location; `--check` passed, reported its relocated resources, and created no state directory.
- Config generation ran from the relocated app into a separate test state directory. Deep strict signature verification still passed afterward.
- Built Apple Silicon macOS 14+ DMG; disk-image checksum verification passed (about 10 MB). No original developer checkout path found inside the staged app.
- This is Apple Development signed, not Developer ID signed or notarized. It is not public-release ready.
- No native login registration, live upgrade/migration, clean-account boot, or fresh-Mac test has been claimed. No dependency or user permission was installed by packaging.

## Exact native-window targeting checkpoint — September 21

Native `--window-target ID PID` resolves the AX window by WindowServer ID using dynamically resolved `_AXUIElementGetWindow`, rejects missing/ambiguous matches, and selects the display by largest frame intersection. This is a private macOS API and must remain fail-closed when unavailable. Main Mac live probe matched the existing Codex window; an invalid ID was rejected.

A temporary Finder window was floated explicitly and resized through the new `--window-half ID PID` prototype command. A no-margin request was rejected and rolled back when macOS clamped the frame. The eight-pixel-margin target passed exact bounds readback, and the Finder window was visually inspected via CUA, then closed by its specific window ID. No installed Omac binary or bindings were changed. Multi-window/sibling isolation, Mini 2, original tree-slot restoration, and controller integration remain pending.

Fixed actual CLI contract: default AeroSpace JSON omits PID/workspace/layout, so the controller now requests these fields explicitly; real tiled layouts are h_tiles/v_tiles. Included tile_modes.py in the packaging manifest. Unit suite: 35 passed.

### Follow-through: two windows and second Mac

Two temporary Finder windows on Mini 1 began at [8,38,948,1033] and [964,38,948,1033]. The second window was selected by exact ID, moved to half-screen, returned to its recorded frame, and re-tiled. Both windows read back their original bounds afterward; only those temporary windows were closed. A final position application after the size change was necessary for macOS to settle the requested bounds.

The same native target probe ran read-only over SSH on Mini 2 and resolved its live Chrome window to the physical display visible frame [1180,0,1920,1080], rather than assuming the primary virtual display. No Mini 2 window was resized and no installed binary changed. Half currently floats the target and does not yet reserve grid space from neighbors; the daily binding must remain gated until shared-grid behavior is implemented.

### Whole-page grid prototype remains gated

`grid_controller.py` is an experimental whole-page transaction, not packaged or bound. A two-Finder test on an otherwise empty page 5 failed frame verification for quarter-sized tiles; subsequent rollback verification also reported errors. Both disposable Finder windows were closed by their created IDs and page 1 restored. No user windows were part of that transaction. Do not deploy this path until app-size fallback and rollback are proven.

The separate Omac Tile Lab launches and visibly states that capture starts only after choosing a window and pressing Preview. Screen Recording approval is pending; no capture started. Controller native integration now has 38 passing tests; no daily binary/bindings were replaced.


## App shelf development checkpoint (2026-09-21)
- New user direction supersedes native-app miniature previews and forced three-size behavior: one real app icon per app, reuse one existing window, preserve native sizing, tuck on page switch, recall on current page.
- Live disposable Finder test passed enrollment, deduplication, minimization, recall on pages 2 and 3, and restoration. Same window ID throughout.
- Atomic checkpoint reload recovered a minimized Finder window and subsequent cross-page recall passed.
- Isolated icon selector showed real Finder/Chrome icons; Right Arrow changed focused entry and Return selected it.
- Native source typecheck, generated TOML parsing, and 40 existing regression tests passed. Those 40 tests are not shelf UI coverage.
- Full installed-app integration, automatic workspace-change tuck, app-launch enrollment, physical Mini 2 behavior, and left/right terminal placement remain unverified. Terminal UI testing was denied by the computer-use tool; no bypass attempted.
- Existing installed Omac has not been replaced in this checkpoint.

### Mini 1 installed shelf follow-up
The daily launcher was updated in place after committing its changes, with the prior application backed up. AeroSpace accepted the configuration dry-run and reload. The launchd-managed menu helper restarted successfully. Installed Finder enrollment and selector Return-to-recall worked; switching to page 2 automatically minimized the shelf window, and recall returned the same window ID to page 2. Switching to page 3 minimized it again. The dark 85%-opacity selector and shortcut guide were inspected on screen; Escape dismissed the selector. Cross-Mac deployment and physical shortcut testing remain pending. Existing native menus use dark appearance; their translucency is managed by macOS.

### Mini 2 shelf installation — September 21 afternoon
Compiled the committed portable shelf launcher, backed up the remote app and runtime in Documents/Omac-backups, then updated the executable and payload. Ad-hoc signature validation passed; --check reported Accessibility true, no missing dependencies, and login registered. Runtime regeneration and AeroSpace dry-run/reload passed. Restarted only the launchd menu helper; it is running and existing Ghostty processes remain. Screen Sharing explicitly reports Locked, so physical keyboard, selector appearance, and cross-page shelf recall are pending unlock. No lock or iPhone Mirroring setting changed.


### Native-width presets and compact terminal setup
- Added explicit one-third, half, and two-thirds native-app widths beside two or three terminals. Existing half-width shortcuts remain unchanged; choices are in Mixed Layout. Restore the active mixed layout before changing presets.
- Menu captures exact window ID/PID before focus changes. Presets and expand/return revalidate identity; missing target refuses. Keyboard commands use their current focus.
- Mini 1 real ChatGPT plus two Ghostty windows passed one-third and two-thirds application and exact frame restoration. Production checkpoint was unchanged.
- Matching signed helper installed/running on both Macs. Mini 1 menu visibly exposes all six size/count combinations. Mini 2 physical test is deferred at the user's request.
- Ghostty hidden mode configured for new Omac terminals. Existing terminal reload remains pending: CUA access to Ghostty was rejected; do not bypass that boundary or restart user sessions. Automatic macOS keyboard-layout switching is disabled by Ghostty hidden mode.
- Optional additional app windows remain an uninstalled prototype, deferred by the user.

- Follow-up page/shelf correction: restore mixed layout before Omac page switching, moving a member, or manual shelf tuck. Real page 1 → 2 → 1 test passed using an isolated checkpoint; original real-window frames and production checkpoint remained intact. External page changes retain recovery state and allow returning to its recorded page.
- Tighter yellow border compiled and installed on both Macs; visual corner acceptance remains user-visible validation.
