# Omac — native packaging preview

This branch (`omac/native-packaging`) builds a portable engineering preview. The working daily-use installation remains on the original branch; no live migration has been performed. **Read [DISTRIBUTION.md](DISTRIBUTION.md) before sharing or installing this build.**

## Build

Run `./package.sh`. It compiles an app, includes its resources and optional saver, runs tests, signs the bundles and creates a checksummed DMG. It neither installs nor notarizes. Move an existing `dist` aside before rebuilding. The script reuses the first available Apple Development identity unless `OMAC_SIGN_IDENTITY` is set explicitly; it falls back to an ad-hoc engineering build only when no development identity is available.

The app uses its own bundled resources, generates configs in each user's Application Support folder, discovers standard Homebrew/Python installations and diagnoses missing dependencies. The menu's Start at Login controls use native SMAppService registration; this new registration path still needs an actual installed-app login test. launchd continues supervising the window manager and watcher.

Dependencies remain external: AeroSpace app/CLI, Ghostty and Python. The public-release path is documented with exact blockers in DISTRIBUTION.md. The legacy direct installer is disabled on this branch to protect the current installation.

## Controls

- Command–1…5 switches pages; Command–Shift–1…5 moves the focused window.
- Command–arrows focuses a tile; Shift swaps tiles.
- Command–O centers/returns a tile; Command–F enlarges/restores; Command–T floats/tiles.
- Command–Return adds a terminal; Control–Option–4 / 6 arranges four/six terminals.
- Option–Tab / Option–Shift–Tab cycles eligible windows on the current page.
- Control–Option–Shift–2 / 3 applies an explicit app-plus-terminals mixed layout; Control–Option–M expands or returns its focused member, and Control–Option–Shift–R restores the original layout.
- Command–K opens the guide. Control–Option–P pauses. Control–Option–Escape disengages and leaves agents running.
- Screensaver preview: 1 assembly, 2 red laser, 3 lightning, 4 logo; Escape closes.

Existing apps retain their minimum sizes. The five pages are AeroSpace workspaces, not additional native Mission Control Spaces. A reboot cannot preserve running shell processes. Renderer previews are verified; native idle saver activation remains unverified.

Mixed layout is never applied during app launch. Restore it before swap, resize, balance, float/tile, or fullscreen commands; those shape-changing commands refuse while the protected mixed layout is active. Restore validates the boot, process, exact window ID, and page before mutation.

## Validation

Run `python3 -m unittest discover -p 'test_*.py'`. Tests cover session preservation, page isolation, recovery failures and generated configuration under relocated paths containing spaces/apostrophes. `Omac.app/Contents/MacOS/AgentControlCenter --check` reports prerequisites without starting tiling. It is not proof of independent app permission trust, login registration, fresh-Mac behavior or notarization.
