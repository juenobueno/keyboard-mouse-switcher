# Keyboard Mouse Switcher

A tiny macOS menu-bar app that makes a Logitech mouse follow a Bluetooth keyboard between two Macs.

When the watched keyboard disconnects from this Mac (because you switched it to the other computer), the app tells the
mouse to switch to the other Easy-Switch channel too. Run it on both Macs and the mouse follows the keyboard back and
forth.

It has two parts:

- **`Follow.m`** – the menu-bar app. Watches IOKit for the keyboard connecting/disconnecting over Bluetooth and, on
  disconnect, runs the bundled `mxswitch` helper.
- **`mxswitch.c`** – a dependency-free CLI that switches a Logitech Easy-Switch device to another channel via HID++
  2.0 feature `0x1814` (ChangeHost). MIT licensed, see [LICENSE-mxswitch](LICENSE-mxswitch).

## Requirements

- macOS 13 or later (Apple silicon or Intel; the build is universal)
- Xcode Command Line Tools (`xcode-select --install`) for `clang` and `codesign`

As written, the app targets these devices (change the strings in the source to use others):

| What     | Where                                                                       | Default          |
| -------- | --------------------------------------------------------------------------- | ---------------- |
| Keyboard | `Follow.m`, `drain:` – product name prefix, must be connected via Bluetooth | `NuPhy Air75 V2` |
| Mouse    | `Follow.m`, `sendMouse` – `--name` filter passed to `mxswitch`              | `MX Master 3`    |
| Mouse    | `mxswitch.c`, `find_devices` / `list_devices` – USB product ID filter       | `0xb023`         |

`0xb023` is the MX Master 3's Bluetooth product ID. For a different Logitech mouse, find its product ID in
System Information → Bluetooth (or `ioreg -r -c IOHIDDevice -l | grep -i -A2 logitech`) and update both checks.

## Build

```bash
git clone <this-repo-url> keyboard-mouse-switcher
```

```bash
cd keyboard-mouse-switcher && ./build.sh
```

This produces `build/Keyboard Mouse Switcher.app` (ad-hoc signed) and a zipped copy next to it. Move the app to
`/Applications` if you like.

## Setup (on each Mac)

1. Pair the keyboard and the mouse with both Macs, using Easy-Switch channel 1 on one Mac and channel 2 on the other.
2. Open **Keyboard Mouse Switcher**. A keyboard icon appears in the menu bar.
3. In its menu, under **This Mac is**, choose the slot this Mac uses (Slot 1 or Slot 2).
4. Choose **Enable Input Monitoring…** and click **Open System Settings** / allow when macOS asks. The menu item turns
   into a checked **Input Monitoring Enabled** once access is granted.

### Why Input Monitoring?

Watching the keyboard connect and disconnect needs no permission; that's plain IOKit device notifications. The
permission is for the *other* half: sending the switch command to the mouse. That means opening the mouse's HID
device and writing a HID++ report to it. The MX Master 3 exposes its HID++ channel through a keyboard-class HID
collection, and macOS only lets an app open keyboard-class devices with Input Monitoring. Without it the open fails
with `kIOReturnNotPermitted`, and writing without opening fails with `kIOReturnNotOpen`. The app never reads your
keystrokes.
5. Optionally enable **Open at Login**.

Now switch the keyboard to the other Mac: when it disconnects here, the mouse is sent to the other slot. The menu shows
the last action, e.g. "Sent mouse to slot 2" or "Mouse unavailable · check Input Monitoring".

Because the app is ad-hoc signed, Gatekeeper may block the first launch of a downloaded copy. Right-click the app →
**Open**, or build it locally with `./build.sh`.

## Using `mxswitch` on its own

The helper lives at `Keyboard Mouse Switcher.app/Contents/MacOS/mxswitch` and works as a standalone CLI:

```text
mxswitch {1|2|3|--info|--status|--toggle|--list|--setup}
         [--all] [--name SUBSTR] [--dry-run] [--json] [--verbose] [--config PATH]
```

- `mxswitch 2` – switch the mouse to channel 2
- `mxswitch --toggle` – switch between `channel_a` and `channel_b` from the config
- `mxswitch --info` / `--status` – show device, channels, battery and firmware (`--json` for JSON)
- `mxswitch --list` – list matching HID collections
- `mxswitch --setup` – open Input Monitoring settings if this binary isn't granted yet

Optional config at `$XDG_CONFIG_HOME/mxswitch/config` or `~/.config/mxswitch/config`:

```ini
channel_a = 1
channel_b = 2
device = primary   # or "all"
name = MX Master   # comma-separated name substrings
```

Exit codes: 0 ok, 1 device not found, 2 bad usage, 3 partial `--all` failure.

## License

`mxswitch.c` is MIT licensed (Copyright (c) 2026 Marco Costa); see [LICENSE-mxswitch](LICENSE-mxswitch).
