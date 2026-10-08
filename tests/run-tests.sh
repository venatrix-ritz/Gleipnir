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
}
sim_start() {  # sim_start effective|ineffective
    ( while sleep 0.15; do
          v=$(cat "$PS/battery/constant_charge_current")
          if [ "$1" = effective ] && [ "$v" -le 1000 ]; then echo "Not charging" > "$PS/battery/status"; echo 0 > "$PS/battery/current_now"
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

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
