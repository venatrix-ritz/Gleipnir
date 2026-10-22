# 06 - Limitations, open questions, documentation differences, glossary

## 1. Limitations

Each item says where the limit comes from. "Repo-reported" means a repo document states it and it was not re-observed for this spec.

| # | Limitation | Source |
|---|---|---|
| L1 | Only one Thor, one Armada build (`20261006.9c7dd3e`) and one kernel (7.2.6) are recorded as tested. Other builds are untested. | `README.md` (status line); `docs/evidence.md` |
| L2 | Gleipnir does nothing to charging until the on-device test passes on that kernel. A kernel update disarms it until the test is run again. | `docs/how-it-works.md` ("The idea"); `bin/gleipnir:425-433`; `docs/troubleshooting.md` |
| L3 | A PASS measures two things: charging stops while clamped and resumes after restore. It does not measure the supply path while clamped, or whether the value survives a reboot. | `docs/evidence.md` ("What follows"); `docs/safety.md` ("What is not guaranteed") |
| L4 | The node is slow. A write may take about a minute to act (repo-reported). The daemon waits up to 120 s for a write to show (`bin/gleipnir:70`, `:118-141`). | `docs/evidence.md` (2026-10-08 first run) |
| L5 | An open stuck state. Repo-reported: after a clamp was held about 90 s at 80 % and then released, `status` stayed `Not charging` for more than ten minutes. The cause is not established. Whether charging resumes by itself below 77 % is untested. The daemon logs a warning for this case (`bin/gleipnir:401-411`). | `docs/evidence.md` (2026-10-08 observation); `docs/troubleshooting.md` |
| L6 | Reboot or power loss while clamped is untested. Whether the firmware keeps the value across a reboot is unknown. | `docs/safety.md` ("Failure modes", "Recovery by hand") |
| L7 | If the Thor does not charge after a clamp, the recovery is manual (`sudo systemctl stop gleipnir`, then write the value back). | `docs/safety.md` ("Recovery by hand") |
| L8 | Sleep clamping works only for a native sleep (`s2idle`). In fake sleep the daemon keeps running and the sleep setting is not used. | `bin/gleipnir:168-171`; `dist/index.js:113-119`; `docs/how-it-works.md` ("Sleep") |
| L9 | With sleep setting 70 the Thor charges while asleep below 70 %, and can pass the cap. With 101 it never clamps for sleep. | `docs/cli.md`; `bin/gleipnir:164-167`; `dist/index.js:124-128` |
| L10 | The daemon polls every 30 s (`bin/gleipnir:64`), so a charger unplug is seen within about 30 s (`docs/safety.md`). | `bin/gleipnir:64`, `:445` |
| L11 | The watchdog uses the signed `current_now` and counts only positive values as charging (`bin/gleipnir:448-450`). The repo's troubleshooting page says Gleipnir uses the absolute value (see D9). An earlier build read the size as charging and tripped the watchdog falsely; the repo records that as fixed (`CHANGELOG.md`, Unreleased). | `bin/gleipnir:448-450`; `docs/evidence.md` (2026-10-08 sign note) |
| L12 | When the value found before a clamp is unknown (empty `saved`), a release restores the node maximum, which is hard-coded as 9000000 if `_max` is missing. The firmware's own value at other charge levels differs (4680000 at 96 % in the repo's observations). Effect on the battery: **unverified**. | `bin/gleipnir:105`, `:366`, `:369-370`; `docs/evidence.md` |
| L13 | A non-zero exit from `--restore` does not happen when the restore fails. The script exits 0 and logs an error. | `bin/gleipnir:211-217` |
| L14 | The test's cancel path sends SIGINT to the test process (`main.py:226-233`, `cancel_test`). The test traps INT and TERM with `restore_test` but no `exit` in the handler (`bin/gleipnir:311`). From reading alone, bash continues the script after a trap handler that does not exit, so a cancel may restore the limit without ending the test loop. **Unverified: not run.** | `main.py` (`cancel_test`); `bin/gleipnir:311` |
| L15 | The panel's "Armed" wording is chosen when the reported limit is 1000 or less. That is an inference from the value, not a read of the state (`dist/index.js:37`). | `dist/index.js:37` |
| L16 | On Decky load, when the installed files differ from the plugin copy, the backend copies them and restarts the daemon if it is active. Whether that restart releases and re-clamps a battery in the middle of a clamp is **unverified** (it follows from the unit's `ExecStopPost` and the daemon's start path). | `main.py:66-83`; `systemd/gleipnir.service` |
| L17 | The simulated suites shorten timings through `GLEIPNIR_*` variables and use fake sysfs trees. They do not exercise systemd, the Decky panel, or the real firmware. | `docs/testing.md`; `tests/run-tests.sh:22-31`; `tests/test_backend.py:16-28` |
| L18 | No test file covers `dist/index.js`. | `tests/` (two files) |
| L19 | The watchdog and the release rules depend on the 77 % point. Under a heavy load on a weak charger the battery can drain to 77 % and the release then runs. The repo records one such case (`docs/evidence.md`, 2026-10-08 field run, weaker charger). | `docs/safety.md` ("Failure modes"); `docs/evidence.md` |

## 2. Open questions
Taken from `docs/evidence.md` ("Open questions") and the untested items above:
1. Does a clamp of `0` behave differently from a small non-zero value on this firmware?
2. Does the firmware reset the value itself at plug and unplug events?
3. Which power supply reports `online` while charging over USB-C PD? Gleipnir reads `qcom-battmgr-usb`. `docs/evidence.md` says that if it never reads 1, the daemon will never clamp and the test will refuse.
4. Why did charging not resume after a long clamp at 80 % (L5)?

## 3. Documentation and code differences
These were found while reading the repo. The code is the reference for this spec. None of them was fixed.

| # | Where | What the document says | What the code does |
|---|---|---|---|
| D1 | `docs/cli.md`, `--status --json` fields | Lists 15 fields | Emits 17: also `sleep_floor` and `sleep_mode` (`bin/gleipnir:259`) |
| D2 | `docs/cli.md`, mode table; `bin/gleipnir:32-38` usage comment | No `--debug` flag | Parses `--debug` (`bin/gleipnir:201`) |
| D3 | `docs/cli.md`, exit codes | Exit 3 for "status, test and restore modes" | Exit 3 also for `--pre-sleep` and `--post-sleep` when no node exists (`bin/gleipnir:205-208`) |
| D4 | `docs/testing.md`, environment variables | Lists the test-suite variables | Omits `GLEIPNIR_DEBUG`, `GLEIPNIR_SLEEP_CLAMP_FROM`, `GLEIPNIR_SLEEP_APPLY_WAIT_S`, `GLEIPNIR_SYSTEMCTL`, `GLEIPNIR_DEVICE_ENV` (`bin/gleipnir:74-79`, `:75`) |
| D5 | `docs/testing.md`, `CHANGELOG.md` | Backend suite is "8 of 8" or "8 checks" | `tests/test_backend.py` has nine `test_*` functions. The totals in the daemon suite (47 to 102) are also not reproducible by reading (see 05-testing.md) |
| D6 | `tests/run-tests.sh:4-5` header | Mode is set by a `SIM=` environment variable | `sim_start` takes the mode as its first argument (`tests/run-tests.sh:33`) |
| D7 | `docs/how-it-works.md`, "Thresholds" | The thresholds are constants at the top of the script | `SETTLE_S`, `MIN_HOLD_S`, `HEARTBEAT_S` and `POLL_S` are overridable through environment variables (`bin/gleipnir:64-67`). The 80, 77, 200 mA and 3-strike values are fixed |
| D8 | `package.json` `description` | Not described in the docs | `Gleipnir (Debug)` and version `0.2.1-debug`. `CHANGELOG.md` says the debug logging is opt-in and off by default, which matches `bin/gleipnir:79` |
| D9 | `docs/troubleshooting.md`, "Reading a log line" | "Gleipnir uses the absolute value" of `current` | The watchdog uses the signed value (`bin/gleipnir:450`). The test's abort and effect checks use the absolute value (`:321`, `:325`, `:335`) |

## 4. Glossary

| Term | Meaning | Where defined |
|---|---|---|
| **Armada** | The Linux distribution the Thor runs (`armadaos.dev`, per `CREDITS.md`) | `README.md` |
| **Armed** | The daemon may write a clamp because a valid marker exists | `bin/gleipnir:425-433` |
| **Bypass charging** | The term in Armada's kernel patch comment for a state in which the charger runs the system and the battery does not charge (repo-reported; `docs/evidence.md`) | `docs/evidence.md` |
| **Clamp** | Writing the clamp value (0 or 1000) to the limit node so the firmware stops charging | `bin/gleipnir:376-388` |
| **Clamp value** | The value written to clamp: 0 on `constant_charge_current`, 1000 on `charge_control_limit` | `bin/gleipnir:101`, `:103` |
| **Constant charge current node** | Armada's `constant_charge_current` attribute and its `_max` | `bin/gleipnir:102-103` |
| **Daemon** | The `gleipnir` process run by `gleipnir.service` (no argument mode) | `bin/gleipnir:354-497` |
| **Decky** | Decky Loader, the plugin loader under which the panel runs (the repo links its project page) | `README.md`; `CREDITS.md` |
| **Fake sleep** | An Armada sleep type in which system services keep running | `bin/gleipnir:168-171`; `dist/index.js:115` |
| **FEX-Emu** | The x86_64 emulator under which Decky runs on the ARM64 Thor. The repo says `uname -r` then reports the emulator's kernel `6.11.0` | `CHANGELOG.md`, Unreleased |
| **Hold window** | The 20 s a restored value must stay released before the restore counts | `bin/gleipnir:71`, `:142-161` |
| **LATE CLAMP** | A clamp the daemon did not make, found in the node. The daemon writes the maximum back | `bin/gleipnir:421-424` |
| **Limit node** | The sysfs attribute that sets the charge-current limit | `bin/gleipnir:99-104` || **Marker** | The verification file `/var/lib/gleipnir/verified` written on PASS | `bin/gleipnir:345` |
| **Monitor-only** | The state of a daemon without a valid marker: it logs and never writes a clamp | `bin/gleipnir:466-467` |
| **Node maximum** | The `_max` attribute, the fallback restore value | `bin/gleipnir:105` |
| **Pre-sleep, post-sleep** | The two modes run by `gleipnir-sleep.service` around a suspend | `bin/gleipnir:222-254` |
| **Release** | Writing the restored value back to the limit node | `bin/gleipnir:364-375` |
| **s2idle** | The native suspend mode that freezes user-space processes, including the daemon (repo-reported; `docs/how-it-works.md`) | `docs/how-it-works.md` ("Sleep") |
| **Settle** | The 120 s after a clamp before the watchdog may trip (`SETTLE_S`) | `bin/gleipnir:65`, `:447` |
| **Sleep floor / sleep setting** | The saved 0, 70 or 101 that decides whether a pre-sleep clamp is written | `bin/gleipnir:73-74`, `:164-167` |
| **Thor** | The AYN Thor handheld that Gleipnir targets | `README.md` |
| **Verified** | The state after a PASS for this node, value and kernel | `bin/gleipnir:425-427` |
| **Watchdog** | The check that releases and exits 78 if charging continues at 200 mA or more after a clamp | `bin/gleipnir:447-454` |
| **Watch-only** | The user-facing name for monitor-only (`dist/index.js:36`) | `dist/index.js:36` |
