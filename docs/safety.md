# Safety

Gleipnir writes to a hardware control on a battery, so it is built to fail safe. This page lists what it relies on, what can go wrong, and what is **not** guaranteed.

## The rules it follows
1. **Watch-only until verified** by a measured test on the running kernel ([testing.md](testing.md)).
2. **Restore on every exit:** `SIGTERM`, `SIGINT`, normal exit and errors trigger a release; the unit's `ExecStopPost` runs `gleipnir --restore` for crashes and `SIGKILL`; a leftover clamp found at start-up is undone first.
3. **Put back what it found,** not a guessed maximum.
4. **Read back every write;** three failures in a row release and stop the daemon (exit `78`).
5. **Watchdog** for a limit that does nothing.
6. **No flapping:** at most one clamp every 120 s; releases are never delayed.
7. **Everything is logged,** and `--status` reports without touching anything.
8. **The test is reversible and bounded:** about 40 s, it restores on any exit, and it aborts if the charger is unplugged, the battery reaches 45 °C, or the level drops 2 points.

## Failure modes
| What goes wrong | What happens |
|---|---|
| The firmware ignores the limit | the test fails (no marker) and the daemon stays watch-only; if it was somehow armed, the watchdog releases and exits `78` |
| The daemon is killed while clamped | `ExecStopPost` runs `--restore`; at next start a leftover clamp is undone |
| The Thor loses power or crashes while clamped | not tested: whether the firmware keeps the value across a reboot is unknown. If the Thor will not charge, run the recovery command below |
| The battery drains while clamped | it releases at 77 %; if the system draws more than the charger supplies it can fall that far, no further |
| The charger is unplugged | released at the next poll (within 30 s) |
| A kernel update changes the node | the marker no longer matches; Gleipnir goes back to watch-only |
| A write is rejected | logged as an error; after three in a row it releases and exits `78` |
| The Decky plugin is removed | `uninstall` stops the daemon (which releases) and runs `--restore` |

## Recovery by hand
If charging ever looks stuck off:
```bash
sudo systemctl stop gleipnir
echo 9000000 | sudo tee /sys/class/power_supply/battery/constant_charge_current
```
(use `charge_control_limit` instead on the fork kernel, and the node's `_max` value if it differs). If the daemon is installed and enabled, restarting it also undoes a leftover clamp. Nobody has tested whether the firmware keeps the value across a reboot.

## What is not guaranteed
- That the Thor's firmware stops charging on this write. That is the point of the test.
- That the Thor stays powered from the charger while clamped. The kernel patch says it does; the test measures charging, not the supply path.
- Anything about batteries you have not tested on. Treat a PASS as "worked once on this kernel", and keep an eye on the first few cycles in the log.

## Security
- The daemon and the plugin backend run as **root**. The daemon takes no network input; its only inputs are sysfs files and its own root-owned marker. `GLEIPNIR_*` environment variables exist only for tests and have no effect on the systemd unit unless someone adds them.
- The plugin backend runs fixed commands (no shell) and has no path or command taken from the panel, except a line count for the log (clamped to 1-200).
- To report a vulnerability, open an issue that says only that you have a security report (no exploit details) and ask for a private way to send it.
