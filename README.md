<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Resizer icon">
</p>

<h1 align="center">Resizer</h1>

<p align="center">
  Mark the part of your screen that goes on stream, snap windows into it,<br>
  and resize any macOS window to an exact resolution, right from the menu bar.<br>
  Free and open source.
</p>

---

## Features

### Stream Zone

Made for streaming from a big or ultrawide monitor: only a 16:9 area in the middle goes on stream (crop your display capture in OBS), and Resizer helps you keep the right windows inside it.

- **Zone frame:** a soft, rounded frame around the area that goes on stream, in red, blue, white, green or purple. It's drawn just outside the zone, so it never shows up on stream.
- **Fits any screen:** pick the display and a size (1280×720, 1920×1080, 2560×1440… or *Max*, the largest 16:9 area that fits). On a 5120×1440 ultrawide, Max is the middle 2560×1440.
- **OBS crop values:** the exact Left / Right / Top / Bottom pixels to type into *Display Capture → Crop*.
- **Snap on drop:** hold `⇧ Shift` while dragging a window into the zone and drop it: in the middle it fills the zone, near the left or right edge it takes that half. Without the key, windows just move as usual. The key can be changed to `⌥`, `⌃` or `⌘`.
- **Shortcuts:** `⌃⌥⌘↑` fills the zone with the focused window, `⌃⌥⌘←` / `⌃⌥⌘→` give it the left / right half.
- **Dim outside** (optional) darkens everything that isn't on stream.

### Window Resizer

- **Any app:** Safari, Chrome, Discord, Finder, VS Code, OBS…
- **Exact resolution:** type width × height (numbers only, capped at your screen's resolution).
- **Presets:** 1280×720, 1920×1080 and more; save your own and delete them with a right-click.
- **Multiple windows at once:** check as many as you like and hit *Apply*.
- **Global shortcut `⇧⌥R`** (Shift + Option + R): applies the current size to the focused window.
- **Center on screen** and **Open at Login**.

Click the menu bar icon to open the settings window; right-click it for quick toggles and Quit.
- Runs on **Apple Silicon and Intel** Macs, macOS 13 (Ventura) or later.

## Installation

1. Download **`Resizer.zip`** from the [latest release](../../releases/latest).
2. Unzip it and drag **Resizer.app** into your **Applications** folder.
3. **Allow it to open.** Resizer isn't notarized by Apple (that needs a paid developer account), so the first time macOS says it can't verify the app. Either:
   - open Terminal and run:
     ```bash
     xattr -dr com.apple.quarantine /Applications/Resizer.app
     ```
   - or double-click the app, close the warning, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
4. **Give it the Accessibility permission.** Open Resizer; macOS asks for it. Turn Resizer on under **System Settings → Privacy & Security → Accessibility**. This is what lets it move and resize other apps' windows.

The icon shows up in the menu bar at the top of the screen: click it for settings, right-click for quick toggles and Quit.

### Updating

Quit Resizer, replace the app in **Applications** with the new one and do step 3 again.

Released builds aren't signed with an Apple Developer ID, so macOS treats each new version as a different app and the Accessibility permission doesn't carry over: remove the old Resizer entry from the Accessibility list with **–** and turn the new one on. The settings window's **Reset Permission** button does the same.

## Building from source

Requires Xcode (or the Command Line Tools).

```bash
git clone https://github.com/dudssecco/Resizer.git
cd Resizer
./build.sh --install
```

| Command | What it does |
|---|---|
| `./build.sh` | Builds `build/Resizer.app` |
| `./build.sh --install` | Builds and installs to `/Applications` |
| `./build.sh --release` | Builds `dist/Resizer.zip` for publishing (always ad-hoc signed) |
| `./tools/make_signing_cert.sh` | Creates your own local signing certificate (optional, run once) |
| `./tools/make_icns.sh` | Regenerates the icon from `tools/make_icon.swift` |

### Optional: your own signing certificate

By default builds are *ad-hoc* signed: every build gets a new signature, and macOS forgets the Accessibility permission each time you rebuild. If you build often, create your own certificate once so every build on your Mac has the same signature and the permission sticks:

1. Create the certificate. It's self-signed, lives only in your login keychain and is named **Resizer Local Signing**:
   ```bash
   ./tools/make_signing_cert.sh
   ```
2. Build and install. `build.sh` finds the certificate and signs with it (if macOS asks for keychain access, choose **Always Allow**):
   ```bash
   ./build.sh --install
   ```
3. Grant the permission one last time: in **System Settings → Privacy & Security → Accessibility**, remove the old Resizer entry with **–**, then turn the new one on. From then on, rebuilds keep it.

Notes:
- The certificate is only for your own builds. `./build.sh --release` ignores it, so it never ends up in a published zip.
- Keep it if you'll keep building: if you delete or lose it, your next build has a new signature and you grant the permission again once.
- To remove it, delete **Resizer Local Signing** in Keychain Access, or run:
  ```bash
  security delete-identity -c "Resizer Local Signing"
  ```

## Limitations

- Some apps enforce their own minimum or maximum window size; Resizer tells you when a window didn't reach the requested size.
- Full-screen windows can't be resized.
- If the Accessibility permission stops working after an update or a rebuild (the settings window shows a warning), remove Resizer from the Accessibility list with **–** and add it again, or click **Reset Permission**.
- The Stream Zone is always centered on its screen.

## License

[MIT](LICENSE)
