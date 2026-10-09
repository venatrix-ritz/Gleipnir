# How Gleipnir works

## The idea
Holding a lithium battery near 80 % instead of 100 % while it sits on a charger slows its wear. Linux has a standard control for this, `charge_control_end_threshold`, but the Thor's firmware ignores it. Gleipnir uses the other control the Thor's kernel offers: the battery manager's **charge current limit**, exposed on Armada's kernel as `constant_charge_current` (and on one community fork as `charge_control_limit`). Armada's patch says writing `0` stops battery charging while the charger keeps powering the system. [See [evidence.md](evidence.md).]

So: when the Thor is plugged in and at 80 % or more, Gleipnir sets the limit to the "stop charging" value; when you unplug it, or the level falls to 77 %, it puts the limit back to what it found.

**Nobody has shown that the Thor's firmware obeys this.** Gleipnir therefore does nothing until its own measured test passes on your Thor and kernel ([testing.md](testing.md)).

## Parts
| Part | What it does |
|---|---|
| `bin/gleipnir` | one bash script: the daemon, `--status`, the safety `--test`, `--restore` |
| `systemd/gleipnir.service` | runs the daemon as root; restarts on failure but never after exit `78`; runs `--restore` after any stop |
| `main.py` + `dist/index.js` | the Decky plugin (flag `root`): installs and starts the daemon, runs the test, shows status and the log |

## Which node
| Node | Clamp value | Where it exists |
|---|---|---|
| `charge_control_limit` | `1000` (µA) | MgeeeeK's patched `qcom_battmgr` |
| `constant_charge_current` | `0` | Armada's kernel (patch `0903`), including the surveyed Thor |

Neither present: the daemon exits `78` and the status says so.

## The daemon's loop (every 30 s)
```
read capacity, USB-online, status, current
is the verification marker valid for this node, value and kernel?
  no  -> MONITOR-ONLY: log, never write; if a clamp is found left over, undo it
  yes -> state "released":  plugged in, capacity >= 80 %, and >= 120 s since the last change  -> CLAMP
         state "clamped":   unplugged -> RELEASE;   capacity <= 77 % -> RELEASE;
                            after 120 s clamped: still "Charging" above 200 mA for 3 polls in a row
                                                 -> WATCHDOG: RELEASE, delete the marker, exit 78
heartbeat every 600 s; three failed writes in a row -> release and exit 78
```
Thresholds are constants at the top of `bin/gleipnir`: target 80, release at 77, 120 s settle, 120 s minimum between clamps, 200 mA watchdog, 3 strikes.

## Sleep
Armada's native sleep (s2idle) freezes every process, so the daemon cannot clamp at 80 % while the Thor sleeps. Before the change below, a Thor that slept at 78 % on a charger woke at 88 %. The firmware keeps a clamp it already holds through a sleep, so `gleipnir-sleep.service` (`Before=sleep.target`) runs `gleipnir --pre-sleep` just before the suspend: if the battery is at or above the **sleep setting** it writes the clamp first (a sleep file goes in front of it so the running daemon adopts the clamp instead of undoing it), the daemon holds that clamp until `--post-sleep` removes the sleep file after the resume (at most an hour); then it applies its normal rules at its next poll (releases when unplugged or at 77 % and below).
- **The setting** (`gleipnir --set-sleep-floor N`, or the Decky panel): `0` clamps before every sleep (default; the cap always holds, the Thor does not charge while asleep); `70` clamps from 70 % up (below that it charges asleep and can pass the cap); `101` never clamps for sleep.
- **Fake sleep** (Armada Control, Sleep type) keeps system services running, so the daemon keeps polling and the setting is not used. The panel shows the current sleep type and hides the setting then.
- Why a unit: `systemd-sleep` on the surveyed build ran the hooks in `/usr/lib/systemd/system-sleep/` but not one placed in `/etc/systemd/system-sleep/`.
- Evidence: [evidence.md](evidence.md).

## The node is slow
A write to the limit node does not show up at once, and does not act at once. On 2026-10-08 the node still read the old value right after the first test wrote the clamp, and about a minute later it read the clamp and charging had stopped. The test had already called that a refusal and written its restore; the restore did not hold, and the clamp was still in place until `--restore` was run by hand. So:
- a write is judged by waiting for the node to show it (up to `APPLY_WAIT_S`, 120 s), not by an instant readback;
- a restore counts only after the node has kept showing the released value for `HOLD_S` (20 s), and is written again if a clamp lands after it;
- the daemon records a clamp before writing it, so a stop signal in between still releases it, and undoes a clamp it did not make.

## Monitoring
Besides the heartbeat, the daemon logs `NOT CHARGING with the limit released` (at most every 10 minutes) when nothing is clamped, a charger is attached, the battery is below the 77 % release point and the status is not `Charging` for five polls in a row. After a clamp held for about 90 s at 80 % and then released, the Thor stayed in `Not charging` for more than ten minutes ([evidence](evidence.md)); this warning is how that shows up if it happens below the cap, where it matters.

## The value it puts back
The firmware changes the limit by itself (observed `9000000` at 73 % charge and `4680000` at 96 % on the surveyed Thor). Gleipnir remembers the value it found before clamping and restores exactly that. If that cannot be written it falls back to the node's `_max`.

## The verification marker
`/var/lib/gleipnir/verified` holds `node=`, `value=`, `kernel=`, `verified_at=`, `baseline_uA=`. The daemon re-reads it every poll. It only counts if the node path, the clamp value and `uname -r` all match the running system, so a kernel update or a different node disarms Gleipnir until you test again. The watchdog deletes it if the limit ever proves ineffective.

## Logging
Everything goes to the journal under the tag `gleipnir` (`journalctl -t gleipnir`): start-up, arming and disarming, every CLAMP and RELEASE with a one-line battery snapshot (`cap=… status=… usb=… current=… voltage=… temp=… health=… limit=…`), every failed write, the watchdog, and a heartbeat. Test runs are also saved in `/var/lib/gleipnir/test-<time>.log`.
