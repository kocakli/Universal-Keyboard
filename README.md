# KeyMapper

A universal keyboard mapper for macOS that lives in the menu bar. Pick a connected keyboard and assign a layout (keymap) to it; KeyMapper chooses the right way to edit it from the keyboard's firmware.

## Download

**[Download KeyMapper for Mac (.dmg)](https://github.com/kocakli/Universal-Keyboard/releases/latest/download/KeyMapper.dmg)** · [all releases](https://github.com/kocakli/Universal-Keyboard/releases)

Requires a Mac with Apple silicon and macOS 15 or later.

1. Open the downloaded disk image and drag **KeyMapper** onto the **Applications** shortcut.
2. Open KeyMapper from Applications. It is signed and notarized by Apple, so it opens without a security warning.
3. KeyMapper lives in the menu bar (keyboard icon) and has no Dock icon; opening it again from Finder or Spotlight brings up the editor.

macOS asks for **Bluetooth** permission the first time a Bluetooth LE keyboard is connected (used only to read its battery level) and for **Accessibility** only when you use an action that sends a key combination or types text.

To build it yourself instead, see [Installation](#installation).

| Keyboard type | Examples | How it is edited |
|---|---|---|
| **Vial** | Cornix, Corne (crkbd), Lily58, Sofle and every keyboard that works with vial.rocks | The definition is read from the keyboard itself (USB or Bluetooth) and the keymap is written to firmware |
| **VIA / QMK** | Keychron (Q/V/K Pro…), NuPhy, KBDfans, Keebio, DZTech, Glorious GMMK Pro… | The definition is downloaded from the VIA repository (usevia.app) or Keychron Launcher, or loaded from a JSON file; the keymap is written to firmware |
| **Every other keyboard** | Logitech, Apple Magic Keyboard, Razer, Corsair, SteelSeries, HyperX… | Key remapping at the macOS level (`hidutil`) that applies **only to that keyboard** and is re-applied every time it connects |

The method is chosen from the interface the device exposes, not from its brand: any keyboard with a QMK raw HID interface (usage page `0xFF60`) is edited through VIA/Vial, and any keyboard without one through macOS remapping. That is why brands that aren't listed work too.

## Features

- **Menu bar**: connected keyboards with their connection (USB / Bluetooth / Bluetooth LE), battery level, support type, and one-click layout (profile) assignment.
- **Editor**: the keyboard's real physical layout (including rotated thumb keys, encoders and layout options), layers, and assigning a new function to any key.
- **Keycodes**: basic keys, modifiers, media, mouse, layer keys (`MO`, `TG`, `TO`, `TT`, `OSL`, `DF`), mod-tap / home row mods (`LSFT_T(KC_A)`), layer-tap (`LT(1, KC_SPC)`), combinations (`LCTL(KC_C)`), macros and keyboard-specific keycodes (e.g. the Cornix's `BT0`, `NEXT_BT`). Legacy (QMK < 0.19) and current keycode numbering are detected automatically.
- **"When held" menu**: add mod-tap or layer-tap to the selected key with one click.
- **Alphabet conversion**: QWERTY ⇄ Colemak / Colemak-DH / Dvorak / Workman, keeping home row mods and layer-taps. KeyMapper remembers each layer's current alphabet, so a layer can't be converted twice by mistake, and the last conversion can be undone. Also available as a ready-made remap for macOS-level keyboards.
- **Profiles**: save the current layout as a profile and restore it from the menu bar. Only the keys that differ are written.
- **Import / export**: Vial `.vil` (files saved from vial.rocks), VIA `.json` layout files and KeyMapper profiles.
- **Vial unlock**: the Vial unlock flow for protected keys such as `QK_BOOT`.
- **Actions** (like the per-app settings in Logitech Options+): assign a key to open an app, open a URL or file, run a Shortcut, send a key combination or type text. The same key can do different things depending on the frontmost app (e.g. a new tab in Safari, the command palette in VS Code, Spotlight everywhere else). Ready-made shortcuts cover about 30 apps, including Claude (approve / deny), ChatGPT, Terminal, iTerm2, Warp, Ghostty, Safari, Chrome, Brave, Arc, Firefox, Finder, Mail, Music, VS Code, Cursor, Xcode, Zoom, Teams, Slack, Discord, Notion, Obsidian, Word, Excel, PowerPoint, Photoshop, Final Cut Pro and Spotify.
- **Battery level**: the charge of connected keyboards appears in the menu bar, the sidebar and the editor header, in red at 20 % and below. Apple keyboards are read through macOS, Bluetooth LE keyboards (e.g. the Cornix) through the standard Bluetooth Battery Service, which asks for Bluetooth permission the first time. Split keyboards show the lower half. Keychron's raw HID protocol has no battery command, so a Keychron connected over USB shows no battery.
- **Launch at login** option.
- **Languages**: Türkçe, English, Español, 日本語 and 简体中文. The app follows the macOS language by default and can be switched instantly from the menu bar or the editor's sidebar. `kmctl` uses the same setting (override it for one command with `KEYMAPPER_LANG=ja kmctl list`).

## How actions work

1. Every action uses a trigger key: F16–F20 first, then F13, and F14/F15 last (macOS uses F14/F15 for screen brightness). Regular keyboards don't have these keys, so they don't clash with anything.
2. In the keyboard editor, select a key and pick **Open app**, **Open URL / file**, **Run Shortcut**, **Send key combination**, **Type text** or **Media / system key** directly from the palette's **Apps & actions** tab. KeyMapper reserves a free trigger key, binds the action to it and writes it to the key (to firmware on VIA/Vial, as a macOS remap on other keyboards). Keys that open an app show the app's icon; change a key's action with **Edit action** on the selected key's card.
3. KeyMapper catches the trigger key through the macOS global hotkey API (Carbon `RegisterEventHotKey`), so the key never reaches the frontmost app. If the frontmost app has a rule, that rule runs; otherwise the default action runs.

### App tabs (like Logi Options+)

The top right of the keyboard view shows **All apps** and app icons; add an app with **+**. With an app selected, each key shows what it does in that app. Clicking a key and choosing one of that app's ready-made shortcuts (e.g. Undo in Photoshop, Switch tab in Chrome) or a custom action turns the key into a **smart key**: a trigger key is written to firmware (or to the macOS remap), the new function runs in the selected app, and in every other app KeyMapper sends the key's previous function unchanged (a letter, a shortcut or a volume/media key). Modifier and layer keys must stay holdable, so they are never turned into smart keys.

Permissions: opening apps, URLs and Shortcuts **needs no permission**. Sending key combinations and typing text needs the macOS **Accessibility** permission; KeyMapper asks for it only when such an action is used. With ad-hoc signed builds macOS may reset this permission after every rebuild; if that happens, remove KeyMapper in System Settings › Privacy & Security › Accessibility and add it again.

## Installation

Requirements: macOS 15+, Xcode 16+ (Swift 6 toolchain).

```bash
scripts/build-app.sh --install
```

This builds `build/KeyMapper.app` and copies it into `/Applications`. Run it without `--install` to only build.

To build an installable package (disk image):

```bash
scripts/make-dmg.sh
```

This creates `build/KeyMapper-<version>.dmg`; open it and drag KeyMapper onto the Applications shortcut. With `--install`, the app inside the disk image is installed straight into `/Applications` (a running copy is quit first).

By default the build is ad-hoc signed: it runs on the Mac that built it, but macOS blocks the first launch on another Mac (allow it with **Open Anyway** in **System Settings → Privacy & Security**). For a package that opens anywhere, sign it with a Developer ID and have Apple notarize it:

```bash
xcrun notarytool store-credentials KeyMapper-notary --apple-id "<Apple ID>" --team-id <TEAMID>
```

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=KeyMapper-notary scripts/make-dmg.sh
```

The first command is needed once; it asks for an app-specific password from account.apple.com and stores it in the keychain. The second signs the app and `kmctl` with the hardened runtime and a secure timestamp, signs the disk image, submits it to Apple's notary service, waits for the result (usually a few minutes) and staples the ticket to the disk image. If Apple rejects it, the script prints the notary log and stops. A Developer ID signature also keeps the Accessibility and Bluetooth permissions across rebuilds.

The app doesn't appear in the Dock; use the keyboard icon in the menu bar. Opening the app again from Finder or Spotlight brings up the editor window.

During development:

```bash
swift run KeyMapper -- --editor
```

```bash
swift test
```

## Command line (`kmctl`)

```bash
swift run kmctl list
```

| Command | Description |
|---|---|
| `kmctl list` | Connected keyboards, with the battery level when macOS reports one |
| `kmctl dump <n> [layer]` | Prints the keymap (and, for Keychron, the layer the keyboard is typing on) |
| `kmctl export <n> <file.vil\|file.json>` | Saves the keymap in Vial or VIA format |
| `kmctl apply <n> <file>` | Writes a `.vil` / VIA `.json` / profile file to the keyboard (only the keys that differ) |
| `kmctl remap <n> [preset\|clear]` | Applies or removes a ready-made macOS-level remap |
| `kmctl firmware <n>` | Installed firmware version and update check (Keychron) |

## Moving a layout from vial.rocks

1. Open your keyboard on vial.rocks and download the `.vil` file with **Save current layout**.
2. In the KeyMapper menu, under the keyboard's **Layout** row, click **+** and choose **Import from file (.vil / VIA .json)…**. The file is saved as a profile.
3. Select the profile in the same row to write it to the keyboard.

## Keychron: automatic definitions, layers and firmware updates

Newer Keychron models (e.g. the Nape Pro trackball and the V/Q/K Max series) aren't in the public VIA repository; Keychron Launcher distributes their definitions. For Keychron devices KeyMapper downloads the definition from Keychron Launcher's server automatically and caches it. Devices without a key matrix, such as trackballs and mice, can be edited too, buttons and knob included.

Layers: KeyMapper reads Keychron's Launcher protocol (both the QMK and the ZMK firmware families) to learn which layer the keyboard is typing on, follows layer changes the keyboard reports, and opens the editor on that layer. This matters because a key written to another layer seems to do nothing; the Nape Pro, for example, types on layer 1.

Firmware: KeyMapper reads the installed version from the device (Keychron's `0xA1` command, or the USB version field) and gets the latest version and its release notes from Keychron. When an update is available, an orange notice appears in the device header and the menu bar. Updates are installed with Keychron Launcher; KeyMapper never writes firmware. There is no public update source for generic VIA/QMK and Vial keyboards.

These Keychron endpoints are undocumented and may change; if they do, KeyMapper quietly falls back to the VIA repository and manually loaded definitions.

## If no definition is found

Some models from other brands (or keyboards connected through a 2.4 GHz receiver) are listed in the VIA repository under a different product ID. Download the VIA JSON file for your model from the manufacturer's site and add it in the editor with **Profile → Load VIA definition file…**.

## Known limitations

- Keyboards that only speak the ZMK Studio protocol aren't supported at the firmware level yet; they can be edited with macOS remapping. (Keychron's ZMK firmware speaks VIA and is supported.)
- Macros, tap dance, combos and RGB settings can't be edited yet (existing ones are kept).
- Key assignments made in other brands' software (e.g. Logi Options+) work separately; KeyMapper remaps on top of them at the macOS level.
- The built-in MacBook keyboard isn't listed.

## Architecture

```
Sources/
  KeyMapperCore/        Platform-independent core (tested)
    HID/                Device discovery with IOHIDManager, raw HID connection, battery levels
    Protocol/           VIA commands + Vial extensions, Keychron Launcher protocol, LZMA (xz) definition decoding
    Definitions/        VIA/Vial definition parsing (KLE + compiled VIA), VIA repository cache
    Keycodes/           QMK keycode tables (v5/v6), expression parsing/formatting
    Keymap/             Keymap model, keyboard session (read / write differences)
    Profiles/           Profiles, .vil / VIA import-export, alphabet layouts
    OSRemap/            Per-device macOS remapping based on hidutil
    Brands/             Manufacturer (VID) database
    Actions/            Trigger keys, action bindings and per-app presets
    Localization/       UI translations
  KeyMapper/            SwiftUI menu bar app + editor
  kmctl/                Command line tool
Resources/
  AppIcon.icon/         App icon (Icon Composer document; Liquid Glass)
  Glyph.png             Transparent glyph: in-app logo and menu bar icon
```

The icon is generated from `Resources/AppIcon.icon` with `actool` at build time: `Assets.car` for macOS 26 and later (the system derives the light, dark, tinted and clear icon styles automatically) and `AppIcon.icns` for older macOS. The document can be opened and edited in Icon Composer, which ships with Xcode.

Translations live in `Sources/KeyMapperCore/Localization/`: UI strings are written in Turkish in the source and marked with `L("…")`, and each language's dictionary uses those Turkish strings as keys. Tests check that every marked string is translated in every language with the same placeholders (`%@`).

Data is stored in `~/Library/Application Support/KeyMapper/` (profiles, the VIA definition cache and user definitions).
