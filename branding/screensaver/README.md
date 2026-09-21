# OMAC screensaver

This directory contains an original, native macOS screensaver inspired by the
quiet terminal idle state in Omarchy. The mark is a chunky, stepped OMAC glyph
rendered in muted sage over graphite, with faint randomized terminal glyphs
behind it. It does not copy the Omarchy wordmark or artwork.

Build on the target Mac with:

```sh
./branding/screensaver/build.sh
```

Outputs are deliberately kept under the ignored `branding/screensaver/build/`:

- `OMAC.saver` is a native `ScreenSaverView` bundle.
- `OMAC-Preview.app` is a standalone AppKit preview using the same renderer.

The renderer runs at 12 fps, bounds timer deltas, and switches to a still mode
when macOS reports Reduce Motion. The build script does not install or activate
the saver.
