# Omac native packaging preview

This is an engineering preview, not yet a public-ready installer. Mini 2 installation, native login registration, five-page terminal grids, and supervised recovery have been tested. Actual reboot, sleep/wake and public-download installation remain release gates. Keep your existing working installation backed up.

## What is included

Omac.app contains the native launcher, guide, controller, config generator, watcher, six static wallpapers, and icon. It has no reference to the original developer checkout. Runtime configuration is generated per user in Application Support; the signed app bundle stays unchanged. It discovers standard Apple Silicon and Intel Homebrew paths. This particular build supports Apple Silicon and macOS 14 or later; other OS versions still need actual testing.

Prerequisites remain separate: AeroSpace 0.21.3-Beta (app and CLI), Ghostty 1.3.1 and Python 3 from Homebrew or python.org. These versions are the tested development baseline, not a promise that every future release works. Omac diagnoses missing tools; it never installs them silently. Their downloads and licenses remain with their vendors:
- https://github.com/nikitabobko/AeroSpace
- https://ghostty.org/download
- https://www.python.org/downloads/macos/

Each recipient must grant Omac and AeroSpace window-control access on their own Mac. Permission grants and credentials are never packaged. New native login controls use Apple's SMAppService. Startup is opt-in for recipients and requires the app in /Applications/Omac.app. Existing terminal sessions are never included or uploaded.

## Public-release gates

1. Mini 2 installation without a developer checkout passed, as did relocation, pause/exit preservation and induced installer rollback. Still test a clean account, permission revocation, complete uninstall and real quarantined downloads.
2. Finish migration from the existing launchd login job to native login registration; test actual sign-out/sign-in, reboot, sleep/wake and multiple displays.
3. Confirm the six static wallpaper choices on a clean account and across multiple displays. The previous Omac screensaver is retired during upgrade; macOS lock and sleep settings are left alone.
4. Decide whether Python remains an explicit beta prerequisite or whether to port the small controller/watcher to Swift. Swift removes a recipient dependency; it does not eliminate the need for AeroSpace or Accessibility authorization.
5. Review artwork provenance, the final public identity and third-party notices; choose a license before publishing source. This package deliberately does not redistribute AeroSpace, Ghostty or Python.
6. Direct distribution is the selected route: no App Store submission or Apple upload. Ad-hoc signing is local code integrity, not Developer ID trust. Test an actual quarantined downloaded copy and document supported macOS approval steps; never instruct users to disable Gatekeeper or other protections. Developer ID/notarization is optional future work only if explicitly chosen.
7. Publish the signed DMG and checksum with release notes and rollback instructions. Add signed updates only after the installation/upgrade paths are reliable.

## Community distribution

Omac is a free community project distributed directly from its source and release artifacts. It does not require accounts, subscriptions, or a hosted service. Window control, terminal sessions, preferences, and the optional remote Screen Sharing setup all stay on the user's Mac. Nothing has been submitted to Apple.

## Reproducible build

Run `./package.sh`. The script reuses the first available Apple Development identity unless `OMAC_SIGN_IDENTITY` is set explicitly; it falls back to an ad-hoc engineering build only when no development identity is available. This command only creates artifacts; it does not install, register startup, publish or submit to Apple. Keep signing keys and notary credentials outside the repo and never ship them. The generated DMG is NOT notarized by this script.

Read-only dependency diagnosis: run `Omac.app/Contents/MacOS/AgentControlCenter --check`. This does not grant permissions or start tiling. For engineering tests use OMAC_STATE_ROOT to keep generated state separate.

Apple references:
- Native login registration: https://developer.apple.com/documentation/servicemanagement/smappservice
- Distribution signing: https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Build, install, and update

1. On the build Mac, run `./package.sh`. It creates a signed engineering DMG and checksum without installing it or changing host services.
2. On the destination Mac, install the prerequisites above, open the DMG, and run `Install Omac.command`. It verifies the staged app before replacing `/Applications/Omac.app`.
3. For an update, choose Disengage and Quit first, then run the newer packaged installer. It preserves the Application Support state, including pages, wallpaper choice, app favorites, and optional remote-control configuration. It backs up the prior app, state, and saver under `~/Library/Application Support/Omac/InstallerBackups`; a failed install restores them automatically.
4. Open Omac from Applications. macOS requires that Mac's own window-control approvals for Omac and AeroSpace. Start at Login remains opt-in.

## Optional remote Screen Sharing handoff

To enable Control–Option–1 (return local) and Control–Option–2 (enter remote), create `~/Library/Application Support/AgentControlCenter/remote-control.json` and then rerun the installed app with `--prepare-runtime` or install an update:

```json
{
  "version": 1,
  "enabled": true,
  "connectionPath": "/Users/you/path/to/saved-connection.vncloc"
}
```

The only required connection setting is `connectionPath`, an existing local Screen Sharing `.vncloc` file. Omac keeps the viewer on the page you enter from and does not ship a host name. Set `enabled` to `false`, remove the file, or regenerate the runtime to remove these bindings.

If a host needs stable display placement, put this separate file beside the remote configuration and regenerate the runtime:

```json
{
  "version": 1,
  "workspaceToMonitor": { "1": "main", "4": "secondary" }
}
```

Save it as `~/Library/Application Support/AgentControlCenter/preferred-monitor.json`. It generates AeroSpace's `workspace-to-monitor-force-assignment` only for valid page keys `"1"` through `"5"`. It is optional, stays outside the app bundle, and survives upgrades.

The installer does not bypass macOS security checks. This preview is not yet the final download-and-go public product.
