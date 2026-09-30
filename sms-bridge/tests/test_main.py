from types import SimpleNamespace

import pytest

from sms_bridge import __main__


def test_runner_returns_stdout(monkeypatch):
    monkeypatch.setattr(
        __main__.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout="ok", stderr=""),
    )

    assert __main__.runner(["mmcli", "-m", "any"]) == "ok"


def test_runner_raises_with_stderr_when_command_fails(monkeypatch):
    monkeypatch.setattr(
        __main__.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(
            returncode=1,
            stdout="",
            stderr="ModemManager unavailable",
        ),
    )

    with pytest.raises(RuntimeError, match="ModemManager unavailable"):
        __main__.runner(["mmcli", "-m", "any"])
