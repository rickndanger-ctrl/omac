# OMAC idle overlay prototype

`build-idle-overlay.sh` builds a manually launched AppKit application using the
existing `OmacRendererView`. It creates one borderless, ordinary-level window
per display. Every window has a visible **Return to desktop** button; Escape,
the button, or clicking the overlay dismisses all windows and terminates the
app. The previously frontmost application is activated on termination.

This prototype does not install or activate a system screensaver, change idle
timers, lock state, sleep state, authentication, iPhone Mirroring, or any
other system setting. It does not capture the screen. Build-only validation
confirms SDK compilation; actual multi-display focus restoration and pointer
dismissal still require a supervised UI run.
