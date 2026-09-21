# Verification

- macOS: 27.0 (26A428).
- Claude Code 2.1.274 and Codex CLI 0.149.0 version commands passed; Hermes help passed.
- Local Qwen launcher found and inspected; existing Full Local mode prerequisite preserved. No generation sent.
- Native menu application compiled and signed.
- Ghostty configuration validation passed.
- No existing AeroSpace, skhd, or Hammerspoon configuration found at their usual paths; no running conflicting tiling manager found.
- No enabled macOS symbolic shortcut using precisely Control–Option found. Third-party and per-app shortcuts require interactive checking.
- Lifecycle unit tests cover repeated entry, preserving sessions on pause/exit, permission failure, and refusing a foreign AeroSpace configuration.

Pending live acceptance: Accessibility grants, four visible terminal launches, 2x2 geometry, Research tiling, real keyboard shortcuts, trackpad use, native dialogs/fullscreen, sleep/wake, monitor changes, crash recovery, and best-effort geometry restoration. Do not treat this first build as production-certified until those pass.
