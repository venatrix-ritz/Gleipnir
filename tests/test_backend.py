"""Backend tests with a fake command runner and temp paths. Run: python tests/test_backend.py"""
import asyncio
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import main as m  # noqa: E402

CALLS = []


def fake_run_factory(script_json=None, active="inactive", enabled="disabled"):
    def fake_run(cmd, timeout=20.0):
        CALLS.append(list(cmd))
        if cmd[-2:] == ["--status", "--json"]:
            return 0, json.dumps(script_json or {"verified": False, "capacity": 70})
        if cmd[0] == m.SYSTEMCTL and cmd[1] == "is-active":
            return 0, active
        if cmd[0] == m.SYSTEMCTL and cmd[1] == "is-enabled":
            return 0, enabled
        if cmd[0] == m.JOURNALCTL:
            return 0, "\n".join(f"line {i}" for i in range(500))
        return 0, ""
    return fake_run


def setup(tmp: Path):
    (tmp / "bin").mkdir(); (tmp / "systemd").mkdir(); (tmp / "dst").mkdir(); (tmp / "state").mkdir()
    (tmp / "bin" / "gleipnir").write_text("#!/bin/sh\nexit 0\n")
    (tmp / "systemd" / "gleipnir.service").write_text("[Service]\n")
    m.BIN_SRC, m.UNIT_SRC = tmp / "bin" / "gleipnir", tmp / "systemd" / "gleipnir.service"
    m.BIN_DST, m.UNIT_DST = tmp / "dst" / "gleipnir", tmp / "dst" / "gleipnir.service"
    m.STATE_DIR = tmp / "state"; m.TEST_OUT = m.STATE_DIR / "ui-test.out"
    CALLS.clear()


def cmds():
    return [" ".join(c[1:]) if c[0] == m.SYSTEMCTL else c[0] for c in CALLS]


def test_install_then_status():
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d); setup(tmp); m._run = fake_run_factory(active="active", enabled="enabled")
        st = asyncio.run(m.Plugin().install())
        assert m.BIN_DST.exists() and m.UNIT_DST.exists()
        if os.name == "posix":
            assert oct(m.BIN_DST.stat().st_mode & 0o777) == "0o755"
        assert cmds()[:2] == ["daemon-reload", "enable --now gleipnir.service"], cmds()
        assert st["installed"] and st["active"] == "active" and st["daemon"]["capacity"] == 70


def test_status_survives_bad_json():
    with tempfile.TemporaryDirectory() as d:
        setup(Path(d))
        m._run = lambda cmd, timeout=20.0: (0, "not json") if cmd[-1] == "--json" else (0, "inactive")
        st = asyncio.run(m.Plugin().get_status())
        assert st["error"] and st["daemon"] == {} and not st["installed"]


def test_disable_restores_and_stops():
    with tempfile.TemporaryDirectory() as d:
        setup(Path(d)); m._run = fake_run_factory(); asyncio.run(m.Plugin().install()); CALLS.clear()
        asyncio.run(m.Plugin().set_enabled(False))
        assert cmds()[0] == "disable --now gleipnir.service"
        assert any(c[-1] == "--restore" for c in CALLS), CALLS


def test_uninstall_removes_files_and_marker():
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d); setup(tmp); m._run = fake_run_factory(); asyncio.run(m.Plugin().install())
        (m.STATE_DIR / "verified").write_text("node=x\n")
        asyncio.run(m.Plugin().uninstall())
        assert not m.BIN_DST.exists() and not m.UNIT_DST.exists() and not (m.STATE_DIR / "verified").exists()
        assert cmds().index("disable --now gleipnir.service") < len(cmds())


def test_log_lines_are_clamped():
    with tempfile.TemporaryDirectory() as d:
        setup(Path(d)); m._run = fake_run_factory()
        out = asyncio.run(m.Plugin().get_log(10_000))
        assert len(out["lines"]) == 200
        assert asyncio.run(m.Plugin().get_log(-5))["lines"] == ["line 499"]


def test_verdicts():
    assert m._verdict("x\nPASS. Marker written") == "pass"
    assert m._verdict("FAIL. No marker") == "fail"
    assert m._verdict("ABORTED: charger was unplugged.") == "aborted"
    assert m._verdict("Refusing: status is 'Discharging'") == "refused"
    assert m._verdict("nothing useful") == ""


def test_test_run_stops_and_restarts_daemon():
    async def go(tmp: Path):
        script = tmp / "bin" / "gleipnir"
        script.write_text("#!/bin/sh\necho '-- baseline'\necho 'PASS. Marker written'\nexit 0\n"); os.chmod(script, 0o755)
        m.BIN_DST = script  # run the fake script directly
        plugin = m.Plugin()
        started = await plugin.start_test()
        assert started["running"]
        again = await plugin.start_test()          # second request while running does not start another
        assert again["running"] and CALLS.count([m.SYSTEMCTL, "stop", m.SERVICE]) == 1
        await plugin._test_task
        res = await plugin.get_test()
        assert not res["running"] and res["rc"] == 0 and res["verdict"] == "pass", res
        assert any("PASS" in line for line in res["tail"])
        assert cmds().index("stop gleipnir.service") < cmds().index("start gleipnir.service")
    if os.name != "posix":
        print("skip test_test_run_stops_and_restarts_daemon (needs a POSIX shell script)"); return
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d); setup(tmp); m._run = fake_run_factory(active="active"); asyncio.run(go(tmp))


def test_failed_test_start_puts_the_daemon_back():
    async def go(tmp: Path):
        m.BIN_DST = tmp / "no-such-script"     # exec fails: the daemon must not be left stopped
        m.BIN_SRC = tmp / "no-such-script"
        plugin = m.Plugin()
        res = await plugin.start_test()
        assert not res["running"] and res["verdict"] == "refused", res
        assert cmds().index("stop gleipnir.service") < cmds().index("start gleipnir.service"), cmds()
        assert "Could not start the test" in (await plugin.get_test())["tail"][0]
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d); setup(tmp); m._run = fake_run_factory(active="active"); asyncio.run(go(tmp))


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn(); print("ok", name)
