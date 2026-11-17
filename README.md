# CORNE ZMK WITH DONGLE

ZMK (`main`, Zephyr 4.1) for Corne on nice!nano v2, with a dongle
(nice!nano or XIAO BLE) or without one. Keymap is editable live in
[ZMK Studio](https://zmk.studio).

![1](./img/keymap-img/corne.svg)

## Firmware

GitHub Actions (or `scripts/zmk-docker.sh build` locally, into `firmware/`) builds:

| Setup | Part | File |
|---|---|---|
| dongle | dongle (nice!nano) | `corne_central_dongle-nice_nano_zmk.uf2` |
| dongle | dongle (XIAO BLE) | `corne_central_dongle-xiao_ble_zmk.uf2` |
| dongle | left / right half | `corne_peripheral_left-…`, `corne_peripheral_right-…` |
| no dongle | left half (central) / right half | `corne_central_left-…`, `corne_peripheral_right-…` |
| any | clear bonds and settings | `settings_reset-…` |

Flash all parts from the same build: the split protocol between dongle and
halves must match. Each part is flashed separately over USB: double-tap reset,
the part shows up as a UF2 drive (`NICENANO`, `XIAO-SENSE`), copy the `.uf2`
onto it, the part reboots.

```sh
scripts/flash-all.sh              # guided: dongle, left, right, then Studio check
scripts/flash-all.sh --no-dongle  # left as central, right
scripts/flash-all.sh --reset      # settings_reset before each part (halves don't pair)
scripts/flash.sh dongle|left|right|central-left|reset   # one part
```

`flash.sh` waits for the drive, picks the file by board (`INFO_UF2.TXT`),
copies it and waits for the drive to disappear. `flash-all.sh` prompts for
each part, refuses to start a step while another part is still in the
bootloader, and at the end reads the keymap over Studio and compares it with
`tests/hardware/keymap.txt`. Left and right halves are not distinguishable by
the script: connect the one it asks for.

### Bootloader key

The keymap has no `&bootloader` key. If one is added back, note that it runs
on the part where the key is pressed (ZMK "event source" locality): a key on
the left half puts the **left half** into the bootloader, never the dongle.
The dongle only enters the bootloader by double-tapping its reset.

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
scripts/studio_check.py --check tests/hardware/keymap.txt   # diff against the reference dump
```

`tests/hardware/keymap.txt` is the keymap read from the flashed keyboard
(`--save` to refresh it after intentional changes).

## Keymap tests

`tests/cases/*.test` script key presses on the real `config/corne.keymap` and
list the expected HID output. The firmware is compiled for ZMK's `native_sim`
board with a mock key matrix and runs as a Linux process: no keyboard and no
host OS involved.

```text
# Удержание A (LGUI) + клавиша правой руки = GUI+H
press A
wait 300
tap H
release A
---
press LGUI
press H
release H
release LGUI
```

- Script: `press|release|tap <key>`, `wait <ms>` (gap after the previous
  event, default 10 ms). Key names are base-layer legends, thumbs are `T1`–`T6`
  (see `POSITIONS` in `tests/run_tests.py`).
- Expected: `press|release <usage> [MODS]`, `mouse <buttons>`.
- `@xfail` in a comment marks a known issue.

```sh
scripts/zmk-docker.sh update        # once: fetch ZMK/Zephyr into a Docker volume
scripts/zmk-docker.sh test          # all cases; `test hrm combo` filters by name
ACCEPT=1 scripts/zmk-docker.sh test NAME   # write actual output as expected
```

CI runs the tests before building firmware.
