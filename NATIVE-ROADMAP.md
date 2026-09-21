# From personal Omac setup to a shareable Mac app

## Direction

Omac should be a normal, self-contained macOS application that starts after sign-in, has a Dock icon and menu-bar controls, owns a clear Preferences window, and can be disengaged without closing work. Its five pages remain AeroSpace workspaces; they are not native Mission Control Spaces. Apps retain their own minimum sizes.

## Foundation completed in this preview

- Bundle code, guide, artwork and saver inside Omac.app.
- Discover standard dependency paths instead of assuming the developer's checkout.
- Generate configuration and launchd jobs in each user's Application Support folder, outside signed resources.
- Compile native login registration and expose setup status.
- Build a signed development DMG reproducibly; verify resources after relocation.

## Next implementation order

1. **Finish recipient setup and safe migration.** A native first-run screen should detect dependencies/versions, link to official installs, explain each permission, and verify actual independent window-control access. Detect the currently installed Omac and migrate only after saving its configuration; preserve all open terminals. Native startup needs real login/logout testing.
2. **Remove Python.** Port the controller and event watcher to Swift, keeping the existing behavioral tests. Continue using launchd supervision, file locks/atomic checkpoints and AeroSpace's event stream. Keep AeroSpace/Ghostty separate for the first beta. A signed supported runtime is an alternative, but adds download size and a maintenance/security burden.
3. **Add native Preferences.** Start-at-login toggle with actual macOS status, editable shortcuts/conflict checks, page/project names, theme/opacity/effects intensity, restore defaults, diagnostics and a complete uninstall action. Keep API/model configuration out of this app.
4. **Prove everyday behavior.** Clean user, second Mac, permission revocation, helper crash, app upgrades, screen lock, sleep/wake, reboot, display removal/reconnection, dialogs/fullscreen and return to ordinary Mac controls. Validate native screensaver selection/idle activation on each supported macOS release.
5. **Ship a small beta.** Choose supported OS/architecture, review public artwork identity and notices, use the selected direct-download route, verify a quarantined download on a clean Mac, then give a few testers the DMG/checksum and a feedback/rollback guide.
6. **Public release.** Publish a versioned download and release notes. Add a signed updater only after migrations and uninstall are reliable. Pick source/license terms before publishing the repository; do not share signing keys, credentials or personal configuration.

## What recipients would do

Download the DMG → drag Omac to Applications → open setup → install missing prerequisites from official sources → grant window-control access → choose whether to start at login → Engage Omac. They do not need Codex, this conversation, the development repo, or the creator's accounts.

## Remaining external checkpoint

The user selected independent SaaS/direct distribution, with no App Store or Apple upload. Ad-hoc signing supplies local integrity, not Developer ID trust. First-launch approval friction must be tested and explained; do not disable security protections. No public upload has occurred.

Sources:
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
