# 03 - Command-line reference

`gleipnir` is one bash script, `bin/gleipnir`. The Decky install copies it to `/var/local/bin/gleipnir` (`main.py:24` `BIN_DST`, `main.py:120-131`). With no arguments it runs as the daemon.

## Parsing rules (from the code)
- Options are read in a loop over all arguments (`bin/gleipnir:198-204`). Each mode flag sets the mode, so **the last mode flag wins** (for example `--status --test` runs the test mode). `--run`, `--json` and `--debug` are modifiers.
- Any unrecognised option prints `unknown option <arg>` to stderr and exits 1 (`:202`).
- `--set-sleep-floor` is handled before the loop (`:190-197`) and takes exactly one number argument.
- The daemon does not check its own UID. `--test --run`, `--set-sleep-floor` and the test's own precondition check require root (`:193`, `:280`), unless `GLEIPNIR_ALLOW_NONROOT=1`.

## Modes

| Invocation | Root needed | Writes the limit node | What it does | Source |
|---|---|---|---|---|
| `gleipnir` | Yes (the unit runs it as root; the script does not check) | Only when armed | The control loop | `:354-497` |
| `gleipnir --status` | No | Never | Text report: node, clamp value, verification state, battery snapshot, last 5 journal lines | `:265-271` |
| `gleipnir --status --json` | No | Never | The same data as one JSON object (fields below); used by the panel | `:256-264` |
| `gleipnir --test` | No | Never | Prints the test plan and exits 0 | `:274-279` |
| `gleipnir --test --run` | Yes | During the test only | Runs the supervised test and writes the marker on PASS | `:280-351` |
| `gleipnir --restore` | Not checked; writes need root | Only if a clamp is found | Undoes a leftover clamp (the unit runs this after every stop) | `:211-217` |
| `gleipnir --set-sleep-floor N` | Yes (or `GLEIPNIR_ALLOW_NONROOT=1`) | Never (writes the setting file) | Sets the sleep setting: 0 clamp before every native sleep, 70 clamp from 70 % up, 101 never | `:190-197` |
| `gleipnir --pre-sleep` | Not checked | Only if armed and at or above the setting | Run by `gleipnir-sleep.service` before suspend | `:222-241` |
| `gleipnir --post-sleep` | Not checked | Only if no daemon is running | Run after resume; removes the sleep file, and releases the clamp only if no daemon runs | `:242-254` |
| `gleipnir --debug` (modifier, any mode) | - | - | Turns on the debug log lines (`DEBUG=1`) | `:201`, `:114` |

`--debug` is parsed by the script but is not in the usage comment at the top (`bin/gleipnir:32-38`) or in `docs/cli.md`. See `06-limitations-glossary.md`.

### The safety test, step by step (with `--test --run`)
The full procedure is in [05-testing.md](05-testing.md). The outcomes that set the exit code are:

| Outcome | Output | Exit | Source |
|---|---|---|---|
| Not root | `Run as root: sudo ... --test --run` | 4 | `:280` |
| Status not `Charging`, or charger offline | `Refusing: status is ...` plus the supplies list | 4 | `:282-286` |
| Battery outside 10 to 90 % | `Refusing: battery is at NN%` | 4 | `:287` |
| `gleipnir.service` running | `Refusing: gleipnir.service is running ...` | 4 | `:288-291` |
| Limit already reads a clamp value | `Refusing: the limit already reads ...` | 4 | `:297` |
| Baseline charging current under 300 mA | `Refusing: charging current is only ...` | 4 | `:314` |
| Node write refused by the kernel | `FAIL: the kernel refused the write.` | 5 | `:317` |
| Charger unplugged, battery 45 °C or more, or level down 2 points | `ABORTED: ...` (limit restored) | 5 | `:322-324`, `:330` |
| Effect or resume not seen, or released check fails | `FAIL. No marker written ...` | 5 | `:350-351` |
| PASS: effective, resumed and released | `PASS. Marker written: ...` | 0 | `:344-348` |

## Exit codes

| Code | Meaning | Source |
|---|---|---|
| 0 | Clean exit; plan printed; test PASS; `--restore` finished; status | Various |
| 1 | Unknown option, or bad `--set-sleep-floor` argument | `:41-202`, `:191-192` |
| 3 | No usable limit node (for modes other than the daemon, including `--pre-sleep` and `--post-sleep`) | `:205-208` |
| 4 | Test preconditions not met, or not root for a write mode (nothing written) | `:193`, `:280`, `:282-297`, `:314` |
| 5 | Test failed or aborted (the limit was restored), or the kernel refused the write | `:317`, `:330-331`, `:351` |
| 78 | Daemon only: no usable node, three failed writes in a row, or the watchdog found the limit ineffective. The unit does not restart on 78 | `:208`, `:460-463`, `:453` |

Two behaviours to note from the code:
- `--restore` exits 0 even when the restore fails. It logs `--restore could NOT restore` at error level instead (`bin/gleipnir:214`). Check the journal, not the exit code.
- A daemon exit that is not 78 (for example a signal) follows the `EXIT` trap, which releases any clamp (`:389-391`).

## `--status --json` fields
Printed on one line (`bin/gleipnir:258-262`). Values that are not numbers are passed through as strings where the script quotes them.

| Field | Meaning | Source |
|---|---|---|
| `node` | The limit node path (or the empty string if none) | `:260` |
| `kind` | `fork charge_control_limit` or `Armada constant_charge_current` | `:101`, `:103` |
| `clamp_value` | The value written to clamp (1000 or 0) | `:101`, `:103` |
| `node_max` | The node's maximum (the fallback restore value) | `:105` |
| `verified` | `true` when the marker matches node, clamp value and kernel | `:257` |
| `verified_why` | Why the marker does not match (empty when verified) | `:183`, `:257` |
| `kernel` | Host kernel release (hostnamectl, busctl, or `uname -r`) | `:60`, `:50-58` |
| `capacity` | Battery charge, percent | `:261` |
| `status` | Kernel status string (`Charging`, `Discharging`, `Not charging`, ...) | `:261` |
| `usb_online` | Charger online, 0 or 1 | `:261` |
| `current_ua` | `current_now` in µA, signed (positive while charging per the code's comment) | `:261`, `:448` |
| `voltage_uv` | `voltage_now` in µV | `:262` |
| `temp_dc` | Temperature in tenths of a degree C | `:262` |
| `health` | Battery health string | `:262` |
| `limit` | The current value of the limit node | `:262` |
| `sleep_floor` | The sleep setting read by `sleep_floor()` (`0`, `70`, `101`, or the default) | `:259`, `:164-167` |
| `sleep_mode` | Armada's suspend mode (`s2idle`, `fake`, or `unknown`) | `:259`, `:168-171` |

`docs/cli.md` lists the first 15 fields and does not list `sleep_floor` or `sleep_mode`. The code emits both.

## Text status output
`gleipnir --status` prints, in order: `node:` (path and kind), `clamp:` (the clamp value and the node maximum), `verified:` (yes with the marker contents, or NO with the reason), `battery:` (the snapshot), and `journal:` (the last 5 journal lines, when `journalctl` exists) (`bin/gleipnir:266-270`).

## Files and names

| Path or name | Written by | What it is | Source |
|---|---|---|---|
| `/var/lib/gleipnir/verified` | `--test --run` on PASS; deleted on FAIL, ABORTED, the watchdog, and when the test is aborted | The verification marker: `node=`, `value=`, `kernel=`, `verified_at=`, `baseline_uA=` | `:345`, `:350`, `:453`, `:330` |
| `/var/lib/gleipnir/sleep-floor` | `--set-sleep-floor` | The sleep setting, a number from 0 to 101 | `:194`, `:46-47`, `:73` |
| `/var/lib/gleipnir/sleep-clamp` | `--pre-sleep`, before it writes the clamp | Two lines, `saved=` (the value found) and `at=` (epoch seconds). The daemon adopts the clamp and holds it while the file exists | `:76`, `:230-232`, `:413-418` |
| `/var/lib/gleipnir/test-<YYYYmmdd-HHMMSS>.log` | `--test --run` (through `tee`) | Full test output | `:293-294` |
| `/var/lib/gleipnir/ui-test.out` | The Decky backend | The test's stdout and stderr for the panel | `main.py:30`, `:198-207` |
| `/var/lib/gleipnir/.avg` | The test | A scratch value for the baseline average | `:300` |
| Journal, tag `gleipnir` | Every mode through `logger` | All daemon and test log lines, at `daemon.<level>` | `:85-91` |
| `/var/local/bin/gleipnir` | Decky install or deploy | The installed script | `main.py:120-131` |

The `StateDirectory=gleipnir` line in the unit makes systemd create `/var/lib/gleipnir` (`systemd/gleipnir.service`).
