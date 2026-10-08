# Changelog

No version numbers have been cut yet.

## Unreleased
- Initial release (2026-10-07): Decky plugin plus the `gleipnir` daemon, status report, safety test and restore command. Watch-only until a measured test passes on the running kernel; restores on every exit; read-back of every write; watchdog for an ineffective limit; journal logging with battery snapshots and a heartbeat.
- Review hardening before publishing: the test only writes the limit back if it clamped it, refuses while the service is running, and lists every power supply when it refuses; a failed test start in the backend puts the daemon back.
- Full documentation under `docs/`.
- Tests: a simulated-battery suite for the daemon (47 checks) and a fake-runner suite for the backend (8 checks); both also pass on the Thor's own Linux userland.
