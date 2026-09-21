# Omac native packaging preview

This is an engineering preview, not yet a public-ready installer. Do not replace an existing working Omac installation with this build yet: migration and native login registration have not been live-tested.

## What is included

Omac.app contains the native launcher, guide, controller, config generator, watcher, three wallpapers, icon, screensaver and visual preview. It has no reference to the original developer checkout. Runtime configuration is generated per user in Application Support; the signed app bundle stays unchanged. It discovers standard Apple Silicon and Intel Homebrew paths. This particular build supports Apple Silicon and macOS 14 or later; other OS versions still need actual testing.

Prerequisites remain separate: AeroSpace 0.21.3-Beta (app and CLI), Ghostty 1.3.1 and Python 3 from Homebrew or python.org. These versions are the tested development baseline, not a promise that every future release works. Omac diagnoses missing tools; it never installs them silently. Their downloads and licenses remain with their vendors:
- https://github.com/nikitabobko/AeroSpace
- https://ghostty.org/download
- https://www.python.org/downloads/macos/

Each recipient must grant Omac and AeroSpace window-control access on their own Mac. Permission grants and credentials are never packaged. New native login controls use Apple's SMAppService. Startup is opt-in for recipients and requires the app in /Applications/Omac.app. Existing terminal sessions are never included or uploaded.

## Public-release gates

1. Test a clean user account and a second Mac with no developer checkout; verify first-run setup, relocation, safe upgrades, uninstall, pause, exit and permission denial/revocation.
2. Finish migration from the existing launchd login job to native login registration; test actual sign-out/sign-in, reboot, sleep/wake and multiple displays.
3. Confirm native screensaver selection and idle activation on supported macOS versions. The preview renderer is verified; idle activation is not.
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
