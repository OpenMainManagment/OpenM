import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import launch_local


def test_local_database_settings_and_environment_precedence(tmp_path, monkeypatch):
    backend = tmp_path / "OpenM_backend_python"
    backend.mkdir()
    deploy = tmp_path / "deploy"
    deploy.mkdir()
    (deploy / ".env").write_text(
        "OPENM_DB_NAME=from_file\nOPENM_DB_PASSWORD=file_password\n"
        "OPENM_SECRET_KEY=not_loaded\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(launch_local, "__file__", str(backend / "launch_local.py"))
    monkeypatch.setenv("COMSPEC", "cmd.exe")
    monkeypatch.setenv("OPENM_DB_NAME", "from_environment")
    monkeypatch.delenv("OPENM_DB_PASSWORD", raising=False)
    monkeypatch.delenv("OPENM_SECRET_KEY", raising=False)
    captured = {}

    def fake_call(args, *, env):
        captured.update(args=args, env=env)
        return 7

    monkeypatch.setattr(launch_local.subprocess, "call", fake_call)
    assert launch_local.main() == 7
    assert captured["args"][-1] == "--with-env"
    assert captured["env"]["OPENM_DB_NAME"] == "from_environment"
    assert captured["env"]["OPENM_DB_PASSWORD"] == "file_password"
    assert "OPENM_SECRET_KEY" not in captured["env"]
    assert "OPENM_DB_PASSWORD" not in os.environ
