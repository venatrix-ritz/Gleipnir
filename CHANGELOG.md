# Changelog

## Unreleased
- **Fixed:** the safety test called a working limit a failure and left charging stopped. On the Thor on 2026-10-08 the node still read the old value 1.5 s after the clamp was written and the effect arrived about a minute later; the test judged the instant readback, restored in the middle of it, and the clamp then took hold with the restore not holding. Now: writes are judged by waiting for the node (`GLEIPNIR_APPLY_WAIT_S`, 120 s); the test waits up to 180 s for charging to stop and up to 120 s for it to resume, stopping as soon as it sees the result; a restore must stay in place for `GLEIPNIR_HOLD_S` (20 s) and is written again if a clamp lands after it; `--restore` and every release do the same; the daemon records a clamp before writing it (a TERM in between used to leave it in place) and undoes a clamp it did not make (`LATE CLAMP`). New tests simulate a battery whose effect lags the limit, a late clamp, and a node that shows writes late and drops writes while one is pending (61 checks).

No version numbers have been cut yet.

## Unreleased
- Initial release (2026-10-07): Decky plugin plus the `gleipnir` daemon, status report, safety test and restore command. Watch-only until a measured test passes on the running kernel; restores on every exit; read-back of every write; watchdog for an ineffective limit; journal logging with battery snapshots and a heartbeat.
- Review hardening before publishing: the test only writes the limit back if it clamped it, refuses while the service is running, and lists every power supply when it refuses; a failed test start in the backend puts the daemon back.
- Full documentation under `docs/`.
- Tests: a simulated-battery suite for the daemon (47 checks) and a fake-runner suite for the backend (8 checks); both also pass on the Thor's own Linux userland.
