# 05 - Design decisions, rejected alternatives and roadmap

Each decision gives the code or document that shows it, and the reason as the repo states it. Where the repo gives no reason, the entry says so. Nothing here is a reason the author did not write down.

## 1. Decisions

| # | Decision | Reason as stated in the repo | Where |
|---|---|---|---|
| D-1 | Monitor-only until a measured test passes on the running kernel | "Safety design 1" in the script header; "Watch-only until verified" in the safety rules | `bin/gleipnir:18-20`; `docs/safety.md` rule 1 |
| D-2 | The marker is bound to node path, clamp value and kernel | A kernel update or a different node disarms the daemon | `bin/gleipnir:18-20`, `:182`; `docs/troubleshooting.md` |
| D-3 | Use the battery manager's current-limit node, not the standard charge-end threshold | The firmware ignores the standard threshold: it reads back 0 and a write of 80 is accepted but reads 0 | `docs/evidence.md` (2026-10-07 entry); `docs/how-it-works.md` ("The idea") |
| D-4 | Restore the value found before the clamp, not the node maximum | The firmware changes the value itself (9000000 at 73 %, 4680000 at 96 %) | `bin/gleipnir:23`; `docs/evidence.md`; `docs/how-it-works.md` ("The value it puts back") |
| D-5 | Judge writes by waiting for the node, not by an instant readback | The node still showed the old value 1.5 s after a write and the effect came about a minute later | `docs/evidence.md` (first run, 2026-10-08); `bin/gleipnir:110-113` |
| D-6 | A restore counts only after 20 s of holding; a late clamp is written back | A restore written while a clamp was on its way did not hold in the first run | `docs/evidence.md`; `bin/gleipnir:71`, `:142-161` |
| D-7 | Record the clamp before writing it | "A TERM that arrives between the write and the bookkeeping must still release it" | `bin/gleipnir:379` |
| D-8 | Watchdog exits 78 and deletes the marker | "So the failure is visible in `systemctl status`" | `bin/gleipnir:25-26`; `systemd/gleipnir.service` |
| D-9 | The unit does not restart after exit 78 | Stay failed and visible instead of looping | `systemd/gleipnir.service` comment; `bin/gleipnir:39` |
| D-10 | Count only positive current as charging in the watchdog | A game drained the battery at 1.4 to 1.7 A with the status still `Charging`; the earlier build tripped on the size of the current | `bin/gleipnir:448-449`; `CHANGELOG.md` (Unreleased, "Fixed") |
| D-11 | Release is never rate-limited; clamp is rate-limited to one per 120 s | Prevents flapping; releases are the safe direction | `bin/gleipnir:437`, `:473`; `docs/safety.md` rule 6 |
| D-12 | Hysteresis 80 % clamp, 77 % release | Idea taken from MgeeeeK's fork | `bin/gleipnir:4-5`, `:61-62`; `CREDITS.md` |
| D-13 | Sleep clamp through a separate oneshot unit ordered before `sleep.target`, not a hook in `/etc` | The hooks in `/etc/systemd/system-sleep/` did not run on the surveyed build; the unit did | `systemd/gleipnir-sleep.service` comment; `docs/evidence.md` (2026-10-08) |
| D-14 | Write the sleep file before the clamp, and have the running daemon adopt it | A running daemon that did not know about the clamp undid it in seconds at 64 % | `bin/gleipnir:219-221`; `CHANGELOG.md` (entry "Fixed: a pre-sleep clamp was undone", under Unreleased) |
| D-15 | Hold a sleep clamp until `--post-sleep` removes the file (at most one hour) | Without the hold, the 77 % rule removed the clamp at once | `bin/gleipnir:413-420`, `:440-445`; `CHANGELOG.md` |
| D-16 | Default sleep setting is 0 (clamp before every sleep) | "The cap always holds, so the Thor does not charge while asleep"; 70 charges below 70 % | `bin/gleipnir:74`; `CHANGELOG.md` (entry "Added: the sleep setting", under Unreleased) |
| D-17 | Kernel from `hostnamectl` or `busctl` before `uname -r` | Under FEX-Emu `uname -r` reports `6.11.0`, which stamped the wrong marker kernel | `bin/gleipnir:48-60`; `CHANGELOG.md` (Unreleased, "Fixed: kernel mismatch under FEX-Emu") |
| D-18 | The Decky backend never writes the node directly | Stated in the module docstring: "Nothing here writes the battery limit directly" | `main.py:1-10` |
| D-19 | The test stops the daemon for its duration and starts it again | "The two never fight over the limit" | `main.py:188-190` (docstring) |
| D-20 | The Decky backend runs as root | Matches Armada's own privileged plugins | `plugin.json`; `CREDITS.md` |
| D-21 | Debug logging is opt-in and off by default | Heavy logging was added in the debug build; it is off unless asked for | `bin/gleipnir:79`; `CHANGELOG.md` (Unreleased) |
| D-22 | The daemon is a bash script, not a compiled or Python program | **Rationale not stated in the repo.** The code uses bash and sysfs throughout | `bin/gleipnir` |
| D-23 | The fork's `charge_control_limit` node is checked before Armada's node | **Rationale not stated in the repo.** The order is in the code | `bin/gleipnir:99-104` |
| D-24 | The clamp value for the fork node is 1000, and the detect threshold is 1000 | The fork node clamps to 1000 µA (`docs/evidence.md`, [src] MgeeeeK entry; `docs/how-it-works.md`, "Which node") | `bin/gleipnir:63`, `:101` |

## 2. Rejected or not-used alternatives

The repo names these alternatives and states why it did not take them, or the state of the evidence. It does not record other rejected designs.

| Alternative | Status in the repo | Source |
|---|---|---|
| Standard `charge_control_end_threshold` | Not used. The Thor's firmware reads back 0 and ignores a write of 80 | `docs/evidence.md` (2026-10-07) |
| AYN's Android `limit_capacity_charge` node and `usb_charge_now` | Not used. Those nodes exist in the Android kernel and not on Armada | `docs/evidence.md` [src] entry; `bin/gleipnir:13-14` |
| Valve's `steamos-manager` approach (standard threshold) | Not used. It is the standard method, proven only where firmware honours it, not on the Thor | `docs/evidence.md` [src] entry |
| Armada's own limiter | None shipped. Armada issue 363 was open on 2026-10-07 (repo-reported) | `docs/evidence.md` [src] entry |

## 3. Open items

These are the repo's own open questions and untested points. They are the items most likely to change the design.

| # | Item | Why it matters | Source |
|---|---|---|---|
| R-1 | Why charging did not resume after the 80 % clamp was released (the stuck state) | It is the only case in which a released limit did not bring charging back. Whether charging resumes below 77 % is untested | `docs/evidence.md` (2026-10-08 observation); `bin/gleipnir:401-411` (warning added) |
| R-2 | Whether the value survives a reboot or a power loss while clamped | Recovery depends on it; the daemon only undoes a clamp when it starts | `docs/safety.md` ("Failure modes") |
| R-3 | Whether a clamp of `0` behaves differently from a small non-zero value on this firmware | Changes the clamp value choice | `docs/evidence.md` ("Open questions") |
| R-4 | Whether the firmware resets the limit on plug and unplug | Affects the daemon's assumption that the saved value stays | `docs/evidence.md` ("Open questions") |
| R-5 | Which supply reports `online` during USB-C PD charging | The daemon never clamps if it reads the wrong supply; the test refuses and lists the supplies | `docs/evidence.md` ("Open questions"); `bin/gleipnir:284` |
| R-6 | The cancel path: whether SIGINT restores and ends the test, given the trap at `bin/gleipnir:311` | Suspected from reading that the test continues after a restore; not run | application spec `06-limitations-glossary.md`, L14; design 04, section 5.7 |
| R-7 | The sleep unit's `ExecStop` order on resume | The adoption and post-sleep path depend on the unit running `--post-sleep` at wake | `systemd/gleipnir-sleep.service`; `docs/evidence.md` (device sessions, repo-reported) |
| R-8 | Reconcile the test totals and the backend check count | The documents give 47, 61, 67, 86, 97, 102 for the daemon suite and 8 for the backend; the file has nine backend test functions | `docs/testing.md`; `CHANGELOG.md`; `tests/test_backend.py` |
| R-9 | Document `--debug`, `sleep_floor` and `sleep_mode` in `docs/cli.md`, and the missing environment variables in `docs/testing.md` | Documentation differences D1 to D4 in the application spec | application spec `06-limitations-glossary.md` section 3 |
| R-10 | Correct the sign statement in `docs/troubleshooting.md` | D9 in the application spec: the watchdog reads the signed current | `docs/troubleshooting.md`; `bin/gleipnir:450` |
| R-11 | Confirm that `act()` in the panel surfaces file-copy errors from install | The backend does not catch them | `main.py:120-131`; `dist/index.js:71-81` |
| R-12 | A test for the panel (`dist/index.js`) | No test file covers it | `tests/` |
| R-13 | The daemon's behaviour when a plugin upgrade restarts it while clamped | The backend restarts the daemon on a changed script or unit; the release and re-clamp path is not analysed in the repo | `main.py:66-83`; `systemd/gleipnir.service` |

The repo's own roadmap is limited to these open items and to the debug build in `CHANGELOG.md` (Unreleased). No other future work is recorded in the repo at this commit. **Unverified:** whether any other plan exists outside the repo.
