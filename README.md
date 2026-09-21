# Omac — Mac Omac

An on-demand or sign-in-started Mac workspace: five persistent AeroSpace pages, Ghostty terminal grids, desktop apps, a compact native shortcut palette, and Omac appearance choices. No agent commands, paid APIs, or model choices are launched automatically.

## Everyday controls

- Command–1…5: switch pages. Command–Shift–1…5: send the focused window to a page.
- Command–Return: add a terminal to the current page, up to six. Control–Option–4 / 6: arrange that page's terminals in a grid.
- Command–arrows: focus a tile; Shift adds swapping. Command–O: centered floating window / return. Command–F: enlarge / restore. Command–T: float / tile. Command–B: balance sizes.
- Command–K: compact translucent shortcut palette. Escape dismisses it.
- Control–Option–P: pause management. Control–Option–Escape: Exit, restore saved geometry and original wallpaper where possible, and leave terminal sessions running.
- The **▦ Omac** menu contains Apps, Settings, Omac Appearance, and login startup controls.

Command–Option plus G opens Codex; C Claude; H Hermes; R Cursor; V VS Code; T Telegram; I Messages; M Mail; B Chrome; E Finder; S System Settings. Existing app windows retain their page; opening an app may focus its existing window on another page. New windows tile on the current page. Apps retain their own minimum window sizes.

## Startup and recovery

Start at Login installs `~/Library/LaunchAgents/com.richard.acc.login.plist`. It starts Omac after GUI sign-in, not before authentication. It does not launch terminal agents. The signed native app owns login initialization, rather than giving a general Python interpreter device-control access.

launchd supervises the menu, AeroSpace, and event watcher. The watcher listens to AeroSpace events, debounces activity, and atomically saves window/page assignments under the controller lock; it performs no paid calls or idle polling. AeroSpace's startup hook restores assignments for matching live window IDs/PIDs from the same boot. Terminal-only grids are rebuilt; arbitrary custom split trees and fullscreen state are not serialized.

Fresh reboot begins with five available pages. Shell processes cannot survive a reboot. macOS may reopen app windows, but Omac does not guess which project/page they belong to. Page restoration across a manager crash or orderly Exit uses still-running windows only. Invalid checkpoints or a different boot are ignored.

## Appearance

Omac Appearance offers Green Glass, Silver Glass and Amber Glass wallpaper. Green is the supplied reference; matching variants were made with the built-in image-generation tool. Original desktop image URLs are saved before applying a theme; Exit attempts restoration. Dynamic wallpaper playback/scaling are not fully represented by that URL backup. See `branding/README.md`.

`branding/screensaver/build/OMAC.saver` is a native ScreenSaverView plugin. `OMAC-Preview.app` previews its renderer without locking the Mac. The system screensaver must be selected in macOS Settings. It animates a sage OMAC glyph through assembly and dissolution, at 12 frames/second; Reduce Motion uses a still image. Existing lock/password requirements are not modified.

## Build and rollback

Run `./build.sh`. For durable Accessibility trust, use the same installed Apple Development identity when signing the installed app; rebuilding with ad-hoc signing changes its trust identity. `OMAC_SIGN_IDENTITY` controls screensaver/preview signing in the build script. Main app installation/signing must use the same identity too. Keep this repository at its current path: installed launch jobs and app point here.

To stop automatic startup, select **Disable Login Startup**. To disable the full setup without stopping terminal sessions:

```sh
/opt/homebrew/bin/python3 control.py rollback
```

This removes the login job, stops management/checkpointing/menu helpers, restores saved windows/wallpaper where possible, and preserves files. It does not uninstall the screensaver; choose another saver in Settings, then move `~/Library/Screen Savers/OMAC.saver` to Trash if desired.

See `VERIFICATION.md` for actual evidence and remaining hardware tests. Compilation alone is not a claim of sleep/wake, reboot, or multi-display reliability.

## Omac Dock launcher
Open `/Applications/Omac.app` to engage Omac. Clicking its running Dock icon engages/resumes it; right-click the icon for the same controls as the green Omac menu-bar item. **Disengage Omac** (Control–Option–Escape) releases tiling and shortcuts and restores saved windows/wallpaper where possible, leaving terminal sessions running. The app stays available for re-entry. Quit Omac also stops its supervised launcher.

User-visible branding is Omac. Existing bundle identifiers and storage paths remain stable to preserve permissions and saved sessions. Existing terminals retain their old titles until closed; newly created terminals are titled Omac.

Build with `./build.sh`. Commit changes before installation, then run `OMAC_SIGN_IDENTITY=<existing Apple Development identity> ./install.sh`. Never replace the installed signing identity with an ad-hoc signature.
