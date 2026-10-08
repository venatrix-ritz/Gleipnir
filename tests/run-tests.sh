#!/usr/bin/env bash
# Behaviour tests for bin/gleipnir against a fake power_supply tree. No device, no root, no real battery.
# Run: bash tests/run-tests.sh      (about a minute)
# The fake battery is driven by a small simulator: SIM=effective  -> status 'Not charging' / 0 current when the limit
# is at or below 1000; SIM=ineffective -> keeps charging at 1.5 A whatever the limit says.
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/gleipnir"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1 :: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() {  # has NAME FILE PATTERN : retried for 3 s, because the daemon logs a moment after it writes the node
    local i=0; while [ "$i" -lt 15 ]; do grep -q -- "$3" "$2" 2>/dev/null && { ok "$1"; return; }; sleep 0.2; i=$((i + 1)); done
    bad "$1" "'$2' lacks '$3'"
}

PIDS=()
cleanup_all() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done; rm -rf "${T:-/nonexistent-dir}"; }
trap cleanup_all EXIT

new_world() {  # new_world CAP STATUS USB LIMIT
    T=$(mktemp -d); PS=$T/ps; mkdir -p "$PS/battery" "$PS/qcom-battmgr-usb" "$T/state"
    echo "$1" > "$PS/battery/capacity"; echo "$2" > "$PS/battery/status"; echo "$3" > "$PS/qcom-battmgr-usb/online"
    echo 1500000 > "$PS/battery/current_now"; echo 4000000 > "$PS/battery/voltage_now"; echo 300 > "$PS/battery/temp"; echo Good > "$PS/battery/health"
    echo "$4" > "$PS/battery/constant_charge_current"; echo 9000000 > "$PS/battery/constant_charge_current_max"
    LOG=$T/log
    export GLEIPNIR_NO_SYSLOG=1 GLEIPNIR_PS_BASE=$PS GLEIPNIR_STATE_DIR=$T/state GLEIPNIR_LOG_FILE=$LOG GLEIPNIR_KERNEL=test-1 GLEIPNIR_ALLOW_NONROOT=1
    export GLEIPNIR_POLL_S=1 GLEIPNIR_SETTLE_S=2 GLEIPNIR_MIN_HOLD_S=0 GLEIPNIR_HEARTBEAT_S=2 GLEIPNIR_WAIT_S=1
    export GLEIPNIR_CLAMP_S=6 GLEIPNIR_BASE_S=2 GLEIPNIR_AFTER_S=4 GLEIPNIR_SAMPLE_S=1
    export GLEIPNIR_APPLY_WAIT_S=6 GLEIPNIR_HOLD_S=1 GLEIPNIR_WAIT_STEP_DS=2
}
sim_start() {  # sim_start effective|ineffective|late [LAG_S] : 'late' reacts to a change of the limit only after LAG_S seconds
    local lag=${2:-0}
    ( last=""; changed=$SECONDS; prev=$(cat "$PS/battery/constant_charge_current")
      while sleep 0.15; do
          v=$(cat "$PS/battery/constant_charge_current")
          [ "$v" != "$last" ] && { last=$v; changed=$SECONDS; }
          seen=$v; [ "$1" = late ] && [ $((SECONDS - changed)) -lt "$lag" ] && seen=${prev:-$v}
          [ $((SECONDS - changed)) -ge "$lag" ] && prev=$v
          if [ "$1" != ineffective ] && [ "$seen" -le 1000 ]; then echo "Not charging" > "$PS/battery/status"; echo 0 > "$PS/battery/current_now"
          elif [ -r "$PS/battery/status" ] && [ "$(cat "$PS/usb_gone" 2>/dev/null)" != 1 ]; then echo Charging > "$PS/battery/status"; echo 1500000 > "$PS/battery/current_now"; fi
      done ) &
    SIM=$!; PIDS+=("$SIM")
}
sim_stop() { kill "$SIM" 2>/dev/null; wait "$SIM" 2>/dev/null; }
marker() { printf 'node=%s\nvalue=0\nkernel=%s\nverified_at=now\n' "$PS/battery/constant_charge_current" "${1:-test-1}" > "$T/state/verified"; }
limit() { cat "$PS/battery/constant_charge_current"; }
daemon_start() { bash "$SCRIPT" 2>>"$T/stderr" & D=$!; PIDS+=("$D"); }
daemon_stop() { kill -TERM "$D" 2>/dev/null; wait "$D" 2>/dev/null; }
wait_limit() {  # wait_limit VALUE SECONDS
    local t=0; while [ "$t" -lt "$(( $2 * 5 ))" ]; do [ "$(limit)" = "$1" ] && return 0; sleep 0.2; t=$((t + 1)); done; return 1
}

echo "S1 not verified: the daemon only watches"
new_world 85 Charging 1 9000000; sim_start effective; daemon_start; sleep 4
eq "limit untouched while unverified" "$(limit)" 9000000
has "says monitor-only" "$LOG" "MONITOR-ONLY"
daemon_stop; eq "still untouched after stop" "$(limit)" 9000000; sim_stop

echo "S2 leftover clamp is undone even when unverified"
new_world 85 Charging 1 0; sim_start effective; daemon_start
wait_limit 9000000 5; eq "leftover clamp released to the node maximum" "$(limit)" 9000000
has "logs the release" "$LOG" "leftover clamp"; daemon_stop; sim_stop

echo "S3 verified: clamp at 80 %, put the firmware's own value back at 77 %"
new_world 85 Charging 1 4680000; marker; sim_start effective; daemon_start
wait_limit 0 6; eq "clamped to 0" "$(limit)" 0
has "logs the clamp with a snapshot" "$LOG" "CLAMP at 85%"
sleep 3; eq "stays clamped at 85 %" "$(limit)" 0
echo 76 > "$PS/battery/capacity"; wait_limit 4680000 5; eq "released to the value found, not the maximum" "$(limit)" 4680000
has "logs the release" "$LOG" "RELEASE (battery down to 76%)"
sleep 2; has "heartbeat logged" "$LOG" "heartbeat"
daemon_stop; sim_stop

echo "S4 unplug releases"
new_world 90 Charging 1 9000000; marker; sim_start effective; daemon_start; wait_limit 0 6
echo 0 > "$PS/qcom-battmgr-usb/online"; wait_limit 9000000 5; eq "released on unplug" "$(limit)" 9000000
has "logs why" "$LOG" "charger unplugged"; daemon_stop; sim_stop

echo "S5 ineffective limit: watchdog releases, deletes the marker, exits 78"
new_world 90 Charging 1 9000000; marker; sim_start ineffective; daemon_start
t=0; while kill -0 "$D" 2>/dev/null && [ "$t" -lt 100 ]; do sleep 0.2; t=$((t + 1)); done
wait "$D"; rc=$?; eq "exit status 78" "$rc" 78
eq "limit restored" "$(limit)" 9000000
eq "marker deleted" "$([ -e "$T/state/verified" ] && echo present || echo gone)" gone
has "logs the watchdog" "$LOG" "WATCHDOG"; sim_stop

echo "S5b discharging under load while the status says Charging must not trip the watchdog"
new_world 90 Charging 1 9000000; marker; sim_start effective; daemon_start; wait_limit 0 6
sim_stop; echo Charging > "$PS/battery/status"; echo -1500000 > "$PS/battery/current_now"; sleep 8
eq "daemon still running" "$(kill -0 "$D" 2>/dev/null && echo yes || echo no)" yes
eq "clamp still held" "$(limit)" 0
eq "marker kept" "$([ -e "$T/state/verified" ] && echo present || echo gone)" present
if grep -q WATCHDOG "$LOG" 2>/dev/null; then bad "no watchdog on discharge" "fired"; else ok "no watchdog on discharge"; fi; daemon_stop

echo "S6 marker for another kernel disarms"
new_world 90 Charging 1 9000000; marker some-other-kernel; sim_start effective; daemon_start; sleep 3
eq "no clamp with a stale marker" "$(limit)" 9000000; has "explains" "$LOG" "re-run the test"; daemon_stop; sim_stop

echo "S7 SIGTERM while clamped restores"
new_world 90 Charging 1 4680000; marker; sim_start effective; daemon_start; wait_limit 0 6
daemon_stop; eq "restored on TERM" "$(limit)" 4680000
has "logs the exit release" "$LOG" "RELEASE (daemon exiting)"
[ "$(limit)" = 4680000 ] || { echo "--- log:"; cat "$LOG"; echo "--- stderr:"; tail -5 "$T/stderr"; }
sim_stop

echo "S8 test mode PASS on a limit that works"
new_world 60 Charging 1 4680000; sim_start effective
bash "$SCRIPT" --test --run > "$T/out" 2>&1; rc=$?; eq "exit 0" "$rc" 0
eq "limit back to the value found" "$(limit)" 4680000
has "result says PASS" "$T/out" "^PASS"
has "marker has the node" "$T/state/verified" "^node=$PS/battery/constant_charge_current"
has "marker has the kernel" "$T/state/verified" "^kernel=test-1"
ls "$T"/state/test-*.log >/dev/null 2>&1 && ok "test log saved" || bad "test log saved" "none"
sim_stop

echo "S9 test mode FAIL on a limit the firmware ignores"
new_world 60 Charging 1 9000000; sim_start ineffective
bash "$SCRIPT" --test --run > "$T/out" 2>&1; rc=$?; eq "exit 5" "$rc" 5
eq "limit restored" "$(limit)" 9000000
eq "no marker" "$([ -e "$T/state/verified" ] && echo present || echo gone)" gone
has "result says FAIL" "$T/out" "^FAIL"; sim_stop

echo "S10 test mode refuses when not charging, too full, or already clamped"
new_world 60 Discharging 0 9000000
bash "$SCRIPT" --test --run > "$T/out" 2>&1; eq "refuses unplugged (exit 4)" "$?" 4; eq "wrote nothing" "$(limit)" 9000000
has "lists the supplies it saw" "$T/out" "Supplies seen"
new_world 95 Charging 1 9000000
bash "$SCRIPT" --test --run > "$T/out" 2>&1; eq "refuses at 95 % (exit 4)" "$?" 4
new_world 60 Charging 1 0
bash "$SCRIPT" --test --run > "$T/out" 2>&1; eq "refuses an already clamped node (exit 4)" "$?" 4
new_world 60 Charging 1 9000000
bash "$SCRIPT" --test > "$T/out" 2>&1; eq "plan-only exit 0" "$?" 0; eq "plan-only wrote nothing" "$(limit)" 9000000

echo "S11 test mode aborts and restores when the charger is pulled mid-test"
new_world 60 Charging 1 4680000; sim_start effective
( sleep 4; echo 0 > "$PS/qcom-battmgr-usb/online" ) &
bash "$SCRIPT" --test --run > "$T/out" 2>&1; rc=$?; eq "exit 5" "$rc" 5; eq "limit restored after abort" "$(limit)" 4680000
has "says aborted" "$T/out" "ABORTED"; eq "no marker" "$([ -e "$T/state/verified" ] && echo present || echo gone)" gone; sim_stop

echo "S12 --restore and --status"
new_world 85 Charging 1 0
bash "$SCRIPT" --restore; eq "--restore undoes a clamp" "$(limit)" 9000000
bash "$SCRIPT" --status --json > "$T/json"; has "json has the node" "$T/json" '"verified":false'
PY=$(command -v python3 || command -v python); "$PY" -c "import json,sys; json.load(open(sys.argv[1]))" "$T/json" 2>/dev/null && ok "status --json is valid JSON" || bad "status --json" "invalid JSON"

echo "S13 no usable node"
new_world 85 Charging 1 9000000; rm "$PS/battery/constant_charge_current"
bash "$SCRIPT" > /dev/null 2>&1; eq "daemon exits 78" "$?" 78
bash "$SCRIPT" --status > /dev/null 2>&1; eq "--status exits 3" "$?" 3

echo "S14 test mode PASS when the limit takes effect late (the Thor took about a minute)"
new_world 60 Charging 1 4680000; export GLEIPNIR_CLAMP_S=14 GLEIPNIR_AFTER_S=14; sim_start late 3
bash "$SCRIPT" --test --run > "$T/out" 2>&1; rc=$?; eq "exit 0" "$rc" 0
eq "limit back to the value found" "$(limit)" 4680000
has "waited for charging to resume" "$T/out" "waiting for charging to resume"
has "result says PASS" "$T/out" "^PASS"; sim_stop

echo "S15 test mode: an effect that arrives after the wait is a FAIL, and the limit is still put back and held"
new_world 60 Charging 1 4680000; export GLEIPNIR_CLAMP_S=4 GLEIPNIR_AFTER_S=4; sim_start late 30
bash "$SCRIPT" --test --run > "$T/out" 2>&1; rc=$?; eq "exit 5" "$rc" 5
eq "limit restored" "$(limit)" 4680000; sleep 2; eq "and still restored 2 s later" "$(limit)" 4680000
eq "no marker" "$([ -e "$T/state/verified" ] && echo present || echo gone)" gone; sim_stop

echo "S16 a clamp that lands late with no clamp of ours is undone (the stuck state seen on 2026-10-08)"
new_world 70 Charging 1 9000000; sim_start effective; daemon_start; sleep 2
echo 0 > "$PS/battery/constant_charge_current"          # something else's write takes effect now
wait_limit 9000000 6; eq "daemon puts the maximum back" "$(limit)" 9000000
has "logs it" "$LOG" "LATE CLAMP"; daemon_stop; sim_stop

echo "S17 the settle logic against a node that shows writes late and drops writes while one is pending"
export GLEIPNIR_NO_SYSLOG=1; TMPOUT=$(mktemp)
( set +u
  T=$(mktemp -d); NODE=$T/node; LIM=$NODE; CLAMP_DETECT=1000; FAILS=0
  num() { case "${1:-}" in ''|*[!0-9-]*) echo 0 ;; *) echo "$1" ;; esac; }
  log() { :; }
  is_clamped() { [ "$(num "${1:-}")" -le "$CLAMP_DETECT" ]; }
  source <(sed -n '/^# --- begin settle/,/^# --- end settle/p' "$SCRIPT")
  now_ms() { date +%s%3N; }
  model_tick() {
      [ -s "$NODE.queue" ] || return 0
      local now at v; now=$(now_ms); : > "$NODE.keep"
      while read -r at v; do if [ "$now" -ge "$at" ]; then echo "$v" > "$NODE.applied"; else echo "$at $v" >> "$NODE.keep"; fi; done < "$NODE.queue"
      mv "$NODE.keep" "$NODE.queue"
  }
  rd() { model_tick; cat "$NODE.applied"; }
  node_write() { model_tick; if [ "$MODEL_DROP" = 1 ] && [ -s "$NODE.queue" ]; then return 0; fi; echo "$(( $(now_ms) + MODEL_LAG_MS )) $1" >> "$NODE.queue"; }
  world() { echo "$3" > "$NODE.applied"; : > "$NODE.queue"; MODEL_LAG_MS=$1; MODEL_DROP=$2; FAILS=0; }
  WAIT_STEP_DS=2

  APPLY_WAIT_S=4; HOLD_S=1
  world 1000 0 9000000; t0=$(now_ms); write_limit 0 exact; rc=$?; took=$(( $(now_ms) - t0 ))
  [ "$rc" = 0 ] && [ "$took" -ge 900 ] && [ "$took" -lt 3500 ] && echo "  ok   a write that shows after 1 s is accepted, not called refused (took ${took} ms)" || echo "  FAIL late write accepted :: rc=$rc took=$took"

  APPLY_WAIT_S=1
  world 8000 0 9000000; write_limit 0 exact; rc=$?
  [ "$rc" = 1 ] && [ "$FAILS" = 1 ] && echo "  ok   a write that never shows within the wait is a counted failure" || echo "  FAIL counted failure :: rc=$rc fails=$FAILS"

  # the 2026-10-08 failure: the clamp lands after the restore was written; the restore must notice and write again
  APPLY_WAIT_S=3; HOLD_S=3
  world 2000 1 9000000; node_write 0                       # the clamp is on its way (lands in 2 s)
  ensure_released 9000000; rc=$?
  sleep 3; final=$(rd "$LIM")
  [ "$rc" = 0 ] && [ "$final" = 9000000 ] && echo "  ok   a restore written while a clamp is in flight ends released and stays released" || echo "  FAIL restore vs late clamp :: rc=$rc final=$final"

  APPLY_WAIT_S=1; HOLD_S=1; t0=$(now_ms)
  world 999999 0 0; ensure_released 9000000; rc=$?; took=$(( $(now_ms) - t0 ))
  [ "$rc" = 1 ] && [ "$took" -lt 12000 ] && echo "  ok   a node that ignores writes makes the restore fail after bounded time (${took} ms), not hang" || echo "  FAIL bounded failure :: rc=$rc took=$took"
  rm -rf "$T"
) > "$TMPOUT" 2>&1
cat "$TMPOUT"; PASS=$((PASS + $(grep -c "^  ok " "$TMPOUT"))); FAIL=$((FAIL + $(grep -c "^  FAIL " "$TMPOUT")))

echo "S18 monitoring: a released limit, a charger and a low battery that is not charging is logged; the 77-80 % band is not"
new_world 70 "Not charging" 1 9000000; daemon_start; sleep 8
has "warns when not charging well below the cap" "$LOG" "NOT CHARGING with the limit released"; daemon_stop
new_world 78 "Not charging" 1 9000000; daemon_start; sleep 8
if grep -q "NOT CHARGING" "$LOG" 2>/dev/null; then bad "no warning inside the 77-80 % band" "warned"; else ok "no warning inside the 77-80 % band"; fi; daemon_stop

presleep() { GLEIPNIR_SLEEP_APPLY_WAIT_S=5 "$@" bash "$SCRIPT" --pre-sleep 2>>"$T/stderr"; }
echo "S19 pre-sleep: armed and at or above the floor, the node is clamped and the sleep file is written first"
new_world 78 Charging 1 9000000; marker; sim_start effective; presleep env
eq "clamped before the freeze" "$(limit)" 0
eq "sleep file written" "$([ -e "$T/state/sleep-clamp" ] && echo yes || echo no)" yes
eq "sleep file keeps the old value" "$(sed -n 's/^saved=//p' "$T/state/sleep-clamp")" 9000000
has "logs it" "$LOG" "PRE-SLEEP CLAMP"; sim_stop
echo "S19b pre-sleep clamps on battery too (a charger plugged in while asleep must not charge past the cap)"
new_world 78 Discharging 0 9000000; marker; sim_start effective; presleep env
eq "clamped with the charger out" "$(limit)" 0; sim_stop
echo "S20 pre-sleep below the floor does nothing"
new_world 60 Charging 1 9000000; marker; sim_start effective; presleep env
eq "not clamped at 60 %" "$(limit)" 9000000
eq "no sleep file" "$([ -e "$T/state/sleep-clamp" ] && echo yes || echo no)" no; sim_stop
echo "S21 pre-sleep when not armed does nothing"
new_world 85 Charging 1 9000000; sim_start effective; presleep env
eq "not clamped without a marker" "$(limit)" 9000000; has "says why" "$LOG" "not armed"; sim_stop
echo "S22 the running daemon takes a pre-sleep clamp over instead of undoing it, and releases it by the normal rules"
new_world 78 Charging 1 9000000; marker; sim_start effective; daemon_start; sleep 3
presleep env; sleep 4
eq "clamp kept (no LATE CLAMP undo)" "$(limit)" 0
has "daemon adopts it" "$LOG" "ADOPT"
if grep -q "LATE CLAMP" "$LOG" 2>/dev/null; then bad "no late-clamp undo" "undone"; else ok "no late-clamp undo"; fi
echo 77 > "$PS/battery/capacity"; wait_limit 9000000 6; eq "released at 77 %" "$(limit)" 9000000; has "logs the release" "$LOG" "battery down to 77%"; daemon_stop; sim_stop
echo "S22b an adopted clamp is released at once when the charger is out on resume"
new_world 85 Charging 1 9000000; marker; sim_start effective; daemon_start; sleep 3
presleep env; sleep 2; echo 0 > "$PS/qcom-battmgr-usb/online"; wait_limit 9000000 6
eq "released on unplug" "$(limit)" 9000000; has "says why" "$LOG" "charger unplugged"; daemon_stop; sim_stop
echo "S23 post-sleep with no daemon releases the sleep clamp; with a daemon it leaves it"
new_world 78 Charging 1 9000000; marker; sim_start effective; presleep env
GLEIPNIR_SYSTEMCTL=true bash "$SCRIPT" --post-sleep 2>>"$T/stderr"; eq "daemon active: clamp left for it" "$(limit)" 0
GLEIPNIR_SYSTEMCTL=false GLEIPNIR_HOLD_S=1 bash "$SCRIPT" --post-sleep 2>>"$T/stderr"; eq "no daemon: released" "$(limit)" 9000000
eq "sleep file removed" "$([ -e "$T/state/sleep-clamp" ] && echo yes || echo no)" no; sim_stop

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
