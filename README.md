# Gleipnir

A [Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader) plugin for the **AYN Thor** on **Armada OS** that holds the battery at **80 %** while plugged in, to slow battery wear. It is named for the unbreakable ribbon that held Fenrir: a thin thing that restrains a large force.

> **Status: not proven on a real Thor battery yet.** Nobody has shown that the Thor's firmware stops charging when the limit below is written. So Gleipnir installs in **watch-only** mode and does nothing to charging until you run its built-in safety test and it passes on your kernel.

## Why it works the way it does
- The usual Linux control, `charge_control_end_threshold`, is ignored by the Thor's firmware: it accepts a write and reads back `0`. [observed on Armada `20261006.9c7dd3e`, kernel 7.2.6, 2026-10-07]
- AYN's own Android "Stop at 80 %" works, through `/sys/class/qcom-battery/limit_capacity_charge`, a node that exists only in the Android kernel and not on Armada [Wayfinder's notes, verified there on a Thor 2026-10-01; checked absent on Armada 2026-10-07]. Armada's kernel patch `0903` exposes the battery manager's *charge current limit* as `constant_charge_current` instead; its commit message says writing `0` stops battery charging while the charger keeps powering the system. [src: Armada `packages/kernel/patches/0903-power-supply-qcom-battmgr-expose-the-charge-current-limit.patch`]
- So Gleipnir clamps that current limit when the Thor is plugged in at 80 % or more and puts it back at 77 % or when you unplug. Whether the firmware honours it is exactly what the test measures.

## What keeps it safe
1. **Watch-only until verified.** The daemon only logs until `gleipnir --test --run` has passed. The pass writes a marker tied to the limit node, the clamp value and the running kernel, so a kernel update disarms it until you test again.
2. **The test proves both directions:** charging stops (or falls under a quarter of the baseline) while clamped, *and* charging resumes after the release. It aborts and restores if the charger is unplugged, the battery passes 45 °C, or the level drops 2 points. It refuses to start outside 10–90 % or without a real charging current to compare against.
3. **Restores on every exit:** stop, `Ctrl-C`, error, and (through the unit's `ExecStopPost`) a crash or `SIGKILL`. A leftover clamp found at start is undone first.
4. **Puts back exactly the value it found.** The firmware changes the limit itself (`9000000` at 73 %, `4680000` at 96 % on the surveyed Thor), so Gleipnir never forces the maximum.
5. **Every write is read back.** Three failures in a row: release, log an error, stop.
6. **Watchdog.** If the battery is still charging at over 200 mA two minutes into a clamp, the limit has no effect: it releases, deletes the marker and exits `78`, which shows as a failed service rather than a silent one.
7. **No flapping.** At most one clamp every two minutes; releases are never delayed.
8. **Logs and monitoring.** Every decision goes to the journal with a full battery snapshot (`journalctl -t gleipnir`), plus a heartbeat every 10 minutes. `gleipnir --status [--json]` reports without touching anything. The Decky panel shows state, battery, the last test and the log.

These are design rules checked against a simulated battery (`tests/run-tests.sh`: obeying, ignoring and tapering batteries, signals, unplugging, aborted tests). They are not a guarantee about real hardware; that is what the on-device test is for. If anything ever goes wrong, restore normal charging with:

```bash
echo 9000000 | sudo tee /sys/class/power_supply/battery/constant_charge_current
```

## Install
From a checkout on your PC (needs SSH key access to the Thor and `sudo` there):

```bash
./scripts/deploy.sh armada@<thor-ip>     # or set THOR_HOST / local/thor.env
```

Then in Game Mode: Steam menu → Decky → **Gleipnir** → *Install daemon* → plug in the charger → *Run test*. After a PASS the daemon arms itself within 30 seconds.

## Files
| Path | What |
|---|---|
| `main.py`, `plugin.json` (`flags: ["root"]`), `dist/index.js` | the Decky plugin: installs, starts, stops and tests the daemon, shows status and log. Root, like Armada's own privileged plugins. |
| `bin/gleipnir` | the daemon, the status report, the safety test and the restore command (one script, so the test and the daemon use the same code) |
| `systemd/gleipnir.service` | the unit (restarts on failure, never on exit 78, runs `--restore` after any stop) |
| `tests/` | `run-tests.sh` (daemon against a fake battery) and `test_backend.py` (plugin backend against a fake runner) |

## Credits
- **Mragank Shekhar ([MgeeeeK](https://github.com/MgeeeeK/thor-armada))**: the original `thor-charge-limit` script this was adapted from (the 80 %/77 % idea and clamping through the current limit). `bin/gleipnir` keeps its GPL-2.0-or-later terms (Armada's `LICENSE.md` covers original Armada scripts); see `LICENSES/GPL-2.0.txt`.
- **[Armada OS](https://armadaos.dev)**: patch `0903` that exposes the current limit.
- **Wayfinder** ([Thor-Wayfinder/thor-wayfinder](https://github.com/Thor-Wayfinder/thor-wayfinder), PolyForm Strict, read only, nothing copied): the note that AYN's Android 80 % limit is a different node.
- **[Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader)** by the SteamDeckHomebrew community.
- Research and tooling around the Thor: [venatrix-ritz/AynThor](https://github.com/venatrix-ritz/AynThor).

## Licence
MIT for the plugin (`LICENSE`); `bin/gleipnir` is GPL-2.0-or-later (SPDX header in the file).
