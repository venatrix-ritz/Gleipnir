# Command-line reference

`gleipnir` is one bash script (`bin/gleipnir`; installed as `/var/local/bin/gleipnir`). With no arguments it is the daemon.

| Invocation | Needs root | Writes the limit | What it does |
|---|---|---|---|
| `gleipnir` | yes | when armed | the daemon (what `gleipnir.service` runs) |
| `gleipnir --status` | no | never | node, clamp value, verification state, a battery snapshot, the last 5 journal lines |
| `gleipnir --status --json` | no | never | the same as one JSON object; used by the Decky panel |
| `gleipnir --test` | no | never | prints the test plan |
| `gleipnir --test --run` | yes | during the test only | the supervised test ([testing.md](testing.md)) |
| `gleipnir --restore` | yes | only if a clamp is found | undo a leftover clamp (the unit runs this after every stop) |

## `--status --json` fields
`node`, `kind`, `clamp_value`, `node_max`, `verified` (bool), `verified_why` (empty when verified), `kernel`, `capacity` (%), `status` (kernel string), `usb_online` (0/1), `current_ua`, `voltage_uv`, `temp_dc` (tenths of a degree C), `health`, `limit` (current value of the node).

## Exit codes
| Code | Meaning |
|---|---|
| `0` | clean exit; test passed; `--restore` done |
| `1` | unknown option |
| `3` | no usable limit node (status, test and restore modes) |
| `4` | test preconditions not met (nothing was written) |
| `5` | test failed or aborted (the limit was restored) |
| `78` | the daemon found no usable node, three writes failed in a row, or the watchdog proved the limit ineffective; the unit does not restart on `78`, so `systemctl status gleipnir` shows it failed |

## Files and names
| Path / name | What |
|---|---|
| `/var/local/bin/gleipnir` | the installed script |
| `/etc/systemd/system/gleipnir.service` | the unit (`StateDirectory=gleipnir`) |
| `/var/lib/gleipnir/verified` | the verification marker |
| `/var/lib/gleipnir/test-*.log`, `ui-test.out` | test output (the second is what the panel shows) |
| journal tag `gleipnir` | all daemon and test logging |
| `/home/armada/homebrew/plugins/gleipnir/` | the Decky plugin |
