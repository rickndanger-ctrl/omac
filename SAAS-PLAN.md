# Omac SaaS: a Mac workspace product with an online account

## Product shape

Omac is a native Mac companion plus a subscription service. The desktop app controls windows, shortcuts, pages and appearance. The website handles registration, plans, device management, downloads, release notes and optional settings sync. A browser cannot supply system-wide window management by itself.

Distribution is directly from the Omac website (or a versioned release host), with no App Store submission or Apple upload planned. Ad-hoc signing is not Developer ID trust, so an actual downloaded installer must be tested for macOS first-launch approval behavior before onboarding customers.

## First paid product

Keep the working single-Mac tiling experience available offline. Sell convenience around it: named project/page presets, advanced shortcut/theme profiles, multiple-device settings sync and later team defaults. Pricing and free/paid boundaries need a product decision; no price or checkout has been created.

A workspace preset means app names, intended pages and layout preferences—not a saved live shell process. Launching saved terminal commands must be opt-in and reviewed; merely opening a preset must not execute imported commands silently.

## Four components

1. **Omac for Mac:** native controls, local tiling, Preferences, permission onboarding, diagnostics, safe pause/exit and local project profiles. No inference API is needed for normal operation.
2. **Account website:** sign in, subscription status, manage devices, download a release, view setup steps and cancel a plan.
3. **Entitlement service:** verify the signed-in account and active plan server-side, issue short-lived signed entitlements with a documented offline grace period, and enforce sensible device limits. Never put billing/provider secrets in the desktop app.
4. **Billing and optional sync:** hosted checkout/customer portal with verified idempotent billing webhooks. Sync only explicitly selected configuration; do not collect terminal output, prompts, agent credentials, window titles or project files by default.

## Reliability rules

- License/network failures never close terminals, move windows unexpectedly, block Disengage, or prevent access to existing local settings.
- Cache entitlements for offline use; avoid a network call on every shortcut or workspace switch.
- Maintain clear local/exported backups before updates and schema migrations.
- Keep app updates signed and versioned, with integrity verification and rollback. No unsigned remote command execution or automatic execution of synced scripts.
- Confirm cancellation and device removal in the web UI; keep account deletion and local app uninstall separate.

## Implementation sequence

**Now:** validate the isolated portable app and migration; finish native Preferences/onboarding and independent startup tests. The current preview DMG proves build/relocation, not recipient readiness.

**Private beta:** add web account/login and device linking, then test with a small group using manually assigned entitlements. Keep billing in test mode. Use feedback to settle project presets and pricing.

**Paid launch:** connect live checkout/webhooks only after authentication, authorization, cancellation, refunds/support process, offline behavior, upgrade/rollback and clean-Mac install have been tested. Pick the hosting/domain and payment account at that stage; none were created or connected in this task.

## Concrete next milestone

One fresh Mac can download Omac from a staging website, sign in to a test account, complete local permissions, engage five pages, load a reviewed workspace preset, go offline, disengage safely, and uninstall without damaging existing agent sessions or configurations. Passing that end-to-end test comes before taking payments.
