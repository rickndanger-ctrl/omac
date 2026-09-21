# Verification

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
