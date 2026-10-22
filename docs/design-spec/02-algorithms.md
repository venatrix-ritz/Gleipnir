# 02 - Algorithms

Each algorithm below is taken from `bin/gleipnir` unless another file is named. Parameters are shown with their defaults. Pseudocode follows the code's order of checks, which matters: the release checks are evaluated before the watchdog, and the sleep hold suppresses both release rules.

## 1. Constants and their meaning

| Symbol | Default | Meaning | Source |
|---|---|---|---|
| `TARGET` | 80 | Charge at which the daemon clamps while plugged in | `:61` |
| `RELEASE_AT` | 77 | Charge at or below which the daemon releases | `:62` |
| `CLAMP_DETECT` | 1000 | Any limit value at or below this is treated as a clamp | `:63` |
| `POLL_S` | 30 | Seconds between polls | `:64` |
| `SETTLE_S` | 120 | Seconds after a clamp before the watchdog may strike | `:65` |
| `MIN_HOLD_S` | 120 | Minimum seconds between a clamp or release and the next clamp | `:66` |
| `HEARTBEAT_S` | 600 | Seconds between heartbeat log lines | `:67` |
| `WATCH_UA` | 200000 | Watchdog threshold (positive µA) | `:68` |
| `BAD_LIMIT` | 3 | Watchdog strikes before it acts | `:69` |
| `APPLY_WAIT_S` | 120 | Maximum seconds for a write to show in the node | `:70` |
| `HOLD_S` | 20 | Seconds a restored value must stay released | `:71` |
| `WAIT_STEP_DS` | 10 | Poll step in tenths of a second (so 1 s by default) | `:72` |
| `SLEEP_APPLY_WAIT_S` | 10 | Maximum seconds for the pre-sleep clamp to show | `:75` |
| Failed writes in a row before exit 78 | 3 (a literal in the loop, not `BAD_LIMIT`) | `:460` |

The `maxv` fallback is 9000000 when the node's `_max` is missing or at or below `CLAMP_DETECT` (`:105`).

## 2. Node selection and the value fallback

```
if charge_control_limit exists:            LIM=.../charge_control_limit, MAX=..._max, CLAMP_VAL=1000  (fork)
elif constant_charge_current exists:       LIM=.../constant_charge_current, MAX=..._max, CLAMP_VAL=0  (Armada)
else:                                      no node: daemon exits 78; other modes exit 3
maxv = read(MAX), or 9000000 if that is not above CLAMP_DETECT
```
Source: `bin/gleipnir:99-106`, `:205-209`.

## 3. Write and judge: `write_limit` and `wait_for`

A write is not judged by an instant readback. The node is slow (a repo observation; `docs/evidence.md`, 2026-10-08).

```
write_limit(VALUE, MODE):                       # MODE = exact | released
    node_write(VALUE)                           # echo VALUE > LIM, errors hidden
    wait_for(VALUE, MODE):
        max = steps_for(APPLY_WAIT_S)           # 120 steps of 1 s by default
        loop:
            RB = read(LIM)
            if value_ok(VALUE, MODE, RB): return success
            if steps >= max: return failure
            sleep WAIT_STEP_DS/10 s
    success -> FAILS = 0
    failure -> FAILS += 1, log error "did not show in 120s"
```
- `exact` requires the readback to equal the value (`value_ok`, `:118-121`).
- `released` accepts any readback above `CLAMP_DETECT`. The comment says the firmware may adjust its own value right after a write (`:118-119`).
- `FAILS` counts consecutive failures. The main loop exits 78 when it reaches 3 (`:460-463`).

## 4. Release with hold: `ensure_released`

A restore counts only if the node keeps showing the released value. A clamp written earlier can still land.

```
ensure_released(TARGET_VALUE):
    for round in 1..3:
        write_limit(TARGET_VALUE, released)     # if it fails, next round
        for i in 1..(HOLD_S in steps):          # 20 steps of 1 s
            sleep 1 s
            if node reads a clamp value: continue with the next round (write again)
        return success                          # the value held for HOLD_S
    return failure
```
Source: `bin/gleipnir:142-161`. The "continue 2" at `:154` restarts the outer round loop, so a late clamp causes a new write.

## 5. The daemon loop

Each pass (`:397-496`) does the following in order.

### 5.1 Observations (`:400`)
Reads `capacity`, `online`, `status`, `|current_now|` and the signed `current_now`.

### 5.2 Monitoring (`:401-411`)
```
if state == released and online == 1 and capacity < 77 and status != "Charging":
    idle_polls += 1
    if idle_polls >= 5 and (now - last_idle_warn) >= 600 s:
        log warning "NOT CHARGING with the limit released ..."
        last_idle_warn = now
else:
    idle_polls = 0
```
This does not change the limit. It is the only check for the stuck state the repo records (see [05](05-design-decisions-roadmap.md)).

### 5.3 Pre-sleep adoption (`:413-420`)
If the state is `released`, a sleep file exists, and the node reads a clamp value other than the maximum:
- the saved value comes from the sleep file (`saved=`); if that value is itself a clamp it is dropped;
- the state becomes `clamped` with `clamped_at` and `last_change` set to now and `bad = 0`;
- the file is **not** removed, so the daemon keeps holding until `--post-sleep` removes it (logged as `ADOPT`).

If the node does not read a clamp, and the sleep file is older than 300 s, the file is removed (`:419`). A newer file is left in place.

### 5.4 Late-clamp correction (`:421-424`)
If the state is `released` and the node reads a clamp other than the maximum, the daemon writes the maximum back once with `node_write` and logs `LATE CLAMP`. This path does not call `wait_for`: it does not wait for the node to show the value, and it logs an error only if the write command itself fails. A later poll repeats the check. The rule lets the daemon undo a write from an earlier test or run that took effect late.

### 5.5 Marker and arming (`:425-433`)
`marker_ok` runs every pass (algorithm 8). The daemon logs `ARMED` or `MONITOR-ONLY` only when the armed state changes. For a FEX-stamped marker that is adopted (`MARKER_ADOPT=1`), the running daemon rewrites the `kernel=` line to the host kernel (`:426-429`).

### 5.6 Decisions (`:435-459`)

```
if armed == 1:
    if state == released:
        if online == 1 and capacity >= 80 and (now - last_change) >= 120 s:
            clamp()                                    # algorithm 5.7
    else:                                              # state == clamped
        sleep_hold = 1 if the sleep file exists and is at most 3600 s old, else 0
        if sleep_hold == 1:
            (no action: the 77 % and unplug rules wait for --post-sleep)
        elif online != 1:
            release("charger unplugged")
        elif capacity <= 77:
            release("battery down to N%")
        elif (now - clamped_at) >= 120 s:
            if status == "Charging" and current_now > 200000:  bad += 1
            else:                                              bad = 0
            if bad >= 3:
                log error WATCHDOG; release("limit ineffective"); delete marker; exit 78
elif state == clamped:
    release("verification no longer valid")
```
Points to note:
- A clamp needs no `status` check. Only the release and watchdog rules look at the state.
- The release rules are never rate-limited (`last_change` gates only the clamp, `:437`).
- The watchdog counts strikes on successive polls only while the conditions hold. A poll that does not meet the condition resets `bad` to 0 (`:450`).

### 5.7 `clamp()` (`:376-388`)
```
c = read(LIM)
if c is not a clamp value: saved = c             # the value to restore
state = clamped; clamped_at = now; last_change = now   # recorded BEFORE the write
if write_limit(CLAMP_VAL, exact): bad = 0; log CLAMP
else:                              state = released; saved = ""; last_change = now
```
The bookkeeping is done before the write so that a TERM arriving between the write and the bookkeeping still releases (comment at `:379`).

### 5.8 `release(WHY)` (`:364-375`)
```
if state != clamped: return
target = saved if non-empty, else maxv; if target is a clamp value: target = maxv
if ensure_released(target):           log RELEASE (why), restored target
elif ensure_released(maxv):           log warning "could not put target back, restored the node maximum"
else:                                 log error COULD NOT RELEASE with the command to run by hand; return 1
state = released; saved = ""; last_change = now
```
Note the fallback: when the saved value is unknown the release writes the node maximum, which the code takes to be 9000000 when `_max` is absent. The firmware's own value can differ (`docs/evidence.md` observed 9000000 at 73 % and 4680000 at 96 %).

### 5.9 Failure exit and heartbeat (`:460-463`, `:493-495`)
If `FAILS >= 3`, the daemon releases and exits 78. A heartbeat line is logged every `HEARTBEAT_S` seconds.

### 5.10 Poll wait (`:496`)
```
sleep POLL_S &  wait $!
```
Running the sleep in the background and waiting on it lets the `TERM` and `INT` traps run at once instead of after the sleep ends (`:390`).

## 6. Start-up (`:393-395`, `:355-358`, `:360-361`)
1. Wait up to 30 s for `battery/capacity` and `qcom-battmgr-usb/online` to exist.
2. Remove any sleep file (`:360`).
3. Initialise: state released, `last_change = -120` (so a clamp is allowed at once), `bad = 0`.
4. Log `started`. If the node reads a clamp other than the maximum, run `release("leftover clamp from an earlier run")`. This is done whether or not the daemon will be armed.

## 7. The on-device test (`--test --run`, `:274-352`)

### 7.1 Sampling
`avgcur` samples the absolute current every `SAMPLE_S` (2 s) until `BASE_S` (6 s) has passed, and stores the mean in `$STATE_DIR/.avg` (`:300`). The baseline is that mean (`:313`).

### 7.2 Clamp and watch
```
node_write(CLAMP_VAL)                              # no readback here (:317)
effective = 0; eff_streak = 0
while t < CLAMP_S (180):                           # sample every 2 s
    if usb != 1: abort "charger was unplugged"
    if temp >= 450: abort "battery reached ..."
    if cap <= cap0 - 2: abort "battery level fell ..."
    if status != "Charging" or |current| < base/4: eff_streak += 1 else eff_streak = 0
    if eff_streak >= 3: effective = 1; break
```
Source: `:318-328`. The ordering of checks means an abort wins over effect in the same sample.

### 7.3 Restore
`restore_test` calls `ensure_released(orig)` and, failing that, `ensure_released(maxv)`. It runs once (guarded by `restored`), and only if the test wrote the clamp (`touched`). It runs before the abort report (`:329`) and also from the `EXIT`, `INT` and `TERM` trap (`:302-311`).

### 7.4 Resume
```
while t < AFTER_S (120):
    if status == "Charging" and |current| >= base/4: streak += 1 else streak = 0
    if streak >= 2: resumed = 1; break
    if usb != 1: break
```
Source: `:331-340`.

### 7.5 Verdict
PASS when `effective == 1`, `resumed == 1` and the node reads released after the restore (`released_ok`, `:341`, `:344`). PASS writes the marker with `node`, `value`, `kernel`, `verified_at` (`date -Is`) and `baseline_uA` (`:345`). Any other outcome deletes the marker (`:350`).

## 8. Marker check (`marker_ok`, `:173-187`)
```
if no readable marker: MARKER_WHY = "not verified: no marker ..."; return fail
read node=, value=, kernel=
if kernel == "6.11.0" and KERNEL != "6.11.0": MARKER_ADOPT = 1; kernel = KERNEL      # FEX adoption
if node != LIM or value != CLAMP_VAL or kernel != KERNEL: return fail with reason
return success
```
The check is re-run every poll, so a changed node, value or kernel disarms the daemon without a restart (the code path is the same as the first start, `:425`). Only the running daemon writes the adopted kernel back into the file (`:426-429`); `--status` and the sleep hooks judge the marker as adopted and leave it alone (`:179`).

## 9. Kernel detection (`host_kernel`, `:48-60`)
```
k = hostnamectl "Kernel: Linux <release>"        # if hostnamectl exists
if k empty: k = busctl get-property org.freedesktop.hostname1 ... KernelRelease
if k empty: k = uname -r
```
The comment gives the reason: under FEX-Emu `uname -r` returns the emulator's kernel (`6.11.0`) (`:50-51`). `GLEIPNIR_KERNEL` overrides the result for tests (`:60`).

## 10. Sleep hooks

### 10.1 `--pre-sleep` (`:222-241`)
```
marker_ok or exit 0                                # not armed: nothing
if capacity < sleep_floor: log, exit 0             # e.g. floor 70 at 65 %
if node already clamped: log, exit 0
write sleep file ("saved=<current limit>", "at=<epoch>") to STATE_DIR/sleep-clamp.tmp, then mv
APPLY_WAIT_S = SLEEP_APPLY_WAIT_S (10)
if write_limit(CLAMP_VAL, exact): log PRE-SLEEP CLAMP
else: rm sleep file; log error "sleeping unclamped"
exit 0
```
The sleep file is written **before** the clamp so that a daemon that is still running sees the clamp as its own (`:219-221`, adoption at `:413-420`).

### 10.2 The sleep setting
`sleep_floor` returns the saved number when it is a number from 0 to 101, and the default otherwise (`:164-167`). The default is `GLEIPNIR_SLEEP_CLAMP_FROM`, which is 0 (`:74`). A value of 0 clamps before every sleep. The CHANGELOG records 0 as the default because "the cap always holds" (`CHANGELOG.md`, entry "Added: the sleep setting", under Unreleased).

### 10.3 `--post-sleep` (`:242-254`)
```
remove sleep file
if daemon is active: log "it takes over"; exit 0
if node reads a clamp other than maximum: ensure_released(maxv) (logs failure if it cannot)
remove sleep file; exit 0
```

### 10.4 The one-hour cap
The daemon holds a sleep clamp only while the sleep file is at most 3600 s old (`:440-442`). This protects against `--post-sleep` never running. The sleep file itself is removed after 300 s if no clamp is present (`:419`).

## 11. Failure counters and the watchdog in combination
- A failed `write_limit` increments `FAILS`. A successful one resets it. Three in a row end the daemon with exit 78 (`:460-463`).
- The watchdog's `bad` counter is separate from `FAILS`. It resets when a poll does not meet the strike condition.
- `FAILS` is reset to 0 by any successful `write_limit`, including the writes made inside `ensure_released` during a release (`:137`). A release that succeeds therefore clears the failure count.
