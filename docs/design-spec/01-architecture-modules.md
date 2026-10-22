# 01 - Architecture and modules

## Runtime parts

| Part | File | Runs as | Role |
|---|---|---|---|
| Daemon, status, test, restore, sleep hooks | `bin/gleipnir` | root (through systemd, or through the backend or a shell) | Everything that touches the limit node |
| systemd service | `systemd/gleipnir.service` | root (no `User=`) | Runs the daemon; runs `--restore` after any stop |
| systemd sleep unit | `systemd/gleipnir-sleep.service` | root | Runs `--pre-sleep` before suspend and `--post-sleep` after resume |
| Decky backend | `main.py` (class `Plugin`) | root (`plugin.json` `flags: ["root"]`) | Installs, starts, stops, tests, reports; calls `bin/gleipnir` and `systemctl` through a no-shell runner |
| Decky panel | `dist/index.js` | the Decky front end (in the Steam UI) | Renders state and calls the backend through the loader |
| Deploy script | `scripts/deploy.sh` | the developer's machine | Copies files over SSH and restarts the Decky loader on the Thor |
| Test suites | `tests/run-tests.sh`, `tests/test_backend.py` | the developer's machine | Exercise the script against a fake power-supply tree, and the backend against a fake runner |

The backend's module docstring states the division of duties: "All it does is install, start, stop and test the `gleipnir` daemon ... the charging logic and its safety rules live in that script. Nothing here writes the battery limit directly" (`main.py:1-10`). Apart from copies of the script and unit files (`main.py:120-131`, `:66-83`) and the test output file `ui-test.out` (`main.py:198`), the backend writes no files itself. Everything else it does goes through `bin/gleipnir` or `systemctl`.

## Who may write the limit node

| Writer | When | Source |
|---|---|---|
| The daemon (`clamp`, `release`, LATE CLAMP correction) | Only while armed (marker valid) | `bin/gleipnir:376-388`, `:364-375`, `:421-424`, `:435-459` |
| The test (`--test --run`) | Only as root, only with the daemon stopped, only with preconditions met | `bin/gleipnir:274-352`, `:288-291` |
| `--restore` (also run by `ExecStopPost`) | Only if the node reads a clamp value | `bin/gleipnir:211-217`; `systemd/gleipnir.service` |
| `--pre-sleep` | Only if armed and the charge is at or above the setting | `bin/gleipnir:222-241` |
| `--post-sleep` | Only when no daemon is running and the node reads a clamp | `bin/gleipnir:242-254` |

Mutual exclusion between the test and the daemon is by a check and a stop, not by a lock file. The test refuses when `gleipnir.service` is active (`bin/gleipnir:288-291`). The backend stops the service before it starts the test and starts it again afterwards (`main.py:194-196`, `:211-221`). The repo does not analyse a race between the check and the stop (**unverified**: the check is not atomic with the stop).

## The daemon script: line map of `bin/gleipnir`

| Lines | Section | Content |
|---|---|---|
| 1-40 | Header | License, provenance (adapted from MgeeeeK's fork), the safety design summary (`:17-30`), the usage list (`:32-38`), exit codes (`:39`) |
| 40-41 | Shell options | `set -uo pipefail`; `LC_ALL=C`. No `-e` |
| 43-79 | Configuration | Paths (`PS`, `B`, `U`, `STATE_DIR`, `MARKER`), kernel (`host_kernel`, `KERNEL`), constants `TARGET`, `RELEASE_AT`, `CLAMP_DETECT`, timings, sleep setting, `DEVICE_ENV`, `DEBUG` |
| 81-96 | Helpers | `rd` (read file or `?`), `num` (integer or 0), `abs`, `log` (journal via `logger`, or stderr and file in tests), `snap` (one-line battery snapshot) |
| 98-106 | Node selection | Chooses `charge_control_limit` first, then `constant_charge_current`; sets `LIM`, `MAX`, `CLAMP_VAL`, `KIND`; `maxv`; `is_clamped` |
| 108-162 | Write and settle primitives | `dlog`, `step_sleep`, `steps_for`, `node_write`, `value_ok`, `wait_for`, `write_limit`, `ensure_released`. The block is marked as the one `tests/run-tests.sh` runs against a late node (`:109`) |
| 164-171 | Sleep setting and mode | `sleep_floor` (saved value or default), `sleep_mode` (reads `ARMADA_SUSPEND_MODE` from the device-env script) |
| 173-187 | Marker check | `marker_ok` sets `MARKER_WHY` and `MARKER_ADOPT`; the FEX `6.11.0` special case |
| 189-197 | `--set-sleep-floor` | Validates 0 to 101, root check, atomic write (`.tmp` then `mv`) |
| 198-204 | Argument loop | Sets `mode`, `run`, `json`, `DEBUG` |
| 205-209 | No-node exit | Exit 78 for the daemon, 3 for other modes |
| 211-217 | `--restore` | Restores only when the node reads a clamp value other than the maximum |
| 222-241 | `--pre-sleep` | Clamp before suspend, with a sleep file written first |
| 242-254 | `--post-sleep` | Removes the sleep file; releases only with no daemon |
| 256-264 | `--status --json` | One-line JSON |
| 265-271 | `--status` | Text report |
| 274-352 | `--test` | Preconditions, baseline, clamp, watch, restore, resume, verdict, marker write |
| 354-358 | Start-up wait | Waits up to `GLEIPNIR_WAIT_S` (30) s for `battery/capacity` and `qcom-battmgr-usb/online` |
| 360-391 | Daemon state and actions | State variables, `release`, `clamp`, `cleanup`, traps |
| 393-395 | Start-up | Logs `started`, undoes a leftover clamp |
| 397-496 | Control loop | One pass per poll: observations, monitoring, adoption, late-clamp correction, marker check, decisions, failure exit, logging, heartbeat, sleep |

## Daemon state
The daemon keeps five pieces of state in shell variables (`bin/gleipnir:361-362`):
- `state`: `released` or `clamped`;
- `saved`: the limit value found before the clamp (empty when unknown);
- `clamped_at`: the `SECONDS` value at the clamp (for the settle and watchdog timers);
- `last_change`: the `SECONDS` value at the last clamp or release (for the minimum hold);
- `bad`: the consecutive watchdog strikes; plus `armed` (last known marker state), `last_beat` and `idle_polls`.

These are lost when the daemon exits. Persistence is limited to the marker, the sleep file, the sleep setting and the journal (`docs/cli.md`, "Files"). On a restart the daemon begins in `released` with `last_change` set so that a clamp is allowed at once (`:361`).

## The Decky backend: `main.py`

One class, `Plugin` (`main.py:60`). Each public method is `async` and runs a synchronous `*_sync` function in a thread (`asyncio.to_thread`). Methods, by group:

| Group | Methods | Lines |
|---|---|---|
| Load | `_main` (Decky's load hook; syncs files), `_sync_installed` | `:85-88`, `:66-83` |
| Status | `get_status`, `_status_sync`, `_installed` | `:116`, `:93-114`, `:90-91` |
| Install and enable | `install`, `_install_sync`, `set_enabled`, `_set_enabled_sync`, `uninstall`, `_uninstall_sync` | `:133`, `:120-131`, `:150`, `:137-148`, `:166`, `:153-164` |
| Sleep setting | `set_sleep_floor`, `_set_sleep_floor_sync` | `:177`, `:169-175` |
| Restore | `restore_now` | `:181-186` |
| Test | `start_test`, `cancel_test`, `get_test` | `:188-224`, `:226-233`, `:235-241` |
| Log | `get_log` | `:243-249` |

Module helpers: `_run` (no shell; returns `(exit, output)`; 127 for a missing command, 124 on timeout, `:35-44`), `_verdict` (maps the output's last verdict line to `pass`, `fail`, `aborted`, `refused` or empty, `:46-57`). Paths are module constants (`:20-32`).

## The Decky panel: `dist/index.js`

- A loader handshake: the file reads the loader's internal init global and connects with API version 2, falling back to 1 (`dist/index.js:2-12`). The global's name is long and says it is internal (`:3`); the repo does not document the loader API.
- RPC wrappers (`:17-26`): one function per backend method, each `call("<name>", ...)`. The names match the backend methods one for one (see [03](03-data-flow-interfaces.md)).
- The component `Content` (`:46-190`) keeps state in React hooks and polls `get_status` every 2 s (`:65-69`). It fetches `get_test` only while a test is running or has finished (`:56-58`). "Show recent log" fetches 15 lines (`:84-91`).
- Pure display helpers: `describeState` (`:32-38`) and `describeBattery` (`:40-44`).
- The panel uses `d.limit <= 1000` to choose the "holding" wording (`:37`).
- `index` (`:192-213`) returns the plugin object with the content, an icon, and an empty `onDismount`.

## Systemd units

| Unit | Type | Key settings | Role |
|---|---|---|---|
| `gleipnir.service` | `simple` | `ExecStart` the daemon; `ExecStopPost=-... --restore`; `Restart=on-failure`; `RestartSec=10`; `RestartPreventExitStatus=78`; `StateDirectory=gleipnir`; `NoNewPrivileges`; `PrivateTmp`; `ProtectHome`; `MemoryMax=32M` | The daemon |
| `gleipnir-sleep.service` | `oneshot`, `RemainAfterExit=yes` | `Before=sleep.target`; `ExecStart=... --pre-sleep`; `ExecStop=-... --post-sleep`; `StopWhenUnneeded=yes`; `WantedBy=sleep.target` | The sleep hooks |

Both units are copied to `/etc/systemd/system/` by the backend (`main.py:25-26`). The sleep unit is enabled by the backend and disabled when the daemon is disabled (`main.py:129-130`, `:144`).

## Build and deploy
`scripts/deploy.sh` checks the script's syntax locally (`bash -n bin/gleipnir`, `scripts/deploy.sh:15`), copies the files to a staging directory on the Thor, moves them into `/home/armada/homebrew/plugins/gleipnir` with root ownership, and restarts `plugin_loader.service` (`:16-27`). The repo has no build step for the script or the panel. `dist/index.js` is the file the loader runs as shipped. The panel is not compiled from a source tree in this repo (**unverified** that no other build exists outside the repo).
