# Gleipnir Application Spec

What Gleipnir is, who it is for, what it does on an AYN Thor, how to drive it from the command line and the Decky panel, and what it does not do. Written from a read of the repository at commit `14ce5ec` (main, 2026-10-15). Every statement is anchored to `file:line` in the repo, or to a repo document (`docs/*.md`, `CHANGELOG.md`, `README.md`) and marked as such, or is marked **unverified**. Nothing here was run on a device or re-tested for this spec.

The companion [design spec](../design-spec/README.md) explains how each part works.

| # | File | Topic |
|---|---|---|
| 01 | [purpose-users.md](01-purpose-users.md) | What Gleipnir is for, who uses it, the workflows, what is out of scope |
| 02 | [features-hardware.md](02-features-hardware.md) | Feature list, hardware and kernel targets, what the panel shows |
| 03 | [cli.md](03-cli.md) | Every `bin/gleipnir` mode and flag, exit codes, the JSON status fields, files |
| 04 | [configuration.md](04-configuration.md) | Environment variables, paths, systemd units, install and deploy |
| 05 | [testing.md](05-testing.md) | The on-device safety test, the simulated suites, what each proves |
| 06 | [limitations-glossary.md](06-limitations-glossary.md) | Known limits, open questions, documentation-versus-code differences, glossary |

**Summary.** Gleipnir holds the Thor's battery at 80 % while the charger is attached. It does this by writing to the battery manager's charge-current limit, not by the standard charge-end threshold (which the Thor's firmware ignores, per `docs/evidence.md`). It does nothing to charging until a supervised on-device test has passed on the running kernel. Source: `README.md` (status section), `bin/gleipnir:1-15`, `bin/gleipnir:354-358`.
