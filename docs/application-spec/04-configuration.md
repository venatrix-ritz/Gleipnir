# 04 - Configuration

Gleipnir has no configuration file. Its behaviour comes from three places: constants at the top of `bin/gleipnir`, `GLEIPNIR_*` environment variables read by the same script, and two saved state files. The systemd units set no environment variables (`systemd/gleipnir.service`, `systemd/gleipnir-sleep.service`), so on a real install the environment defaults apply. This matches `docs/safety.md`, "Security".

## Constants that are not overridable

| Name | Value | Meaning | Source |
|---|---|---|---|
| `TARGET` | 80 | Clamp when charge reaches this, plugged in | `bin/gleipnir:61` |
| `RELEASE_AT` | 77 | Release at or below this | `:62` |
| `CLAMP_DETECT` | 1000 | A limit at or below this value is treated as a clamp | `:63` |
| `WATCH_UA` | 200000 | Watchdog threshold, µA of positive current | `:68` |
| `BAD_LIMIT` | 3 | Watchdog strikes before it gives up | `:69` |
| Fallback maximum | 9000000 | Used when the node's `_max` reads as 1000 or less | `:105` |

The docs say these are "constants at the top" (`docs/how-it-works.md`, "Thresholds"). `SETTLE_S`, `MIN_HOLD_S` and `HEARTBEAT_S` are also in that block but read an environment variable first (see below).

## Environment variables

Defaults are the values after `:-` in the script. Set by a test suite or by hand only. The unit does not set them.

| Variable | Default | Effect | Source |
|---|---|---|---|
| `GLEIPNIR_PS_BASE` | `/sys/class/power_supply` | Root of the power-supply tree (tests point it at a fake tree) | `:43` |
| `GLEIPNIR_STATE_DIR` | `/var/lib/gleipnir` | State directory (marker, sleep files, test logs) | `:46` |
| `GLEIPNIR_KERNEL` | the host kernel (`hostnamectl`, then `busctl`, then `uname -r`) | Kernel string for the marker check | `:60`, `:50-58` |
| `GLEIPNIR_POLL_S` | 30 | Daemon poll interval, seconds | `:64` |
| `GLEIPNIR_SETTLE_S` | 120 | Seconds after a clamp before the watchdog runs | `:65` |
| `GLEIPNIR_MIN_HOLD_S` | 120 | Minimum seconds between a clamp and the next clamp | `:66` |
| `GLEIPNIR_HEARTBEAT_S` | 600 | Heartbeat interval, seconds | `:67` |
| `GLEIPNIR_APPLY_WAIT_S` | 120 | How long a write may take to show in the node | `:70` |
| `GLEIPNIR_HOLD_S` | 20 | Seconds a restored value must stay released before it counts | `:71` |
| `GLEIPNIR_WAIT_STEP_DS` | 10 | Poll step while waiting, tenths of a second | `:72` |
| `GLEIPNIR_SLEEP_CLAMP_FROM` | 0 | Default sleep setting when no saved setting exists | `:74` |
| `GLEIPNIR_SLEEP_APPLY_WAIT_S` | 10 | Maximum wait for the clamp at pre-sleep | `:75` |
| `GLEIPNIR_SYSTEMCTL` | `systemctl` | The systemctl command used by `--post-sleep` | `:77` |
| `GLEIPNIR_DEVICE_ENV` | `/usr/libexec/armada/device-env` | The Armada device-environment script read for the suspend mode | `:78` |
| `GLEIPNIR_DEBUG` | 0 | Debug log lines (same as `--debug`) | `:79` |
| `GLEIPNIR_WAIT_S` | 30 | Seconds the daemon waits at start for `battery/capacity` and `usb/online` | `:355` |
| `GLEIPNIR_CLAMP_S` | 180 | Test: how long to wait for charging to stop | `:275` |
| `GLEIPNIR_BASE_S` | 6 | Test: baseline sampling time | `:275` |
| `GLEIPNIR_AFTER_S` | 120 | Test: how long to wait for charging to resume | `:275` |
| `GLEIPNIR_SAMPLE_S` | 2 | Test: sample interval | `:275` |
| `GLEIPNIR_NO_SYSLOG` | unset | When set, log lines go to stderr instead of the journal | `:87` |
| `GLEIPNIR_LOG_FILE` | unset | When set, log lines are also appended to this file | `:89` |
| `GLEIPNIR_ALLOW_NONROOT` | unset | When `1`, skips the root check for `--test --run` and `--set-sleep-floor` | `:193`, `:280` |

The `GLEIPNIR_*` names that the test suite uses are listed in `docs/testing.md`. `GLEIPNIR_DEBUG`, `GLEIPNIR_SLEEP_CLAMP_FROM`, `GLEIPNIR_SLEEP_APPLY_WAIT_S`, `GLEIPNIR_SYSTEMCTL` and `GLEIPNIR_DEVICE_ENV` are not in that list.

`main.py` reads no environment variables (`grep` of the file found none).

## Saved state

| File | Format | Default when absent | Source |
|---|---|---|---|
| `<STATE_DIR>/verified` | Lines `node=`, `value=`, `kernel=`, `verified_at=`, `baseline_uA=` | Not verified (monitor-only) | `:47`, `:175-187`, `:345` |
| `<STATE_DIR>/sleep-floor` | One number, 0 to 101; a value outside 0 to 101 or not a number is ignored | `GLEIPNIR_SLEEP_CLAMP_FROM` (default 0) | `:73`, `:164-167` |
| `<STATE_DIR>/sleep-clamp` | Lines `saved=` and `at=` (epoch seconds) | None (no sleep hold) | `:76`, `:230-232` |

The marker is valid only when its node path, its value and its kernel all match the running system. The kernel `6.11.0` is treated specially under FEX-Emu (see [03-cli.md](03-cli.md) and the design spec, file 04).

## Systemd units

### `systemd/gleipnir.service`
| Setting | Value | Meaning |
|---|---|---|
| `Description` | Thor 80% battery charge ceiling (monitor-only until verified) | |
| `After` / `WantedBy` | `multi-user.target` | Starts at boot once enabled |
| `ExecStart` | `/var/local/bin/gleipnir` | The daemon |
| `ExecStopPost` | `-/var/local/bin/gleipnir --restore` | The leading `-` means a failure here is ignored. It runs after every stop |
| `Restart` / `RestartSec` | `on-failure` / 10 | Restarts after a failure |
| `RestartPreventExitStatus` | 78 | Exit 78 stays failed |
| `StateDirectory` | `gleipnir` | systemd creates `/var/lib/gleipnir` |
| `NoNewPrivileges`, `PrivateTmp`, `ProtectHome` | yes | Hardening |
| `MemoryMax` | 32M | Memory cap |

No `User=` is set, so systemd's default applies (the unit runs as root). This is the basis of the "runs as root" statement in `docs/safety.md`, "Security".

### `systemd/gleipnir-sleep.service`
| Setting | Value | Meaning |
|---|---|---|
| `Before` | `sleep.target` | Runs before the sleep target is reached |
| `StopWhenUnneeded` | yes | |
| `Type` / `RemainAfterExit` | `oneshot` / yes | |
| `ExecStart` | `/var/local/bin/gleipnir --pre-sleep` | Clamp before suspend if the setting allows |
| `ExecStop` | `-/var/local/bin/gleipnir --post-sleep` | Release after resume (the design relies on this running on wake; see the design spec) |
| `TimeoutStartSec` / `TimeoutStopSec` | 30 / 60 | |
| `WantedBy` | `sleep.target` | |

The comment in the unit says systemd-sleep on the Thor does not run hooks in `/etc/systemd/system-sleep/` (`systemd/gleipnir-sleep.service`, comment). That is a repo-reported observation (`docs/evidence.md`, 2026-10-08) and not re-checked here.

## Decky plugin manifests

| File | Field | Value | Notes |
|---|---|---|---|
| `plugin.json` | `name` | `Gleipnir` | |
| `plugin.json` | `flags` | `["root"]` | The backend runs as root |
| `plugin.json` | `api_version` | 1 | |
| `dist/index.js` | `API_VERSION` | 2, falling back to 1 | `dist/index.js:2`, `:8-12` |
| `package.json` | `version` | `0.2.1-debug` | The description says `Gleipnir (Debug)` |
| `package.json` | `license` | `MIT` | `bin/gleipnir` is GPL-2.0-or-later (see `README.md`, "Credits and licence") |

## Install paths on the Thor

| Path | Set by | Source |
|---|---|---|
| `/home/armada/homebrew/plugins/gleipnir/` | `scripts/deploy.sh` (`PLUGIN_DIR`) | `scripts/deploy.sh:13` |
| `/var/local/bin/gleipnir` | Decky install (`BIN_DST`) | `main.py:24` |
| `/etc/systemd/system/gleipnir.service` | Decky install (`UNIT_DST`) | `main.py:25` |
| `/etc/systemd/system/gleipnir-sleep.service` | Decky install (`SLEEP_UNIT_DST`) | `main.py:26` |
| `/var/lib/gleipnir/` | The daemon and the backend (`STATE_DIR`) | `main.py:27`, `bin/gleipnir:46` |

The plugin directory is not used at run time for the daemon: `main.py` falls back to the plugin copy of the script only when `/var/local/bin/gleipnir` does not exist (for example `main.py:94`, `_status_sync`).

## Deployment inputs (`scripts/deploy.sh`)

| Input | Precedence | Source |
|---|---|---|
| First argument | Highest | `scripts/deploy.sh:11` |
| `THOR_HOST` environment variable | Second | `:11` |
| `THOR_ENV_FILE` (a file with a `THOR_HOST=` line) | Third | `:6-10` |
| `local/thor.env` in the repo | Fourth | `:7` |
| `../../local/thor.env` | Fifth (the AynThor junction layout) | `:7` |

`local/` is in `.gitignore` (`.gitignore:5`), so a local env file is not committed. The script copies `plugin.json`, `package.json`, `main.py`, `LICENSE`, `bin/gleipnir`, both unit files and `dist/index.js` (`scripts/deploy.sh:18-21`). It does not copy `tests/`, `docs/` or `CHANGELOG.md`. It runs `bash -n bin/gleipnir` locally first (`:15`), and it restarts `plugin_loader.service` on the Thor (`:27`).

The deploy script needs SSH key access and sudo on the Thor, and the README says so (`README.md`, "Install").
