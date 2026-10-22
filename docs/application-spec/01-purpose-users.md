# 01 - Purpose, users and workflows

## Purpose
Gleipnir keeps an AYN Thor's battery from being held at 100 % while the charger is attached. When the Thor is plugged in and the charge is at or above 80 %, the daemon writes the "stop charging" value to the battery manager's charge-current limit. When the Thor is unplugged, or the charge falls to 77 %, it puts back the value it found. Source: `bin/gleipnir:61-62` (`TARGET=80`, `RELEASE_AT=77`), `bin/gleipnir:437` and `:445-446`, `README.md` ("What it does").

The stated reason is slower battery wear (`README.md`, the first paragraph of "What it does"; `docs/how-it-works.md`, "The idea"). The repo does not measure wear, so the wear benefit is **unverified** here.

## Scope

In scope (all in the repository):
- The root daemon `bin/gleipnir`: the control loop, a status report, a supervised safety test, a restore command, a sleep-setting command, and two sleep hooks (`bin/gleipnir:198-352`).
- The Decky Loader plugin: backend `main.py` (Python, runs as root per `plugin.json` `"flags": ["root"]`) and front end `dist/index.js` (the panel).
- The systemd units `systemd/gleipnir.service` and `systemd/gleipnir-sleep.service`.
- The deploy script `scripts/deploy.sh`.
- The simulated test suites in `tests/`.

Out of scope (stated by the repo):
- Any other battery control, including the standard `charge_control_end_threshold`, which the repo says the Thor ignores (`docs/evidence.md`, "About the control", 2026-10-07 observation).
- Cloud, network or remote control. The daemon takes no network input (`docs/safety.md`, "Security").
- Armada Control's own sleep-type setting, which the plugin reads but does not change (`dist/index.js` "Sleep type" row; `bin/gleipnir:168-171`).
- Other devices. The README says the project is not affiliated with AYN or Armada.

## Users

| User | Needs | Uses |
|---|---|---|
| Ven (author and maintainer, per `CREDITS.md` and `LICENSE`) | A cap on charge for their own Thor; a safe way to prove the limit works | Deploy script, Decky panel, `gleipnir --test`, journal |
| Another AYN Thor owner on Armada OS with Decky Loader | Install a battery cap without editing system files | Decky panel (install, test, sleep setting, log, restore, uninstall) |
| A person recovering a Thor that will not charge | Put normal charging back | `docs/safety.md` "Recovery by hand"; `gleipnir --restore`; the panel's "Restore normal charging now" button |

The README asks for "an AYN Thor on Armada OS with Decky Loader" and SSH and sudo for the one-time install (`README.md`, "Requirements").

## Workflows

1. **Install from a clone.** `./scripts/deploy.sh <host>` copies the files to `/home/armada/homebrew/plugins/gleipnir` on the Thor and restarts `plugin_loader.service` (`scripts/deploy.sh:4-28`). Needs SSH key access and sudo on the Thor (`README.md`, "Install").
2. **Install the daemon in the panel.** Steam menu, Decky, Gleipnir, "Install daemon". This copies the script, the unit and the sleep unit into place and starts the daemon (`main.py:120-131`, `dist/index.js` "Install daemon" button). The daemon then only watches (`dist/index.js` line 36 text: "Watching only: not verified yet").
3. **Run the safety test.** Plug in the charger, keep the battery between 10 and 90 %, press "Run test" (`dist/index.js:153-159`). The panel stops the daemon for the test and restarts it afterwards (`main.py:188-209`). The test refuses on a bad precondition and writes nothing (`bin/gleipnir:281-297`).
4. **Arming.** A PASS writes the verification marker. The running daemon re-reads it every poll and arms within one poll (`bin/gleipnir:425-433`; the test's own message at `bin/gleipnir:347`).
5. **Everyday use.** The daemon clamps at 80 % while plugged in, and releases when unplugged or at 77 % (`bin/gleipnir:435-459`). The heartbeat and the decision log go to the journal (`bin/gleipnir:393`, `:493-495`).
6. **Sleep.** With the sleep setting (default 0) the pre-sleep hook clamps just before a suspend, and the post-sleep hook releases after resume (`bin/gleipnir:222-254`, `systemd/gleipnir-sleep.service`).
7. **Stop or uninstall.** Disabling the daemon in the panel disables the sleep unit and the daemon, then runs `--restore` (`main.py:137-151`). Uninstall also removes the unit files, the script and the marker (`main.py:153-164`).
8. **Read the log.** The panel's "Show recent log" button runs `journalctl -t gleipnir -n 15` (`main.py:243-248`, `dist/index.js:84-91`).

## What a user is told (summary)
The panel's wording for each state is in `dist/index.js:32-38` ("Not installed", "Stopped (charging is not limited)", "Watching only: not verified yet. Run the test below.", "Armed: holding the battery at 80%", "Armed: will hold the battery at 80%"). The "holding" wording is chosen when the reported limit is 1000 or less (`dist/index.js:37`), which is an inference from the clamp value, not a direct read of clamp state.
