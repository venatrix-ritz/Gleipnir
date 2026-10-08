# Testing

Two kinds of test: the **on-device test** that arms Gleipnir, and the **simulated suites** that check the code.

## The on-device test (arms the daemon)
It answers one question: does writing the clamp value to the limit node really stop charging on this Thor and kernel, and does charging come back when the value is restored?

**Preconditions** (it refuses otherwise, and says why): run as root; charger plugged in and the battery status `Charging`; USB supply online; battery between 10 and 90 %; the Gleipnir service not running (the Decky panel stops it for you); the limit node not already clamped; a baseline charging current of at least 300 mA, so there is something to measure. For best results leave the Thor idle.

**Steps** (about 40 s):
1. Baseline: sample status, current, voltage, temperature for 6 s (every 2 s) and average the charging current.
2. Clamp: write the clamp value, check it reads back.
3. Watch for 20 s. It is **effective** if for 3 samples in a row the status is no longer `Charging` or the current is under a quarter of the baseline. It **aborts and restores** if the charger is unplugged, the temperature reaches 45.0 °C, or the level drops 2 points.
4. Restore the value it found and confirm the node reads above the clamp range.
5. Watch for 10 s. Charging has **resumed** if the status is `Charging` again at at least a quarter of the baseline current.

**PASS** needs effective, resumed and released. It then writes `/var/lib/gleipnir/verified` (node, value, running kernel, time, baseline) and the daemon arms itself on its next poll. **FAIL** or **ABORTED** deletes any marker and leaves Gleipnir watch-only.

Run it from the Decky panel (Gleipnir, Safety test, Run test) or by hand:
```bash
sudo systemctl stop gleipnir          # if it is running
sudo gleipnir --test                  # prints the plan, writes nothing
sudo gleipnir --test --run            # does it
```
The output is also saved to `/var/lib/gleipnir/test-<time>.log` and the journal (`journalctl -t gleipnir`). Re-run it after every kernel update; the marker is tied to the kernel version.

## The simulated suites (check the code)
They use a fake `power_supply` directory and never touch a real battery.
```bash
bash tests/run-tests.sh          # the daemon: about a minute
python tests/test_backend.py     # the Decky backend with a fake command runner
```
`run-tests.sh` includes a battery simulator that either obeys the limit or ignores it. It checks: watch-only without a marker; undoing a leftover clamp; clamping at 80 % and restoring the firmware's own value at 77 %; releasing on unplug; the watchdog (release, marker deleted, exit `78`); a marker for another kernel; `SIGTERM` while clamped; the on-device test passing, failing, refusing (unplugged, too full, already clamped), and aborting when the charger is pulled; `--restore`; `--status --json`; and a kernel with no limit node.

Last recorded results (2026-10-07): 47 of 47 daemon checks and 8 of 8 backend checks pass on the Thor's own Linux userland; on Git for Windows the same suite passed on three of four runs, and the fourth failed only the `SIGTERM`-while-clamped check (unverified guess: that environment's signal emulation does not always deliver the signal to a waiting script; Linux, where Gleipnir runs, passes it). These runs never wrote to the real battery.

## Environment variables
The `GLEIPNIR_*` variables (`PS_BASE`, `STATE_DIR`, `KERNEL`, `POLL_S`, `SETTLE_S`, `MIN_HOLD_S`, `HEARTBEAT_S`, `WAIT_S`, `CLAMP_S`, `BASE_S`, `AFTER_S`, `SAMPLE_S`, `LOG_FILE`, `NO_SYSLOG`, `ALLOW_NONROOT`) exist so the suites can point the script at fake files and shorten the timings. Leave them unset in normal use.
