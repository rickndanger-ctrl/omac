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
