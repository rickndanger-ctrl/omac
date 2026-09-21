# Agent Control Center

Installed app: /Applications/Agent Control Center.app

Open it from Applications and use the ▦ menu-bar item. Choose Accessibility Settings first to grant Agent Control Center access, then Enter. AeroSpace separately requires Accessibility permission. These macOS grants must be made by the user.

See Guide.html for shortcuts. No model prompts are submitted automatically. Claude, Codex, and Hermes use existing CLI defaults. Local uses the existing Local Qwen launcher, including its Full Local mode requirement.

## Architecture and recovery

AeroSpace 0.21.3-Beta and Ghostty 1.3.1 were installed through Homebrew. Custom configuration is isolated in this repository; ~/.aerospace.toml and Ghostty defaults are not modified. Unselected windows default to floating. Research manages open ChatGPT, Claude, and Chrome windows; closing a terminal ends that terminal's foreground session.

launchd supervises the menu app and AeroSpace while explicitly enabled. Each terminal launch is tracked through a launchd job running `open -W -n`, with Ghostty owning its foreground agent process. No automatic agent restarts or prompt replay. Jobs live here rather than Library/LaunchAgents, so they do not load at login. On a launcher crash, recovery pauses tiling. On an AeroSpace crash its config starts disabled; Enter resumes it.

Exit disables shortcuts and stops only the owned window manager. Geometry restoration matches PID, window index, and title; changed titles or closed windows are skipped. Original snapshot is retained through pause/resume. Session persistence across closing terminals or reboot is not included.

## Rollback

Choose Exit and Restore Windows, then Quit Launcher. Or run:

```sh
/opt/homebrew/bin/python3 '/Users/richardholguin/Documents/Codex/2026-09-20/is-x20/outputs/agent-control-center/control.py' rollback
```

This leaves agent terminals and existing apps running. Installed dependency applications and this repository remain available. To remove the app later, quit it before moving it to Trash. Do not uninstall Ghostty while it hosts active sessions.

## Build and verification

Compile Launcher.swift with swiftc, Cocoa, and ApplicationServices into the installed app executable, then ad-hoc sign its bundle. Paths are deliberately fixed to this Mac. Config/source changes must be committed before restarting helpers.

Run `python3 test_controller.py` for lifecycle safeguards. See VERIFICATION.md for live acceptance status. A successful build is not proof of production readiness.
