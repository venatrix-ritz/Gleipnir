# Troubleshooting

First look: `gleipnir --status` (no root needed) and `journalctl -t gleipnir -n 40 --no-pager`. The Decky panel shows the same state, battery line and last log lines.

| You see | Meaning | What to do |
|---|---|---|
| "Watching only: not verified yet" | no valid marker, so the daemon only logs | run the safety test (Decky: Gleipnir, Safety test) |
| Log: `MONITOR-ONLY: verification is for node … kernel …` | the marker belongs to another kernel or node | re-run the test; kernel updates disarm Gleipnir by design |
| Test refuses: "status is 'Discharging' (usb online 0)" | not charging, or Gleipnir is reading the wrong supply | plug in and wait for `Charging`. The refusal lists every supply and its `online` value; if one shows `1` while `qcom-battmgr-usb` shows `0`, open an issue with that line |
| Test refuses: "battery is at NN %" | outside 10 to 90 % | let it discharge or charge into range; near full, charging tapers and cannot be measured |
| Test refuses: "charging current is only N uA" | not enough current to compare against | idle the Thor, retry at a lower level |
| Test refuses: "gleipnir.service is running" | it could clamp during the test | `sudo systemctl stop gleipnir` (the panel does this itself) |
| Test says FAIL | charging did not stop, or did not resume | the firmware ignores this control on your Thor or kernel; Gleipnir stays watch-only and changes nothing. Please share the saved log (`/var/lib/gleipnir/test-*.log`) in an issue |
| Test says ABORTED | the charger was unplugged, the battery reached 45 °C, or the level dropped | the limit was restored; retry when conditions are stable |
| `systemctl status gleipnir` shows failed, exit 78 | no usable node, three failed writes, or the watchdog found the limit ineffective | read the journal; the limit was released before exit; re-test before restarting |
| Thor will not charge | a leftover clamp | see the recovery command in [safety.md](safety.md); then `sudo systemctl restart gleipnir` |
| Gleipnir missing from Decky | plugin not installed or Decky not restarted | `./scripts/deploy.sh` again; it restarts `plugin_loader.service` |
| "Run test" button is greyed out | `usb_online` is not `1` | plug the charger in; if it is plugged in, see the wrong-supply row above |

## Reading a log line
```
CLAMP at 85%: limit 4680000 -> 0; cap=85% status=Charging usb=1 current=1450000uA voltage=4100000uV temp=312 health=Good limit=0
```
`limit A -> B` is the value found and the value written; `temp` is tenths of a degree C; `current` is the raw `current_now` in µA (its sign convention varies, Gleipnir uses the absolute value).

## Uninstalling
Decky panel, Log and maintenance, Uninstall daemon (stops it, restores the limit, removes the script, unit and marker). Then remove `/home/armada/homebrew/plugins/gleipnir` and restart `plugin_loader.service`.
