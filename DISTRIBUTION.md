# Omac native packaging preview

This is an engineering preview, not yet a public-ready installer. Mini 2 installation, native login registration, five-page terminal grids, native screensaver selection and supervised recovery have been tested. Actual reboot, sleep/wake and public-download installation remain release gates. Keep your existing working installation backed up.

## What is included

Omac.app contains the native launcher, guide, controller, config generator, watcher, six wallpapers, icon, screensaver and visual preview. It has no reference to the original developer checkout. Runtime configuration is generated per user in Application Support; the signed app bundle stays unchanged. It discovers standard Apple Silicon and Intel Homebrew paths. This particular build supports Apple Silicon and macOS 14 or later; other OS versions still need actual testing.

Prerequisites remain separate: AeroSpace 0.21.3-Beta (app and CLI), Ghostty 1.3.1 and Python 3 from Homebrew or python.org. These versions are the tested development baseline, not a promise that every future release works. Omac diagnoses missing tools; it never installs them silently. Their downloads and licenses remain with their vendors:
- https://github.com/nikitabobko/AeroSpace
- https://ghostty.org/download
- https://www.python.org/downloads/macos/

Each recipient must grant Omac and AeroSpace window-control access on their own Mac. Permission grants and credentials are never packaged. New native login controls use Apple's SMAppService. Startup is opt-in for recipients and requires the app in /Applications/Omac.app. Existing terminal sessions are never included or uploaded.

## Public-release gates

1. Mini 2 installation without a developer checkout passed, as did relocation, pause/exit preservation and induced installer rollback. Still test a clean account, permission revocation, complete uninstall and real quarantined downloads.
2. Finish migration from the existing launchd login job to native login registration; test actual sign-out/sign-in, reboot, sleep/wake and multiple displays.
3. Confirm native screensaver selection and idle activation on supported macOS versions. Native selection and all three preview scenes passed on Mini 2; automatic idle activation is not yet observed.
4. Decide whether Python remains an explicit beta prerequisite or whether to port the small controller/watcher to Swift. Swift removes a recipient dependency; it does not eliminate the need for AeroSpace or Accessibility authorization.
5. Review artwork provenance, the final public identity and third-party notices; choose a license before publishing source. This package deliberately does not redistribute AeroSpace, Ghostty or Python.
6. Direct distribution is the selected route: no App Store submission or Apple upload. Ad-hoc signing is local code integrity, not Developer ID trust. Test an actual quarantined downloaded copy and document supported macOS approval steps; never instruct users to disable Gatekeeper or other protections. Developer ID/notarization is optional future work only if explicitly chosen.
7. Publish the signed DMG and checksum with release notes and rollback instructions. Add signed updates only after the installation/upgrade paths are reliable.

## Independent distribution decision

Omac is intended as a SaaS product with a direct-download Mac companion. Accounts, subscriptions and optional sync belong to the website; window control remains local. Nothing has been submitted to Apple. See SAAS-PLAN.md.

## Reproducible build

Run `OMAC_SIGN_IDENTITY='<signing identity>' ./package.sh`. Omitting the identity creates an ad-hoc development build. This command only creates artifacts; it does not install, register startup, publish or submit to Apple. Keep signing keys and notary credentials outside the repo and never ship them. The generated DMG is NOT notarized by this script.

Read-only dependency diagnosis: run `Omac.app/Contents/MacOS/AgentControlCenter --check`. This does not grant permissions or start tiling. For engineering tests use OMAC_STATE_ROOT to keep generated state separate.

Apple references:
- Native login registration: https://developer.apple.com/documentation/servicemanagement/smappservice
- Distribution signing: https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Install on a tester Mac

1. Install the prerequisites above. Open the DMG and run Install Omac.command. The installer checks prerequisites and preserves a backup before replacing files.
2. Open Omac from Applications. macOS will require that Mac's own window-control approvals for Omac and AeroSpace.
3. Use Open / Arrange 4 Terminals or 6 Terminals. Command–1 through 5 selects pages; Command–K opens help; Command–Option–Return opens the command menu.
4. Start at Login is optional in the menu. Disengage restores ordinary window control while leaving terminal sessions running; Quit closes the menu helper.
5. For an upgrade, choose Disengage and Quit first. Failed installation restores the previous app, Omac state and screensaver automatically. Backups remain under ~/Library/Application Support/Omac/InstallerBackups. Do not restore an old backup over an active session.

The installer does not bypass macOS security checks. This preview is not yet the final download-and-go public product.
