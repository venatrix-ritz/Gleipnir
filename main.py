"""Gleipnir: Decky backend for the Thor's 80 % battery ceiling.

Runs as root (plugin.json flags ["root"], the same flag Armada's own privileged plugins use). All it does is install,
start, stop and test the `gleipnir` daemon (bin/gleipnir) and report on it; the charging logic and its safety rules live
in that script. Nothing here writes the battery limit directly.
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parent
BIN_SRC = PLUGIN_DIR / "bin" / "gleipnir"
UNIT_SRC = PLUGIN_DIR / "systemd" / "gleipnir.service"
SLEEP_UNIT_SRC = PLUGIN_DIR / "systemd" / "gleipnir-sleep.service"
BIN_DST = Path("/var/local/bin/gleipnir")
UNIT_DST = Path("/etc/systemd/system/gleipnir.service")
SLEEP_UNIT_DST = Path("/etc/systemd/system/gleipnir-sleep.service")
STATE_DIR = Path("/var/lib/gleipnir")
SERVICE = "gleipnir.service"
SLEEP_SERVICE = "gleipnir-sleep.service"
TEST_OUT = STATE_DIR / "ui-test.out"
SYSTEMCTL = "systemctl"
JOURNALCTL = "journalctl"


def _run(cmd: list[str], timeout: float = 20.0) -> tuple[int, str]:
    """Run a command (never through a shell). Returns (exit status, combined output); 127 if it is missing."""
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        return res.returncode, (res.stdout or "") + (res.stderr or "")
    except FileNotFoundError:
        return 127, f"{cmd[0]}: not found"
    except subprocess.TimeoutExpired:
        return 124, f"{' '.join(cmd)}: timed out after {timeout}s"


def _verdict(text: str) -> str:
    """Reduce the test script's output to one word the UI can show."""
    for line in reversed(text.splitlines()):
        if line.startswith("PASS"):
            return "pass"
        if line.startswith("FAIL"):
            return "fail"
        if line.startswith("ABORTED"):
            return "aborted"
        if line.startswith("Refusing") or line.startswith("Run as root"):
            return "refused"
    return ""


class Plugin:
    def __init__(self) -> None:
        self._test: dict = {"running": False, "started": 0.0, "finished": 0.0, "rc": None, "verdict": ""}
        self._proc: asyncio.subprocess.Process | None = None
        self._test_task: asyncio.Task | None = None

    async def _main(self) -> None:
        """Called by Decky on load. Does nothing to charging: the daemon is only installed when asked."""

    # -- status ---------------------------------------------------------------------------------------------
    def _installed(self) -> bool:
        return BIN_DST.exists() and UNIT_DST.exists()

    def _status_sync(self) -> dict:
        script = BIN_DST if BIN_DST.exists() else BIN_SRC
        rc, out = _run([str(script), "--status", "--json"], timeout=10)
        daemon: dict = {}
        error = ""
        if rc == 0:
            try:
                daemon = json.loads(out)
            except ValueError:
                error = "status output was not JSON"
        else:
            error = out.strip().splitlines()[-1] if out.strip() else f"status exited {rc}"
        _, active = _run([SYSTEMCTL, "is-active", SERVICE], timeout=5)
        _, enabled = _run([SYSTEMCTL, "is-enabled", SERVICE], timeout=5)
        return {
            "installed": self._installed(),
            "active": active.strip(),
            "enabled": enabled.strip(),
            "daemon": daemon,
            "error": error,
            "test": dict(self._test),
        }

    async def get_status(self) -> dict:
        return await asyncio.to_thread(self._status_sync)

    # -- install / enable -----------------------------------------------------------------------------------
    def _install_sync(self) -> dict:
        BIN_DST.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(BIN_SRC, BIN_DST)
        os.chmod(BIN_DST, 0o755)
        shutil.copyfile(UNIT_SRC, UNIT_DST)
        os.chmod(UNIT_DST, 0o644)
        shutil.copyfile(SLEEP_UNIT_SRC, SLEEP_UNIT_DST)
        os.chmod(SLEEP_UNIT_DST, 0o644)
        _run([SYSTEMCTL, "daemon-reload"])
        _run([SYSTEMCTL, "enable", "--now", SERVICE])
        _run([SYSTEMCTL, "enable", SLEEP_SERVICE])  # runs --pre-sleep before every suspend; it does nothing until a test has passed
        return self._status_sync()

    async def install(self) -> dict:
        """Copy the daemon and unit into place and start it. It only watches until a test has passed."""
        return await asyncio.to_thread(self._install_sync)

    def _set_enabled_sync(self, enabled: bool) -> dict:
        if enabled:
            if not self._installed():
                return self._install_sync()
            _run([SYSTEMCTL, "enable", "--now", SERVICE])
            _run([SYSTEMCTL, "enable", SLEEP_SERVICE])
            return self._status_sync()
        _run([SYSTEMCTL, "disable", SLEEP_SERVICE])
        _run([SYSTEMCTL, "disable", "--now", SERVICE])  # stopping releases any clamp
        if BIN_DST.exists():
            _run([str(BIN_DST), "--restore"], timeout=10)
        return self._status_sync()

    async def set_enabled(self, enabled: bool) -> dict:
        return await asyncio.to_thread(self._set_enabled_sync, bool(enabled))

    def _uninstall_sync(self) -> dict:
        _run([SYSTEMCTL, "disable", SLEEP_SERVICE])
        _run([SYSTEMCTL, "disable", "--now", SERVICE])
        if BIN_DST.exists():
            _run([str(BIN_DST), "--restore"], timeout=10)
        for path in (UNIT_DST, SLEEP_UNIT_DST, BIN_DST, STATE_DIR / "verified"):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        _run([SYSTEMCTL, "daemon-reload"])
        return self._status_sync()

    async def uninstall(self) -> dict:
        return await asyncio.to_thread(self._uninstall_sync)

    async def restore_now(self) -> dict:
        """Undo a leftover clamp immediately."""
        script = BIN_DST if BIN_DST.exists() else BIN_SRC
        rc, out = await asyncio.to_thread(_run, [str(script), "--restore"], 10)
        return {"ok": rc == 0, "output": out.strip()}

    # -- the supervised test --------------------------------------------------------------------------------
    async def start_test(self) -> dict:
        """Run `gleipnir --test --run`. The daemon is stopped for the duration (a clamp restores on stop) and
        restarted afterwards if it was running, so the two never fight over the limit."""
        if self._test["running"]:
            return dict(self._test)
        script = BIN_DST if BIN_DST.exists() else BIN_SRC
        was_active = (await asyncio.to_thread(_run, [SYSTEMCTL, "is-active", SERVICE], 5))[1].strip() == "active"
        if was_active:
            await asyncio.to_thread(_run, [SYSTEMCTL, "stop", SERVICE])
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        out = open(TEST_OUT, "w", encoding="utf-8")
        try:
            self._proc = await asyncio.create_subprocess_exec(
                str(script), "--test", "--run", stdout=out, stderr=subprocess.STDOUT)
        except OSError as err:
            out.close()
            if was_active:  # the test never started: put the daemon back
                await asyncio.to_thread(_run, [SYSTEMCTL, "start", SERVICE])
            self._test = {"running": False, "started": 0.0, "finished": time.time(), "rc": 127, "verdict": "refused"}
            TEST_OUT.write_text(f"Could not start the test: {err}\n", encoding="utf-8")
            return dict(self._test)
        self._test = {"running": True, "started": time.time(), "finished": 0.0, "rc": None, "verdict": ""}

        async def _finish() -> None:
            rc = await self._proc.wait()
            out.close()
            try:
                text = TEST_OUT.read_text(encoding="utf-8", errors="replace")
            except OSError:
                text = ""
            self._test = {"running": False, "started": self._test["started"], "finished": time.time(),
                          "rc": rc, "verdict": _verdict(text)}
            if was_active:
                await asyncio.to_thread(_run, [SYSTEMCTL, "start", SERVICE])

        self._test_task = asyncio.create_task(_finish())
        return dict(self._test)

    async def cancel_test(self) -> dict:
        """Interrupt a running test; the script restores the limit on SIGINT."""
        if self._proc is not None and self._test["running"]:
            try:
                self._proc.send_signal(signal.SIGINT)
            except ProcessLookupError:
                pass
        return dict(self._test)

    async def get_test(self) -> dict:
        try:
            lines = TEST_OUT.read_text(encoding="utf-8", errors="replace").splitlines()[-40:]
        except OSError:
            lines = []
        return {**self._test, "tail": lines}

    # -- logs -----------------------------------------------------------------------------------------------
    async def get_log(self, lines: int = 40) -> dict:
        n = max(1, min(200, int(lines)))
        rc, out = await asyncio.to_thread(_run, [JOURNALCTL, "-t", "gleipnir", "-n", str(n), "--no-pager", "-o", "short"], 10)
        return {"ok": rc == 0, "lines": out.splitlines()[-n:]}
