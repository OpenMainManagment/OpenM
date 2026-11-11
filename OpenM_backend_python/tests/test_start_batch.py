import os
from pathlib import Path
import shutil
import subprocess

import pytest


@pytest.mark.skipif(os.name != "nt", reason="Windows batch script")
@pytest.mark.parametrize(
    ("backend", "frontend", "expected"),
    [
        (False, True, "Backend folder not found:"),
        (True, False, "Frontend folder not found:"),
        (True, True, "Python virtual environment not found:"),
    ],
)
def test_start_uses_only_exact_source_directories(tmp_path, backend, frontend, expected):
    root = tmp_path / "OpenM with spaces"
    root.mkdir()
    script = Path(__file__).resolve().parents[2] / "start_openm.bat"
    shutil.copyfile(script, root / "start_openm.bat")
    (root / "other_backend").mkdir()
    (root / "other_frontend").mkdir()
    if backend:
        (root / "OpenM_backend_python").mkdir()
    if frontend:
        (root / "OpenM_frontend_flutter").mkdir()

    env = os.environ.copy()
    env["BACKEND_DIR"] = str(root / "other_backend")
    env["FRONTEND_DIR"] = str(root / "other_frontend")
    result = subprocess.run(
        [env["COMSPEC"], "/d", "/c", str(root / "start_openm.bat")],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )
    assert result.returncode == 1
    assert expected in result.stdout
