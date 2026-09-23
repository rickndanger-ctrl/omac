# Omac stability review — 2026-09-22

This is a local review build. It has not replaced either installed app and is not a public release.

| Area | Result | Evidence and limit |
| --- | --- | --- |
| Five-page navigation | Passed in earlier controlled live cycles on both Minis | Mini 1 cycled 1→2→3→4→5→1; Mini 2 cycled 3→4→5→1→2→3. Original windows were preserved. This verifies page selection, not physical-key latency or every transient frame. |
| Empty page and remote viewer | Passed on Mini 1 after source fix | A hidden Screen Sharing viewer on page 1 previously became `h_tiles` after evacuation. The updated controller moved it to `Omac-Remote` and restored `floating` before the page change. In a controlled page 1→2 run, page 2 had no focused window; the starting page and viewer state were restored. A physical visual check for any brief pickup remains open. |
| Non-Codex window actions | Passed in earlier controlled live checks | Disposable windows were opened, moved, focused and closed by exact ID on both Macs; pre-existing windows were retained. Ghostty UI could not be operated by the computer-use tool, so direct typing in those terminals remains a user check. |
| Installer preservation and recovery | Passed locally, not deployed | 96 Python unit tests, seven lifecycle fixture tests within that suite, success and failure/rollback installer integration, shell syntax, combined Swift typecheck, signing verification, DMG verification and SHA-256 check passed. A registered but stopped manager or missing saved window ID now counts as degraded. Mini 2 has not received this build. |
| Yellow focus border | Source fix compiled; live visual result untested | Refreshes use the tracked app PID rather than macOS's briefly frontmost app; stale observations clear and desktop windows are excluded. The installed helper has not been replaced. |
| Menu-bar wordmark | Source and package updated; live visual result untested | The bar now draws smooth bold system-font `OMAC` lettering with the wallpaper-derived active accent and retains page buttons 1–5. The installed helper is unchanged. |
| Page indicator responsiveness | Source and package updated; rendered latency unmeasured | AeroSpace's confirmed workspace-change event now triggers a refresh; a 10-second fallback retains shelf, status and AX-focus recovery, and overlapping events are coalesced. The old badge depended on a 1.5-second polling interval. No new helper was launched to measure painted-frame latency. |

Review artifact: `dist/review-d6751a6/Omac-1.2.4-preview-arm64.dmg` and its adjacent `.sha256` file. The app is a signed development preview, not notarized. Do not install it over Mini 2 until the user renews authorization for that transition; preserve the current windows and sessions.
