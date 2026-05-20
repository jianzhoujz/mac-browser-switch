# BrowserSwitch

![macOS](https://img.shields.io/badge/macOS-12.0%2B-black)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-supported-brightgreen)
![Intel](https://img.shields.io/badge/Intel-supported-brightgreen)
![Release](https://img.shields.io/github/v/release/jianzhoujz/mac-browser-switch)

A tiny macOS menu bar utility for switching the system default browser without
opening System Settings.

[中文 README](README.zh-CN.md)

> 🤖 **AI collaborators / contributors please read [AGENTS.md](AGENTS.md) first.**
> It is the canonical entry doc for this project (code map, design principles,
> build & release workflow).

---

## Why

On macOS, changing the default browser takes four clicks (System Settings →
Apps → Default web browser → pick → confirm). If you switch a few times a day
this is annoying. BrowserSwitch puts the same dropdown directly in the menu
bar:

![Menu screenshot](docs/images/menu.png)

Click a browser → done.

## Install

### Homebrew (recommended)

```bash
brew tap jianzhoujz/tap
brew install --cask mac-browser-switch
```

### Update

```bash
brew update
brew upgrade --cask mac-browser-switch
```

### Uninstall

```bash
brew uninstall --cask mac-browser-switch
```

### Manual install

Download `BrowserSwitch-<version>.dmg` from
[GitHub Releases](https://github.com/jianzhoujz/mac-browser-switch/releases),
open the DMG, drag `BrowserSwitch.app` to `Applications`, then launch from
`/Applications`.

## First launch

The app is **ad-hoc signed** (no paid Apple Developer ID). macOS may show one
of:

- "BrowserSwitch can't be opened because Apple cannot check it for malicious
  software" — open `System Settings → Privacy & Security`, scroll down, click
  `Open Anyway`.
- "BrowserSwitch is damaged and can't be opened" — remove the quarantine
  attribute:

  ```bash
  xattr -dr com.apple.quarantine /Applications/BrowserSwitch.app
  ```

That's the only one-time hurdle. The app needs **no special permissions** —
no Accessibility, no Input Monitoring, no Full Disk Access.

## How a switch works

When you click a browser in the menu, BrowserSwitch asks LaunchServices to
set that app as the default for `http` and `https`. macOS then pops its own
confirmation dialog:

> Do you want to change your default web browser to **Firefox**?

Click **Use "Firefox"** and the switch is done. The checkmark in the menu
moves to Firefox on next open.

This dialog is a macOS security feature on the default-browser scheme — it
appears even for notarized commercial apps (Velja, Browserosaurus, etc.).
There is no entitlement that suppresses it. BrowserSwitch does not try to
bypass it.

## Menu structure

```
BrowserSwitch
──────
   Safari
 ✓ Google Chrome              ← current default
   Arc
   Firefox
   Microsoft Edge
   …                          ← every app registered as an https handler
──────
 ☑ Launch at login
   Check for updates…
   GitHub Homepage
──────
   Version 0.1.0
   Quit                        ⌘Q
```

The browser list is rebuilt every time you open the menu, so freshly
installed browsers appear immediately.

## Requirements

- macOS 12.0 Monterey or newer
- Apple Silicon or Intel Mac

## Prefer the command line?

If you'd rather script default-browser switching, the
[`defaultbrowser`](https://github.com/kerma/defaultbrowser) Homebrew formula
does the same job from a terminal. BrowserSwitch is just the menu bar UI on
top of the same `LSSetDefaultHandlerForURLScheme` API; the two tools
coexist.

## Development

### Build

```bash
./build.sh                   # → build/BrowserSwitch.app
```

Produces a universal binary (`arm64` + `x86_64`), ad-hoc signed.

### Local install / dev loop

```bash
./install.sh                 # stop old → build → copy to /Applications → register LaunchAgent
./uninstall.sh               # reverse
```

### Package DMG

```bash
./package-dmg.sh             # → dist/BrowserSwitch-<version>.dmg
```

### Release (maintainer only)

```bash
./scripts/package-release.sh 0.2.0
```

Builds the DMG, updates the sha256 in `../homebrew-tap/Casks/mac-browser-switch.rb`,
and prints the `gh release create` command for you to run manually.

### Logs

```text
~/Library/Logs/BrowserSwitch.log
```

Auto-rotated past 1 MB. Reachable from the menu via `GitHub Homepage → …` is
not the right place — open the file directly if you need to debug.

## Feedback

Bug reports and feature requests:
[GitHub Issues](https://github.com/jianzhoujz/mac-browser-switch/issues).

## License

MIT. See [LICENSE](LICENSE).
