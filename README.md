# OpenIn — Browser Picker for macOS

> Intercepts every link you click from any app (Slack, WhatsApp, Mail, Telegram…) and lets you choose which browser — and which profile — to open it in.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Instant picker popup** every time a URL is opened from outside a browser
- **All installed browsers** detected automatically — Chrome, Brave, Edge, Firefox, Safari, Arc, Vivaldi, Opera, and more
- **Per-profile rows** — Chrome/Brave/Edge/Firefox profiles each appear as separate entries with their profile name and avatar email
- **Per-app rules** — tell OpenIn to always open WhatsApp links in Chrome Work, Slack links in Firefox, etc.
- **Incognito/Private mode** per row — hover to reveal the "Private" button, or press `⇧` + a number key
- **Keyboard-first** — `1–9` to pick, `↑↓` to navigate, `↩` to open, `⎋` to cancel, `⇧↩` / `⇧N` for private
- **Menu bar app** — no Dock icon, lives quietly in the menu bar
- **Open at Login** — single click to add/remove from login items
- **Auto-update** — checks GitHub on launch and notifies when a new version is available

---

## Install

### Option A — Download DMG (recommended)

1. Download `OpenIn.dmg` from [Releases](https://github.com/mindgame0909/openin/releases/latest)
2. Open the DMG and drag **OpenIn** → **Applications**
3. Launch OpenIn from Applications (right-click → Open the first time to bypass Gatekeeper)
4. **System Settings → Desktop & Dock → Default web browser → OpenIn**

### Option B — Build from source

```bash
# Requires Xcode Command Line Tools
xcode-select --install

git clone https://github.com/mindgame0909/openin.git
cd openin
make install
```

Then set OpenIn as your default browser in **System Settings → Desktop & Dock**.

---

## Usage

After setting OpenIn as your default browser, click any link in Slack, Mail, WhatsApp, etc. — a picker will appear:

- Click a browser row to open normally
- Hover and click **Private** (or press `⇧` + number) to open in incognito/private mode
- Check **"Always open [App] links here"** to save a rule for that app

Manage saved rules from the menu bar icon → **Manage App Rules**.

---

## Profiles detected

| Browser | Source |
|---|---|
| Chrome | `~/Library/Application Support/Google/Chrome/Local State` |
| Brave | `~/Library/Application Support/BraveSoftware/Brave-Browser/Local State` |
| Edge | `~/Library/Application Support/Microsoft Edge/Local State` |
| Firefox | `~/Library/Application Support/Firefox/profiles.ini` |
| Safari / others | Single entry (no profiles) |

---

## Auto-Update

OpenIn checks `latest.json` on GitHub on every launch. When a new version is available, the menu bar icon shows **"⬆ Update Available"** — click it to download the new DMG.

---

## Publishing an Update

1. Make your changes
2. Bump `CFBundleShortVersionString` in `Resources/Info.plist`
3. Run `make dist` — produces `OpenIn.dmg`
4. Create a GitHub release: `gh release create vX.Y.Z OpenIn.dmg`
5. Update `latest.json` with the new version and DMG URL, push to `main`

---

## Uninstall

```bash
rm -rf /Applications/OpenIn.app
# Remove login item if enabled:
rm -f ~/Library/LaunchAgents/com.personal.openin.plist
# Then set another browser as default in System Settings
```

---

## License

MIT
