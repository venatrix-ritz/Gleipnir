# 04 - Error handling, recovery and operating-system constraints

## 1. Failure classes and what the code does

| Class | Detected at | Response | Exit or result | Source |
|---|---|---|---|---|
| No limit node | Start of every mode | Logs an error and exits; the daemon exits 78 so the unit stays failed | 78 (daemon) or 3 | `bin/gleipnir:205-209` |
| Unknown option | Argument loop | Message to stderr | 1 | `:202` |
| Test refused (preconditions) | `--test --run` start | Message to stderr, lists supplies if the status is wrong, writes nothing | 4 | `:280-297`, `:314` |
| Kernel refuses the test write | `node_write` in the test | Removes the marker; the EXIT trap restores | 5 | `:317` |
| Test aborted | Watch loop | Restores, deletes the marker, prints `ABORTED: ...` | 5 | `:322-324`, `:330-331` |
| Test failed | Verdict | Deletes the marker; prints `FAIL. No marker written` | 5 | `:350-351` |
| Write not shown in time | `write_limit` | Logs an error, increments `FAILS` | Continues until `FAILS` reaches 3 | `:139`, `:460-463` |
| Three failed writes in a row | Main loop | Releases; logs; exits 78 | 78 | `:460-463` |
| Watchdog: charging after a clamp | Main loop, 120 s after the clamp, three strikes | Releases; deletes the marker; logs `WATCHDOG`; exits 78 | 78 | `:447-454` |
| Release cannot restore the saved value | `release` | Tries the node maximum; if that fails too, logs `COULD NOT RELEASE` with the manual command | Continues | `:364-375` |
| Restore cannot write | `--restore` | Logs `--restore could NOT restore`; exits 0 | 0 (see below) | `:211-217` |
| Late clamp | Main loop | Writes the maximum back; logs `LATE CLAMP` | Continues | `:421-424` |
| Pre-sleep clamp does not show | `--pre-sleep` | Removes the sleep file; logs; the suspend proceeds unclamped | 0 | `:233-239` |
| Post-sleep cannot release | `--post-sleep` | Logs an error with the manual command | 0 | `:250-251` |
| Daemon stopped or killed | Unit | `ExecStopPost --restore` runs; the exit trap also releases on normal exits and TERM or INT | Next start undoes any leftover clamp | `systemd/gleipnir.service`; `:389-391`, `:395` |
| Charger unplugged | Main loop | Releases | Continues | `:445` |
| Level at or below 77 % | Main loop | Releases | Continues | `:446` |
| Log lookup fails | Backend | Returns `ok: false` with output | | `main.py:243-249` |

Two points about this table:
- `--restore` exits 0 even when it fails. The unit's `ExecStopPost` is written with a leading `-` (ignore failure), so the unit does not see it either. The journal line is the only signal (`bin/gleipnir:214`).
- A daemon that exits 78 is not restarted, because the unit sets `RestartPreventExitStatus=78` (`systemd/gleipnir.service`). The stated purpose is that the failure stays visible in `systemctl status` (`systemd/gleipnir.service` comment, and `bin/gleipnir:39`).

## 2. Retry and hold policy

| Mechanism | Policy | Source |
|---|---|---|
| Write judgement | Wait up to 120 s for the node to show the value; no retry of the write itself | `bin/gleipnir:118-141` |
| Release | Up to three rounds of write-then-hold; each round holds 20 s and a clamp that lands restarts the round | `:142-161` |
| Clamp frequency | At most one clamp per 120 s; releases are never delayed | `:437`, `:473-474`, `safety.md` rule 6 |
| Restart of the unit | `on-failure`, 10 s delay, not after 78 | `systemd/gleipnir.service` |
| Backend start of the test | Refuses a second start while one runs | `main.py:190-192` |

## 3. Recovery procedures

These come from the repo's operator documents. Each is a manual action for the user, not a code path.

| Situation | Procedure | Source |
|---|---|---|
| Thor will not charge, a clamp may be left | Stop the daemon, then write the limit value back. The repo gives `9000000` for Armada's node and the node's `_max` as the alternative | `docs/safety.md` ("Recovery by hand"); `docs/troubleshooting.md` |
| Restore without stopping | `gleipnir --restore` (root) | `docs/cli.md`; `bin/gleipnir:211-217` |
| Panel restore | "Restore normal charging now" button calls `restore_now` | `dist/index.js:173-178`; `main.py:181-186` |
| Watchdog fired | Read the journal; re-run the test before restarting | `docs/troubleshooting.md` (the `exit 78` row) |
| Test ABORTED | Retry when the conditions are stable | `docs/troubleshooting.md` |
| Plugin removed or uninstalled | Uninstall stops the daemon, runs `--restore`, removes the files and marker | `main.py:153-164`; `docs/troubleshooting.md` ("Uninstalling") |
| Stuck "Not charging" with the limit released | Unplug and re-plug the charger; if it persists, `--restore`, stop the daemon, collect the journal | `docs/troubleshooting.md` |

The repo does not give a procedure for power loss while clamped (`docs/safety.md`, "Failure modes": "not tested").

## 4. The `set -uo pipefail` choice
The script uses `set -uo pipefail` and not `set -e` (`bin/gleipnir:40`). Most commands therefore continue after a failure, and each failure is handled where it is checked. Several reads use `2>/dev/null` and a default value (`rd` returns `?`, `num` returns 0, `:82-83`), so a missing node file reads as `?` or `0`. A missing battery reading can therefore look like "not charging" to the code. The main loop's guards (`[ "$on" = 1 ]`, `[ "$cap" -ge ... ]`) work on those defaults (**unverified** whether that can cause a wrong action in practice; the repo does not test a missing file mid-run).

## 5. Operating-system constraints the design relies on

### 5.1 Kernel and the limit node
- The design depends on a writable charge-current attribute under `battery/`. The repo states Armada's kernel patch 0903 provides `constant_charge_current` and the value 0 stops charging (`docs/evidence.md`, [src] entry). The code also accepts the fork's `charge_control_limit`.
- The kernel release string is part of the marker check (`bin/gleipnir:182`). A kernel update disarms the daemon. This is intended (`docs/troubleshooting.md`, "kernel updates disarm Gleipnir by design").
- The firmware changes the value on its own (repo-reported values in `docs/evidence.md`). The restore rule uses the value read at clamp time for this reason (`:378`).
- The node takes time to act (repo-reported, about a minute). Judgement by waiting is the design answer (`:110-113`).

### 5.2 FEX-Emu and `uname -r`
Decky runs under FEX-Emu on the ARM64 Thor, so `uname -r` reports the emulator's kernel `6.11.0` (`CHANGELOG.md`, Unreleased). `host_kernel` queries `hostnamectl` and then `busctl` before `uname -r` (`bin/gleipnir:50-58`). A marker stamped `6.11.0` is adopted (`:178-181`). The adoption is recorded in the daemon's journal and the file is rewritten only by the daemon (`:426-429`). The reason the emulator's kernel reaches the marker is recorded in the CHANGELOG; the exact FEX behaviour is **unverified** beyond that record.

### 5.3 systemd
- **Sleep hooks in `/etc`.** The unit file's comment says systemd-sleep on the surveyed build does not run hooks from `/etc/systemd/system-sleep/`, which is why the design uses a unit ordered `Before=sleep.target` (`systemd/gleipnir-sleep.service`). This is repo-reported (`docs/evidence.md`, 2026-10-08) and not re-checked.
- **Exit 78 and restart.** `RestartPreventExitStatus=78` keeps a failed daemon stopped (`systemd/gleipnir.service`).
- **`ExecStopPost`.** Runs after every stop, including after a crash. The leading `-` makes its failure non-fatal.
- **`StateDirectory=gleipnir`.** systemd creates the state directory. The script also `mkdir -p`s it in the test, the sleep setting and the pre-sleep path (`bin/gleipnir:194`, `:229`, `:292`).
- **Hardening.** `NoNewPrivileges`, `PrivateTmp`, `ProtectHome` and `MemoryMax=32M` are set (`systemd/gleipnir.service`). The repo does not state the reason for each. The daemon's file effects are the limit node under `/sys/class/power_supply` and the state directory `/var/lib/gleipnir`. **Unverified** that the hardening settings do not block any of those paths on the device; the repo has no record of that check beyond the device sessions it describes.
- **Stopping releases.** `systemctl disable --now` triggers the stop path and therefore `--restore` (`main.py:145`).

### 5.4 Suspend
- Armada's native sleep is s2idle, which freezes the daemon (`docs/how-it-works.md`, "Sleep"; repo-reported observation in `docs/evidence.md`).
- Fake sleep keeps services running, so the daemon keeps polling (`bin/gleipnir:168-171`; `dist/index.js:113-119`).
- The sleep unit's ordering (`Before=sleep.target`) is what gives the clamp time to show before the freeze (`systemd/gleipnir-sleep.service`; `bin/gleipnir:219-221`).

### 5.5 Power supply reporting
- `status` reads `Charging` at 0 A while clamped, and also while a game drains the battery (repo-reported, `docs/evidence.md`). The design therefore does not treat `Charging` as proof of charging. The watchdog and the test use the current value as well (`bin/gleipnir:321`, `:325`, `:448-450`).
- `current_now` sign: the repo records positive while charging, negative while discharging (`docs/evidence.md`). The code's watchdog reads the signed value, but the test and the clamp-effect check read the absolute value. See the documentation difference D9 in the application spec.
- The Type-C supply `ucsi-source-psy-pmic_glink.ucsi.01` can report `online=1` while the Thor is unplugged (repo-reported, `docs/evidence.md`, 2026-10-15). The daemon reads only `qcom-battmgr-usb`, so it is not affected by that supply (`bin/gleipnir:45`), and the repo says so.

### 5.6 Shell and tools
The script needs bash, `sed`, `tr`, `head`, `seq`, `date`, `cat`, `sleep` (with a fractional argument: `step_sleep` calls `sleep "1.0"`-style values, `bin/gleipnir:115`), `logger`, `systemctl`, `journalctl`, and optionally `hostnamectl`, `busctl` and `/usr/libexec/armada/device-env`. The repo's tests run on Linux and on Git for Windows (`docs/testing.md`). A `sleep` that rejects fractional arguments would break the settle and hold loops; the repo does not state the coreutils version on the Thor (**unverified**).

### 5.7 Bash signal semantics
- The daemon sets `trap 'exit 0' TERM INT` and `trap cleanup EXIT` (`bin/gleipnir:389-391`). The handler exits, so the `EXIT` trap runs and releases any clamp.
- The test sets `trap restore_test EXIT INT TERM` (`:311`). The handler does not call `exit`. From reading alone, a bash trap that returns does not end the script, so after INT or TERM the test restores the limit and then continues its loop. The repo does not show a run of this case. **Unverified; not run.** See L14 in the application spec.

## 6. Backend error handling (`main.py`)

| Situation | Result | Source |
|---|---|---|
| Command not found | Exit 127 with `<cmd>: not found` | `main.py:35-44` |
| Command timed out | Exit 124 with a timeout message | `:35-44` |
| Status output is not JSON | `error` field set; `daemon` empty | `:93-114`; tested by `tests/test_backend.py:58-63` |
| Status exits non-zero | `error` set to the last output line | `:93-114` |
| Test cannot be spawned | Test state `refused`; the test output file gets the reason; the daemon is restarted if it was active | `:199-209` |
| Cancel while not running | No effect; returns the state | `:226-233` |
| Install or sync file error | `OSError` is caught in `_sync_installed` (`:76-79`); `_install_sync` does not catch it | `:66-83`, `:120-131` |

`_install_sync` does not catch file-copy errors, so an install that fails on copy raises through the RPC (**unverified**: the panel's `act()` catches it and shows a toast, `dist/index.js:71-81`).
