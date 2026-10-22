# 05 - Testing and verification

Two kinds of test exist in the repo. The **on-device safety test** decides whether Gleipnir may ever write a clamp on a given Thor and kernel. The **simulated suites** check the code against a fake power-supply tree. This spec describes both from the code. It does not record a new run of either: no test was run for this spec.

## 1. The on-device safety test

It is the only path that writes a marker. The steps below are from `bin/gleipnir:274-352`.

### Preconditions (refused, nothing written)

| Check | Requirement | Source |
|---|---|---|
| Root | UID 0, unless `GLEIPNIR_ALLOW_NONROOT=1` | `:280` |
| Charging | Battery `status` is exactly `Charging` and `qcom-battmgr-usb/online` is 1 | `:282-286` |
| Level | Capacity between 10 and 90 % inclusive | `:287` |
| Daemon | `gleipnir.service` is not active | `:288-291` |
| Limit | The node does not already read a clamp value | `:297` |
| Baseline | Average charging current over the baseline window is at least 300 000 µA | `:314` |

The panel stops the daemon before it starts the test and restarts it afterwards if it was running (`main.py:194-196` for the stop; `main.py:211-221`, `_finish`, for the restart).

### Steps

| Step | What happens | Source |
|---|---|---|
| 1. Baseline | Samples `status`, `current_now`, `voltage_now`, `temp` and `capacity` every 2 s for 6 s (three samples at 0, 2 and 4 s with the defaults). The average of the absolute current is the baseline | `:300`, `:313` |
| 2. Clamp | Writes the clamp value (0 on Armada's node, 1000 on the fork node). It does **not** read back at once | `:315-317` |
| 3. Watch | Up to `GLEIPNIR_CLAMP_S` (180 s), sampling every 2 s. Aborts if the charger is unplugged, the battery reaches 45.0 °C (450 tenths), or the level falls 2 points below the starting level. Counts "effective" when, on three samples in a row, the status is not `Charging` or the absolute current is under a quarter of the baseline. Stops early on effective | `:318-328` |
| 4. Restore | Writes back the value found and holds it for `HOLD_S` (20 s). If a clamp lands during the hold, it writes the value again, up to three rounds. Falls back to the node maximum if the saved value does not hold | `:329`, `:302-310`, `:142-161` |
| 5. Resume | Up to `GLEIPNIR_AFTER_S` (120 s). "Resumed" when status is `Charging` and the absolute current is at least a quarter of the baseline on two samples in a row. Stops waiting if the charger is unplugged | `:331-340` |
| 6. Verdict | PASS when effective, resumed, and the node reads released at the end. PASS writes the marker with `node=`, `value=`, `kernel=`, `verified_at=` (ISO time) and `baseline_uA=`. Anything else deletes the marker | `:341-351` |

If the kernel refuses the write outright, the test exits 5 with `FAIL: the kernel refused the write.` and removes the marker (`:317`).

### What PASS means and what it does not
- PASS means that, on this run, the node write was followed by a fall in charging (or a status change), and that charging came back after restore. The repo states it "measures charging stop and charging resume; it does not measure the supply path" (`docs/evidence.md`, "What follows"). Those are the code's two checks (`:325-326`, `:336-337`).
- The marker is bound to node path, clamp value and kernel (`bin/gleipnir:182`). A kernel update disarms the daemon until the test is run again (`docs/troubleshooting.md`).

### Recorded results (repo-reported)
- The repo records a first run on 2026-10-08 that wrote the clamp, judged it refused from an instant readback, and left the Thor clamped until a manual restore. The fix is described in the entries under "Unreleased" in `CHANGELOG.md` and in `docs/evidence.md`. That run is not reproduced here.
- A later run on 2026-10-08 passed, and the repo records a field session on the same day. These come from `docs/evidence.md` and are not re-observed for this spec.

## 2. The simulated suites (no device, no root, no battery)

### `tests/run-tests.sh` (the daemon)
A bash suite that builds a fake power-supply tree in a temp directory and runs `bin/gleipnir` against it. A background simulator (`sim_start`, `tests/run-tests.sh:33-45`) either obeys the limit (status `Not charging`, current 0 when the node is at or below 1000), ignores it (`ineffective`), or obeys it late (`late`, with a lag argument). The header comment says the mode comes from a `SIM=` environment variable, but the code passes it as the first argument of `sim_start` (`:4-5` against `:33`). That header is out of date.

The sections (from the `echo "S..."` headers in the file):

| Section | What it checks |
|---|---|
| S1 | Unverified: monitor-only, limit untouched |
| S2 | A leftover clamp is undone even when unverified |
| S3 | Verified: clamp at 80 %, released to the firmware value at 77 % |
| S4 | Unplug releases |
| S5, S5b | Watchdog releases, deletes the marker, exits 78; a discharge with status `Charging` does not trip it |
| S6, S6b | A marker for another kernel disarms; the FEX-stamped `6.11.0` marker is adopted |
| S7 | SIGTERM while clamped restores |
| S8, S9, S10, S11 | The test: PASS on a working limit, FAIL on an ignored one, refusals, abort and restore when the charger is pulled |
| S12, S13 | `--restore`, `--status`; a missing node |
| S14, S15, S16, S17 | A late-acting node: PASS when the effect arrives within the wait; FAIL and a restore when it does not; a late clamp is undone; the settle logic against a node that drops writes |
| S18 | Monitoring warning for a released limit, charger attached, low battery, not charging; not logged in the 77 to 80 % band |
| S19, S19b, S20, S20b, S20c, S20d | Pre-sleep: clamps when armed and at or above the setting, also on battery; below the setting does nothing; the default clamps every sleep; a saved setting wins; `--set-sleep-floor` validates input |
| S21, S22, S22b, S22c | Pre-sleep when not armed does nothing; the daemon adopts a pre-sleep clamp and holds it through the sleep |
| S23 | Post-sleep with no daemon releases; with a daemon it leaves the clamp |
| S24 | The FEX-stamped marker is judged adopted by `--status` and `--pre-sleep`; only the daemon rewrites it |
| S25 | Poll lines appear only with debug on |

Static counts in the file (not run): 65 `eq` call sites, 28 `has` call sites and 11 direct `ok` calls. `docs/testing.md` and `CHANGELOG.md` give totals of 47, 61, 67, 86, 97 and 102 at different points in time, with the last at "102 pass" under Unreleased. Those totals cannot be confirmed by reading the file. **Unverified.**

Two things about the suite affect its meaning:
- `has` waits up to 3 seconds for a log line (`tests/run-tests.sh:13-15`), so it does not catch timing bugs longer than that.
- Some sections use real `sleep` and background processes (`tests/run-tests.sh:33-46`). `docs/testing.md` says the suite takes about a minute and that the signal check (S7) failed once on Git for Windows and passed on Linux. That failure is recorded as an unverified guess in `docs/testing.md`.

### `tests/test_backend.py` (the Decky backend)
A plain Python script with `test_*` functions, run by its own `__main__` loop (`tests/test_backend.py:144-147`; run with `python tests/test_backend.py`). It does not use the `unittest` module. It replaces `main._run` with a fake command runner and uses temp paths. It has **nine** test functions:

| Function | Covers |
|---|---|
| `test_install_then_status` | Install copies the files, enables the daemon and the sleep unit, reports status |
| `test_status_survives_bad_json` | A non-JSON status does not crash; the error is returned |
| `test_disable_restores_and_stops` | Disable stops the sleep unit and the daemon, then runs `--restore` |
| `test_uninstall_removes_files_and_marker` | Uninstall removes the files and the marker |
| `test_log_lines_are_clamped` | `get_log` clamps the line count to 1 to 200 |
| `test_verdicts` | The verdict words from the test output |
| `test_test_run_stops_and_restarts_daemon` | A test run stops and restarts the daemon, and a second start is refused |
| `test_failed_test_start_puts_the_daemon_back` | If the test cannot start, the daemon is restarted |
| `test_main_syncs_upgraded_files` | A changed script or unit on load is copied and the daemon restarted |

`docs/testing.md` and `CHANGELOG.md` describe "8 of 8" or "8 checks" for this suite. The file has nine test functions. Which count is right for the suite as it stands is **unverified**; the difference may come from counting assertions instead of functions.

These tests fake `systemctl` and `journalctl` through `_run`, so they do not exercise systemd. The panel (`dist/index.js`) has no test file in the repo (`tests/` lists two files only).

## 3. Verification checklist for a reader of this spec
1. Read the marker: `cat /var/lib/gleipnir/verified` (on the Thor). A marker must match the node and the kernel (`docs/troubleshooting.md`).
2. Read the status without changing anything: `gleipnir --status --json` (`bin/gleipnir:256-264`).
3. Read the test output file: `/var/lib/gleipnir/test-*.log` (`bin/gleipnir:293`).
4. Read the journal: `journalctl -t gleipnir -n 40 --no-pager` (`docs/troubleshooting.md`).

Running the test, the simulated suites, or any of these commands on a device is outside this spec's scope and was not done for it.
