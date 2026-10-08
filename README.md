# Gleipnir

A [Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader) plugin for the **AYN Thor** on **Armada OS** that holds the battery at **80 %** while plugged in, to slow battery wear. Named for the thin ribbon that bound Fenrir: a small thing that restrains a large force.

> **Status: unproven on a real Thor battery.** Nobody has shown that the Thor's firmware stops charging when the control below is written. Gleipnir installs in **watch-only** mode and does nothing to charging until its built-in measured test passes on your kernel. Read [docs/evidence.md](docs/evidence.md) for what is and is not known. Not affiliated with AYN or Armada.

## What it does
- Watches the battery. When the Thor is plugged in at 80 % or more it sets the battery manager's charge current limit to the "stop charging" value; when you unplug it, or the level falls to 77 %, it puts back the value it found.
- Ships a **safety test** (about 40 s) that proves, on your Thor, that the limit stops charging and that charging resumes after release. Only a pass arms the daemon, and the pass is tied to your kernel version.
- Logs every decision to the journal with a battery snapshot, runs a watchdog for a limit that does nothing, and restores the limit on every exit path.

## Requirements
An AYN Thor on Armada OS with Decky Loader, a kernel that exposes `constant_charge_current` (Armada's does; the surveyed build `20261006.9c7dd3e` has it), SSH key access to the Thor and `sudo` there for the one-time install. Python 3 and bash are already on the Thor.

## Install
```bash
git clone https://github.com/venatrix-ritz/Gleipnir && cd Gleipnir
./scripts/deploy.sh armada@<thor-ip>      # or set THOR_HOST / local/thor.env; needs SSH keys and sudo on the Thor
```
Then in Game Mode: Steam menu, Decky, **Gleipnir**, **Install daemon**; plug in the charger (battery between 10 and 90 %), **Run test**. After a PASS the daemon arms itself within 30 seconds. What each message means, and how to uninstall: [docs/troubleshooting.md](docs/troubleshooting.md).

If anything ever looks wrong, restore normal charging with:
```bash
sudo systemctl stop gleipnir && echo 9000000 | sudo tee /sys/class/power_supply/battery/constant_charge_current
```

## Documentation
| Page | What is in it |
|---|---|
| [How it works](docs/how-it-works.md) | the control it uses, the daemon loop and thresholds, the verification marker |
| [Safety](docs/safety.md) | the rules it follows, failure modes, recovery, what is not guaranteed, security notes |
| [Testing](docs/testing.md) | the on-device test step by step, the simulated suites, recorded results |
| [Command-line reference](docs/cli.md) | every mode, exit codes, JSON status, files |
| [Evidence](docs/evidence.md) | observed values and sources, with the open questions |
| [Troubleshooting](docs/troubleshooting.md) | what each message means and what to do |
| [Changelog](CHANGELOG.md) · [Credits](CREDITS.md) | history; who this builds on |

## Files
| Path | What |
|---|---|
| `main.py`, `plugin.json` (`flags: ["root"]`), `dist/index.js` | the Decky plugin: installs, starts, stops and tests the daemon; shows status and log. Root, like Armada's own privileged plugins |
| `bin/gleipnir` | the daemon, status report, safety test and restore command in one script |
| `systemd/gleipnir.service` | the unit |
| `tests/` | `run-tests.sh` (daemon against a simulated battery) and `test_backend.py` (plugin backend) |

## Credits and licence
Adapted from MgeeeeK's `thor-charge-limit`; see [CREDITS.md](CREDITS.md). MIT for the plugin ([LICENSE](LICENSE)); `bin/gleipnir` is GPL-2.0-or-later (SPDX header in the file, terms in `LICENSES/GPL-2.0.txt`).
