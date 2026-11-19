# CORNE ZMK

ZMK (`main`, Zephyr 4.1) for Corne on nice!nano v2, with a dongle
(nice!nano or XIAO BLE) or without one. Keymap is editable live in
[ZMK Studio](https://zmk.studio).

## Principle: everything in the firmware, the computer stays default

The keyboard is meant to work on a computer with default settings: stock input
sources (ABC, Russian – PC), stock system shortcuts, no key remapping in the
OS. Every key, combo, modifier position and shortcut is defined in
`config/corne.keymap`, and the keymap sends the shortcuts the OS already
knows (e.g. Cmd+Shift+4 for a screenshot) instead of relying on custom ones.

Host-side setup is the exception and is allowed only when the firmware cannot
do it. Each exception is listed here, kept in this repo and applied by a script:

- macOS, punctuation in any input source: Karabiner-Elements (see
  [below](#macos-punctuation-in-any-input-source)). The keyboard cannot know the
  active input source, so it cannot pick the key for `.` or `,`.
- App launch shortcuts: the keymap sends a fixed chord (Hyper+letter), the OS
  binds it to an app (see [App launch](#app-launch-hyper)). The firmware cannot
  start programs.

## Target OS: one keymap, a build per OS

Shortcuts differ between systems (Cmd vs Ctrl, screenshots, lock), so the
central part (dongle, or left half without a dongle) is built for one OS:
`build.yaml` passes `-DOS_MAC` or `-DOS_LINUX` (GNOME) to the keymap, and the
"Target OS" block at the top of `config/corne.keymap` defines everything that
differs. The layers use only those names. A build without the flag fails.
Halves have one build for both systems. To switch OS, reflash the central part.

Modifiers are named by role:

| Role | macOS | Linux | Keys |
|---|---|---|---|
| `SC`, shortcut modifier (copy, paste, save) | Cmd | Ctrl | F, J (hold), left thumb, outer left pinky |
| `OT`, the other one | Ctrl | Super | A, ; (hold), Enter thumb (hold) |

So copy is the same physical chord on both systems (`SC`+C), and nothing is
remapped in the OS.

System keys, with the default shortcuts they send:

| Key | macOS | Linux (GNOME) |
|---|---|---|
| Utils (hold BSPC) + Esc: lock | Ctrl+Cmd+Q | Super+L |
| Utils + Q / W: display brightness − / + | `C_BRI_DN` / `C_BRI_UP` | same |
| Utils + E / R / T: screenshot screen / area / recording | Cmd+Shift+3 / 4 / 5 | Shift+Print / Print / Ctrl+Alt+Shift+R |
| Utils + (Ctrl key, A, S, D, F, G): mute, volume −, volume +, prev, play/pause, next | consumer keys | same |
| Nav (hold Space) + F / G: overview / app windows | Ctrl+↑ / Ctrl+↓ | Super / Super+A (app grid) |
| Nav + ; / ': previous / next desktop | Ctrl+← / Ctrl+→ | Ctrl+Alt+← / → |
| Nav + Z X C V B: undo, cut, copy, paste, redo | Cmd+Z… / Cmd+Shift+Z | Ctrl+Z… / Ctrl+Shift+Z |
| Del thumb (hold): Hyper | Ctrl+Opt+Shift+Cmd | Ctrl+Alt+Shift+Super |

The MacBook keyboard backlight has no HID usage for an external keyboard: use
Control Center. F1–F12 are plain F-keys on both systems (macOS applies the
"F1, F2 as standard keys" setting to Apple keyboards only); media and
brightness are separate consumer keys, so no Fn key is needed.

### App launch: Hyper

Hold the Del thumb and press a letter: Hyper+letter is free on both systems.
Bind it in the OS:

- macOS: Shortcuts app → new shortcut → action "Open App" → shortcut details
  (ⓘ) → "Add Keyboard Shortcut" → press Hyper+letter.
- GNOME: Settings → Keyboard → View and Customize Shortcuts → Custom
  Shortcuts → `+`, command e.g. `gnome-terminal`, press Hyper+letter.

Keep the bindings you set up listed here, so they can be restored on a new
machine.

### Moving a Mac to the macOS build

Earlier builds sent Linux modifiers and relied on a Ctrl ↔ Cmd swap in macOS.
After flashing the `-mac` central:

1. System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys → select
   Corne → "Restore Defaults".
2. `scripts/karabiner-setup.sh`: removes the swap from Karabiner too.

![1](./img/keymap-img/corne.svg)

The picture is rendered locally with [keymap-drawer](https://github.com/caksoylar/keymap-drawer)
(version pinned in the script, runs in Docker if not installed) and committed
together with the keymap. CI does not draw or check it.

```sh
scripts/draw-keymap.sh           # updates img/keymap-img/corne.{yaml,svg}
scripts/draw-keymap.sh --check   # fails if the images are outdated
git config core.hooksPath .githooks   # once per clone: pre-commit hook re-renders
                                      # and stages the images when the keymap is committed
```

If a global `core.hooksPath` dispatches to `.git/hooks/<name>`, link the hook
there instead, so the global hooks keep working:
`ln -s ../../.githooks/pre-commit .git/hooks/pre-commit`.

## Setups: with or without the dongle

| Setup | Central (talks to the computer, runs the keymap and Studio) | Peripherals |
|---|---|---|
| `dongle` | dongle on USB (nice!nano or XIAO BLE) | left and right half over BLE |
| `no-dongle` | left half, over USB or Bluetooth | right half over BLE |

The split role is compiled into the firmware (Kconfig), so the setup is
switched by flashing, not by a key. The right half has the same firmware in
both setups; the left half (and the dongle) change. A half keeps its pairing
with the old central, so switching needs a settings reset on every part:
`flash-all.sh` remembers the setup it flashed last (`.git/corne-flashed-mode`)
and turns `--reset` on by itself when the setup changes. Without the dongle,
unplug it: a powered dongle would take the right half back. The left half drains
its battery faster without the dongle: it keeps both the computer and the
right half connected.

Setups, boards and OSes are described once in `scripts/firmware.py`:
`build.yaml` is generated from it (`scripts/firmware.py gen`; the pre-commit
hook does it and CI checks it), and local builds and flashing pick the parts
of a setup from it. To add a setup (e.g. right half as central), add a shield
under `config/boards/shields/corne/` (key pins are in `corne_left.dtsi` /
`corne_right.dtsi`) and an entry in `MODES`.

## Firmware

GitHub Actions (or `scripts/zmk-docker.sh build` locally, into `firmware/`) builds:

| Setup | Part | File |
|---|---|---|
| dongle | dongle (nice!nano) | `corne_central_dongle-nice_nano_zmk-{mac,linux}.uf2` |
| dongle | dongle (XIAO BLE) | `corne_central_dongle-xiao_ble_zmk-{mac,linux}.uf2` |
| dongle | left / right half | `corne_peripheral_left-…`, `corne_peripheral_right-…` |
| no dongle | left half (central) / right half | `corne_central_left-nice_nano_zmk-{mac,linux}.uf2`, `corne_peripheral_right-…` |
| any | clear bonds and settings | `settings_reset-…` |

The central part has a file per OS (see [Target OS](#target-os-one-keymap-a-build-per-os)).

Flash all parts from the same build: the split protocol between dongle and
halves must match. Each part is flashed separately over USB: double-tap reset,
the part shows up as a UF2 drive (`NICENANO`, `XIAO-SENSE`), copy the `.uf2`
onto it, the part reboots.

```sh
scripts/zmk-docker.sh build --mode no-dongle --os mac --reset   # only the parts of one setup
scripts/firmware.py list --mode no-dongle --os mac             # which files that is

scripts/flash-all.sh                    # guided: dongle, left, right, then Studio check
scripts/flash-all.sh --mode no-dongle   # left as central, right (also: --no-dongle)
scripts/flash-all.sh --os linux         # central for this OS (default: the OS of this computer)
scripts/flash-all.sh --reset            # settings_reset before each part (halves don't pair)
scripts/flash-all.sh --no-reset         # no automatic reset when the setup changes
scripts/flash.sh dongle|central-left mac|linux   # one central part
scripts/flash.sh left|right|reset                # one half, or settings reset
```

`flash.sh` waits for the drive, picks the file by board (`INFO_UF2.TXT`),
copies it and waits for the drive to disappear. `flash-all.sh` prompts for
each part, refuses to start a step while another part is still in the
bootloader, and at the end reads the keymap over Studio and compares it with
`tests/hardware/keymap.<os>.txt` (saves it on the first run). Left and right halves are not distinguishable by
the script: connect the one it asks for.

### Bootloader key

The keymap has no `&bootloader` key. If one is added back, note that it runs
on the part where the key is pressed (ZMK "event source" locality): a key on
the left half puts the **left half** into the bootloader, never the dongle.
The dongle only enters the bootloader by double-tapping its reset.

## macOS: punctuation in any input source

The keyboard sends key codes, the input source turns them into characters, so
`.` `,` `?` sit on different keys in ABC and Russian – PC. The thumb keys of the
Num layer send keypad `1` `2` `3` (`KP_N1..3`), and
[Karabiner-Elements](https://karabiner-elements.pqrs.org) turns them into
`.` `,` `?` for the current input source. On other systems they stay keypad digits.

```sh
scripts/karabiner-setup.sh --diff   # what would change in ~/.config/karabiner/karabiner.json
scripts/karabiner-setup.sh          # apply (backup first) and start Karabiner
```

Karabiner is configured by `~/.config/karabiner/karabiner.json`, which it
reloads on save. The script changes only the Corne entries there, the rest stays:

- only the Corne is grabbed, the built-in keyboard is ignored;
- virtual keyboard type `ansi` (with `iso` macOS swaps `` ` ~ `` and `§ ±`);
- F1–F12 stay F-keys;
- no modifier remaps: the macOS build already has Cmd and Ctrl in place;
- rules from `macos/karabiner/*.json` (descriptions start with `Corne:`).

To change the characters or add an input source, edit
[macos/karabiner/corne-punctuation.json](macos/karabiner/corne-punctuation.json)
(key names: Karabiner-EventViewer) and run the script again.

## ZMK Studio

Studio runs on the central part (dongle, or left half without a dongle), over USB.

1. Connect the central by USB.
2. Open <https://zmk.studio> in Chrome/Edge (Safari has no WebSerial), or the
   desktop app from [zmk-studio releases](https://github.com/zmkfirmware/zmk-studio/releases)
   (`.dmg` for macOS).
   Linux: `.deb` from the same page, then "ZMK Studio" in the app menu.
   Only one client can hold the serial port: close the others first
   (`lsof /dev/ttyACM0` shows who holds it).
3. Unlock: `Utils` layer (hold BSPC thumb) + top-right key (`&studio_unlock`).
   Studio locks again on USB disconnect or after 10 minutes idle.
4. Edit keys and layers, then **Save**. Changes live in the keyboard flash and
   override `config/corne.keymap` until "Restore Stock Settings".

Two empty layers (`extra1`, `extra2`, `status = "reserved"`) are reserved in
the keymap for Studio: add them with `+` in the layer list.

Studio edits bindings and layers only. Combos, macros, tap-dance and
home-row-mod behaviors are defined in `config/corne.keymap` and can be
assigned to keys in Studio.

Linux: the serial port needs user access. Install the udev rule once:

```sh
sudo cp scripts/udev/70-zmk-studio.rules /etc/udev/rules.d/ && sudo udevadm control --reload-rules
```

Check that the keyboard answers Studio and reports the expected keymap
(read-only; needs `pyserial`):

```sh
scripts/studio_check.py                  # print layers read from the keyboard
scripts/studio_check.py --check tests/hardware/keymap.mac.txt   # diff against the reference dump
```

`tests/hardware/keymap.<os>.txt` is the keymap read from the keyboard flashed
with that OS build (`--save` to refresh it after intentional changes).

## Keymap tests

`tests/cases/*.test` script key presses on the real `config/corne.keymap` and
list the expected HID output. The firmware is compiled for ZMK's `native_sim`
board with a mock key matrix and runs as a Linux process: no keyboard and no
host OS involved.

```text
# Удержание A (OT: Super на Linux, Ctrl на Mac) + клавиша правой руки
press A
wait 300
tap H
release A
---
press OT
press H
release H
release OT
```

- Script: `press|release|tap <key>`, `wait <ms>` (gap after the previous
  event, default 10 ms). Key names are base-layer legends, thumbs are `T1`–`T6`
  (see `POSITIONS` in `tests/run_tests.py`).
- Expected: `press|release <usage> [MODS]`, `mouse <buttons>`.
- Each case runs for both OS builds (`-DOS_MAC`, `-DOS_LINUX`). Modifiers in
  the expected block can be roles: `SC`/`SC_R`, `OT`/`OT_R` (see
  [Target OS](#target-os-one-keymap-a-build-per-os)); concrete names
  (`LCTRL`) are compared as written.
- `@os mac` or `@os linux` in a comment runs a case for one OS only: for keys
  whose output differs beyond the roles (screenshots, lock).
- `@xfail` in a comment marks a known issue.

```sh
scripts/zmk-docker.sh update        # once: fetch ZMK/Zephyr into a Docker volume
scripts/zmk-docker.sh test          # all cases; `test hrm combo` filters by name
ACCEPT=1 scripts/zmk-docker.sh test NAME   # write actual output as expected
```

CI runs the tests before building firmware.
