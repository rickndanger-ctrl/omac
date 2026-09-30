<p align="center">
  <img src="branding/omac-logo.svg" alt="Omac" width="320">
</p>

<p align="center"><b>Own your Mac.</b><br>
A tiling window manager built for AI agents, with its own terminal and a voice partner, Jev.</p>

<p align="center">
  <a href="https://github.com/rickndanger-ctrl/omac/releases/latest"><b>Download for Apple Silicon</b></a> ·
  <a href="https://rickndanger-ctrl.github.io/omac/">Website</a> ·
  <a href="https://rickndanger-ctrl.github.io/omac/guide.html">Guide</a>
</p>

<p align="center">
  <a href="https://youtu.be/fCC9YHR6KLg"><img src="https://i.ytimg.com/vi/fCC9YHR6KLg/hqdefault.jpg" alt="Watch Own Your Mac. Meet Omac." width="480"></a><br>
  <a href="https://youtu.be/fCC9YHR6KLg"><b>Watch the 33-second Omac demo</b></a>
</p>

---

## What it does

- **Every window in its place.** Apps and terminals tile themselves into clean layouts across five pages. <kbd>⌘</kbd> <kbd>1–5</kbd> switches instantly.
- **Omac Terminal, built in.** A fast glass terminal that opens tiled, takes your typing immediately, and keeps jobs running through a restart. No extra terminal app needed.
- **Jev, your partner.** Say it or type it: `jev "bring chrome next to me"`, `jev "open notes on page 2"`. Jev asks once, then does it.
- **Your terminal is your assistant.** `omac open chrome page 2`, `omac text wife "on my way"`, `omac remind "call the plumber" tomorrow 9am`. It always confirms before sending anything.
- **Know what your agents are doing.** Claude, Codex and Hermes report to the Omac bar: working, needs you, done.
- **Two Macs, one keyboard.** Hop between Macs with <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>1</kbd> / <kbd>2</kbd>.
- **Make it yours.** Themes like Oak and Pirate Waters, or have your own AI agent design one.

## Install

1. Download the latest **OMAC-….dmg** from [Releases](https://github.com/rickndanger-ctrl/omac/releases/latest). It is signed and notarized by Apple.
2. Drag **OMAC** to Applications and open it.
3. Follow Setup, and turn on **Accessibility** when macOS asks. That's how Omac moves windows.
4. Press <kbd>⌘</kbd> <kbd>↩</kbd> for a terminal, and <kbd>⌘</kbd> <kbd>K</kbd> for every shortcut.

With [Homebrew](https://brew.sh):

```sh
brew install --cask rickndanger-ctrl/omac/omac
```

Or straight from a terminal:

```sh
curl -sL $(curl -s https://api.github.com/repos/rickndanger-ctrl/omac/releases/latest | grep -o 'https://[^"]*\.dmg' | head -1) -o ~/Downloads/Omac.dmg && open ~/Downloads/Omac.dmg
```

Requires an Apple Silicon Mac running macOS 14 or later.

## The keys worth knowing

| Keys | Does |
|---|---|
| <kbd>⌘</kbd> <kbd>1–5</kbd> | Switch page |
| <kbd>⌘</kbd> <kbd>↩</kbd> | New terminal |
| <kbd>⌘</kbd> <kbd>←↑↓→</kbd> | Move between tiles |
| <kbd>⌘</kbd> <kbd>W</kbd> | Close; focus lands on the tile beside it |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>↩</kbd> | Quick open any app, already tiled |
| <kbd>⌘</kbd> <kbd>K</kbd> | Shortcut guide |

## Feedback

Found a bug or want a feature? [Open an issue](https://github.com/rickndanger-ctrl/omac/issues). If Omac saves you time, **a ⭐ helps a lot.**

---

<sub>Omac is built by one person with a team of AI agents. The app is free to download; supporter and creator versions are coming soon.</sub>
