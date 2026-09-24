# Lessons — read this before touching Omac

Problem → root cause → rule. Append; never delete. Every session starts by reading this file.

## 1. Focus highlight vanished under rapid Command-W (2026-09-24)

**Problem.** Holding Command-W to close several windows fast left the yellow focus border
hidden even though a live window was focused. Reported on the installed preview.

**Root cause.** `FocusBorderController` acted on every Accessibility callback without
checking who sent it. Closing window A fires two events in no fixed order: "focused window
changed" (to B) and "A destroyed". When the focus change arrived first, the border was
already outlining B, then A's late "destroyed" hid it. Callbacks are also delivered
asynchronously, so a torn-down observer could still land a message. Separately, if the
app briefly reported no focused window mid-close, the controller hid the border and never
retried until the next focus event.

**Fix.** `FocusBorderEventPolicy` (pure rules, no AppKit): drop any callback whose observer
is no longer current; only honor destroy/minimize for the exact outlined element; after a
hide, or a failed focused-window read, re-read on a bounded schedule (50/150/400/900 ms)
rather than waiting for an event that may not come. Also observe main-window-changed and
window-created on the app, and observe the window through its own process id.

**Rules that keep this from recurring.**
- An AX or workspace callback is not evidence about the *current* target until you have
  checked it came from the current observer and names the current element. Treat every
  callback as possibly stale.
- Window close is a transition, not an instant. Any "read the focused window" that can
  fail during a burst needs a short bounded retry, never a single try and give up.
- Keep decision rules in a pure struct next to the AppKit glue so the ordering cases can be
  enumerated and reviewed without a live Mac. Add cases to the policy, not to the callback.
- The same class of bug (focus reconciled before the destruction callback) already cost
  days in `omac-native`; see its `CLOSURE-FOCUS-CHECKPOINT.md`. Check both repos when one
  hits an ordering race.

**Verification gap.** This session ran on Linux with no Swift toolchain, so the change is
compile-unverified until `./package.sh` runs on a Mac. Acceptance: with the border on,
open 6+ windows in one app, hold Command-W until one remains; the border must stay on the
surviving focused window the whole time, and must clear when the last window closes.

## Working agreements

- Cheaper subagents for search and bulk reads; the lead reviews and edits.
- Say plainly what was verified and what was not.
