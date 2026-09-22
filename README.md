# Omac

Omac is a free, community-built keyboard-first macOS workspace built around AeroSpace, Ghostty, native apps, persistent pages, an app shelf, focus highlighting, and optional animated wallpaper. This repository currently builds a portable engineering preview. The signed bundle has been installed and exercised on two development Macs; it is not notarized or production-certified. **Read [DISTRIBUTION.md](DISTRIBUTION.md) before sharing or installing a build.**

## Build

Run `./package.sh`. It compiles an app, includes its resources and optional saver, runs tests, signs the bundles and creates a checksummed DMG. It neither installs nor notarizes. Move an existing `dist` aside before rebuilding. The script reuses the first available Apple Development identity unless `OMAC_SIGN_IDENTITY` is set explicitly; it falls back to an ad-hoc engineering build only when no development identity is available.

The app uses its own bundled resources, generates configs in each user's Application Support folder, discovers standard Homebrew/Python installations and diagnoses missing dependencies. It does not run from the development checkout after installation. The menu's Start at Login controls use native SMAppService registration; installed-app login registration has passed on the second development Mac, while reboot and sign-out/sign-in acceptance remain open. launchd continues supervising the window manager and watcher.

Dependencies remain external: AeroSpace app/CLI, Ghostty and Python. The public-release path is documented with exact blockers in DISTRIBUTION.md. The legacy source-checkout installer is disabled here; use the packaged `Install Omac.command` workflow.

## Controls

- Command–1…5 switches pages; Command–Shift–1…5 moves the focused window.
- Command–arrows focuses a tile; Shift swaps tiles.
- Command–O centers/returns a tile; Command–F enlarges/restores; Command–T floats/tiles.
- Command–Return adds a terminal; Control–Option–4 / 6 arranges four/six terminals.
- Option–Tab / Option–Shift–Tab cycles eligible windows on the current page.
- Control–Option–Shift–2 / 3 applies an explicit app-plus-terminals mixed layout; Control–Option–M expands or returns its focused member, and Control–Option–Shift–R restores the original layout.
- Command–K opens the guide. Control–Option–P pauses. Control–Option–Escape disengages and leaves agents running.
- Optional Screen Sharing handoff: Control–Option–1 returns to the remembered local window and Control–Option–2 enters the configured remote Mac. These shortcuts are absent unless remote control is configured.
- Screensaver preview: 1 assembly, 2 red laser, 3 lightning, 4 logo; Escape closes.

Existing apps retain their minimum sizes. The five pages are AeroSpace workspaces, not additional native Mission Control Spaces. A reboot cannot preserve running shell processes. Renderer previews are verified; native idle saver activation remains unverified.

Mixed layout is never applied during app launch. Restore it before swap, resize, balance, float/tile, or fullscreen commands; those shape-changing commands refuse while the protected mixed layout is active. Restore validates the boot, process, exact window ID, and page before mutation.

## Validation

Run `python3 -m unittest discover -p 'test_*.py'`. Tests cover session preservation, page isolation, recovery failures and generated configuration under relocated paths containing spaces/apostrophes. `Omac.app/Contents/MacOS/AgentControlCenter --check` reports prerequisites without starting tiling. It is not proof of independent app permission trust, login registration, fresh-Mac behavior or notarization.

## Optional remote Screen Sharing handoff

Create `~/Library/Application Support/AgentControlCenter/remote-control.json`, then prepare the runtime again from the installed app (or reinstall/upgrade). Omac does not create this file, save credentials, or assume a particular remote Mac or monitor.

```json
{
  "version": 1,
  "enabled": true,
  "connectionPath": "/Users/you/Library/Containers/com.apple.ScreenSharing/Data/Library/Application Support/Screen Sharing/My Mac.vncloc"
}
```

`connectionPath` must name an existing Screen Sharing `.vncloc` file. Omac keeps the viewer on the page you enter from. Set `enabled` to `false`, remove the file, or regenerate the runtime to remove the shortcuts. The state file survives application upgrades.

For a Mac with stable named monitors, an optional `~/Library/Application Support/AgentControlCenter/preferred-monitor.json` can assign pages to AeroSpace monitor names:

```json
{
  "version": 1,
  "workspaceToMonitor": { "1": "main", "4": "secondary" }
}
```

Only page keys `"1"` through `"5"` with non-empty monitor names are generated. This host-local file is preserved by upgrades and is ignored when absent or malformed; it never makes a default install target a particular display.
