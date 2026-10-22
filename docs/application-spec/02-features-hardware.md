# 02 - Features and hardware targets

## Feature list

| # | Feature | Where it is implemented | Notes |
|---|---|---|---|
| F1 | Clamp at 80 % while plugged in | `bin/gleipnir:435-437`, `clamp()` at `:376-388` | Requires the verification marker, a charger online, charge at or above 80 %, and 120 s since the last change |
| F2 | Release when unplugged | `bin/gleipnir:445` | Checked each poll (30 s default) |
| F3 | Release at 77 % or below | `bin/gleipnir:446` | Hysteresis band 77-80 % |
| F4 | Restore the value found, not a maximum | `bin/gleipnir:364-375`, `:378` | Falls back to the node maximum when no value was saved (`:366`, `:369-370`) |
| F5 | Monitor-only until verified | `bin/gleipnir:425-433`, `:466-467` | Without a valid marker the daemon never writes a clamp |
| F6 | Supervised safety test | `bin/gleipnir:274-352` | Writes the clamp for up to 180 s; writes a marker only on PASS |
| F7 | Watchdog | `bin/gleipnir:447-454` | Still charging above 200 mA, 120 s after a clamp, three polls in a row: release, delete the marker, exit 78 |
| F8 | Late-clamp correction | `bin/gleipnir:421-424` | A clamp the daemon did not make is written back to the maximum within one poll |
| F9 | Settle and hold for writes | `bin/gleipnir:108-161` | Writes are judged by waiting for the node to show them (up to 120 s); restores must hold 20 s |
| F10 | Leftover-clamp cleanup at start | `bin/gleipnir:395` | Runs before the loop, whether or not the daemon is armed |
| F11 | Undo a clamp on any stop | `bin/gleipnir:389-391`; `systemd/gleipnir.service` `ExecStopPost` | Exit trap releases; the unit runs `--restore` after any stop |
| F12 | Stuck-not-charging warning | `bin/gleipnir:401-411` | Logs `NOT CHARGING with the limit released` at most every 10 minutes |
| F13 | Heartbeat | `bin/gleipnir:493-495` | Every 600 s by default |
| F14 | Sleep setting and hooks | `bin/gleipnir:164-171`, `:190-197`, `:222-254`; `systemd/gleipnir-sleep.service` | Setting 0 (default), 70 or 101; stored in `/var/lib/gleipnir/sleep-floor` |
| F15 | Fake-sleep detection | `bin/gleipnir:168-171` | Reads `ARMADA_SUSPEND_MODE` from `/usr/libexec/armada/device-env`; the panel hides the setting in fake sleep (`dist/index.js:120`) |
| F16 | Status report | `bin/gleipnir:256-272` (JSON), `:265-271` (text) | Never writes the node |
| F17 | Kernel-version workaround for Decky under FEX-Emu | `bin/gleipnir:48-60`, `:173-187`, `:426-429` | Adopts a marker stamped `6.11.0` when the host kernel differs; see the CHANGELOG entry "Fixed: kernel mismatch under FEX-Emu" (under Unreleased) |
| F18 | Decky panel | `main.py`, `dist/index.js` | Install, enable toggle, sleep dropdown, test, cancel, log, restore, uninstall |
| F19 | Opt-in debug logging | `bin/gleipnir:79`, `:114`, `:201`, `:491` | Off by default; `--debug` or `GLEIPNIR_DEBUG=1` (the flag is not in `docs/cli.md`; see `06-limitations-glossary.md`) |

`CHANGELOG.md` has a single heading, "Unreleased"; its header line says 0.1.0 was tagged 2026-10-07 and 0.2.0 on 2026-10-08 "adds the sleep clamp and its setting". The entries for F14 and F15 are in that section, as are F17 and F19.

## Hardware and software targets

### Tested target (repo-reported)
- AYN Thor running Armada OS, build `20261006.9c7dd3e`, kernel `7.2.6`. Source: `README.md` status line; `docs/evidence.md` observations dated 2026-10-07 and 2026-10-08. The field observations are recorded in those documents and were not re-observed for this spec.
- Decky Loader running on the Thor. The CHANGELOG records that Decky runs as an x86_64 binary under FEX-Emu on ARM64 Linux (`CHANGELOG.md`, Unreleased, "Fixed: kernel mismatch under FEX-Emu").
- Power supplies read by the code: `battery` and `qcom-battmgr-usb` (`bin/gleipnir:43-45`). The evidence page lists four supplies seen on the Thor (`docs/evidence.md`, 2026-10-07 entry); the charger's `online` flag is read from `qcom-battmgr-usb`.

### Other builds
`README.md` says other builds are untested. The daemon is written to detect the limit node per kernel, but no other kernel has been tested in the repo.

### Limit nodes the daemon understands

| Node | Clamp value | Source of the node | Selection order |
|---|---|---|---|
| `charge_control_limit` (and `charge_control_limit_max`) | `1000` (µA) | MgeeeeK's patched `qcom_battmgr` (`docs/how-it-works.md`) | Checked first (`bin/gleipnir:100-101`) |
| `constant_charge_current` (and `constant_charge_current_max`) | `0` | Armada kernel patch 0903 (`docs/evidence.md`) | Checked second (`bin/gleipnir:102-103`) |

When neither node exists the daemon exits 78 and the status says there is no usable limit (`bin/gleipnir:205-209`).

### Node behaviour recorded in the repo (repo-reported, not re-observed)
- A write to the node can take about a minute to show in readback and to act (`docs/evidence.md`, 2026-10-08 first run). The code waits up to 120 s (`bin/gleipnir:70`).
- The firmware changes the value by itself (`docs/evidence.md`: 9000000 at 73 %, 4680000 at 96 %). Hence the restore-what-was-found rule.
- A clamp on the Thor stopped charging in the recorded tests, and charging resumed after restore in the recorded tests (`docs/evidence.md`). One recorded case did not resume (see `06-limitations-glossary.md`).

### Operating system and runtime
- systemd service and oneshot sleep unit (`systemd/`).
- Bash, with `logger`, `hostnamectl`, `busctl`, `journalctl`, `systemctl`, `sed`, `tr`, `head`, `seq` (`bin/gleipnir`).
- Python 3 for the Decky backend (`main.py`). The README says Python 3 and bash are already on the Thor.

## The Decky panel (what the user sees)
Sections in `dist/index.js` (`:97-190`):

1. **Gleipnir: 80% charge ceiling.** State line, battery line (`capacity % · status · mA · °C · health`, `:40-44`), an optional "Problem" row from the status error, the install button when not installed, a sleep-type line, the "Charge cap while asleep" dropdown (options 0, 70, 101; hidden in fake sleep), and the "Enabled" toggle.
2. **Safety test.** A description of the test, a "Run test" button (disabled unless `usb_online` is 1), a cancel button while running, a "Last result" line from the verdict (`pass`, `fail`, `aborted`, `refused`), and the last 12 lines of test output.
3. **Log and maintenance.** "Show recent log" (15 lines), "Restore normal charging now", and "Uninstall daemon".

The panel polls the status every 2 seconds (`dist/index.js:67`).

Note on the panel's verdict text: the `refused` verdict is shown as "Not run: conditions not met (see output)" (`dist/index.js:95`). The backend assigns `refused` for output lines beginning `Refusing` or `Run as root` (`main.py:46-57`, `_verdict`).
