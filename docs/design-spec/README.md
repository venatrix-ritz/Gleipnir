# Gleipnir Design Spec

How Gleipnir works: the modules, the control algorithms with their parameters, the data flow and interfaces, error handling and the operating-system constraints, and the reasons behind the main decisions. Companion to the [application spec](../application-spec/README.md). Written from a read of the repository at commit `14ce5ec` (main, 2026-10-15). Line anchors are to `bin/gleipnir`, `main.py`, `dist/index.js` and the other tracked files; they may drift as the code changes. Anything not traced in the code, or taken from a repo document without re-observation, is marked **unverified** or **repo-reported**.

| # | File | Topic |
|---|---|---|
| 01 | [architecture-modules.md](01-architecture-modules.md) | The three runtime parts, the line map of the daemon script, who may write the limit node |
| 02 | [algorithms.md](02-algorithms.md) | Control loop, write-and-judge, release with hold, watchdog, test, sleep hooks, marker, kernel detection |
| 03 | [data-flow-interfaces.md](03-data-flow-interfaces.md) | Mermaid data-flow and sequence diagrams; sysfs, file, JSON, RPC and journal interfaces |
| 04 | [error-handling-os-constraints.md](04-error-handling-os-constraints.md) | Failure handling, exit codes, recovery, and the operating-system constraints the design depends on |
| 05 | [design-decisions-roadmap.md](05-design-decisions-roadmap.md) | The decisions and their stated reasons, the rejected alternatives the repo names, and the open items |

**Core design in one paragraph.** A single bash script (`bin/gleipnir`) runs as root under systemd. It writes one of two charge-current limit nodes and only after a supervised test has proved, on the running kernel, that the node stops charging and that charging resumes after restore. While it runs it never trusts a write until the node shows it, always puts back the value it found, and exits visibly (code 78) on any condition it cannot correct. A Decky Loader backend in Python and a panel in JavaScript only install, start, stop, test and display; they never write the limit node themselves (`main.py:1-10`).
