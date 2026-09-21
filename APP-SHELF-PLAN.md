# Omac app shelf

Approved replacement for tiny native-app previews. Existing tile-compatible windows remain tiled. One actual app icon per app appears beside Omac; the keyboard selector uses arrows and Return to recall the same remembered window on the current page. Recall never creates another window. Existing additional windows remain untouched.

Shelf windows keep their native size and controls, and tuck away without quitting or closing documents. Forced center/full sizing was explicitly removed by the user. Page switching automatically tucks summoned shelf windows. Normal close controls retain document-close semantics; Omac tuck is a separate action.

Implementation gates: exact ID/PID targeting; standard-window filtering; current monitor placement; hide/recall and page change; stale-window pruning; restore on exit; explicit no-duplicate behavior. App minimum sizes are respected. No screen capture required. Screensaver work remains deferred.

Proposed bindings, pending conflict/live tests: Command-Option-Space selector, Command-Option-Down tuck, Command-Option-Shift-Space add current app to shelf. Control-Option-Left/Right request optional half-screen placement. Existing app launcher shortcuts recall already enrolled apps. Automatic enrollment must not capture terminals or unrelated apps accidentally.

Follow-up: app attention badges. Render a small dot/count beside the actual icon when a supported app integration reports unread/completion state. Do not equate a running/hidden app with completed work. Apple's public UNUserNotificationCenter exposes the calling app's notifications, not a universal cross-app notification feed; app-specific signal validation is required before promising support.
