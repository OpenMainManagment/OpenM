"""Launch the Windows development script with local PostgreSQL settings."""

import os
from pathlib import Path
import subprocess
import sys

from dotenv import dotenv_values


DATABASE_SETTINGS = (
    "OPENM_DATABASE_URL",
    "OPENM_DB_HOST",
    "OPENM_DB_PORT",
    "OPENM_DB_NAME",
    "OPENM_DB_USER",
    "OPENM_DB_PASSWORD",
)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    env = os.environ.copy()
    env_file = root / "deploy" / ".env"
    if env_file.is_file():
        settings = dotenv_values(env_file)
        for key in DATABASE_SETTINGS:
            value = settings.get(key)
            if value is not None and key not in env:
                env[key] = value
    return subprocess.call(
        [env["COMSPEC"], "/d", "/c", str(root / "start_openm.bat"), "--with-env"],
        env=env,
    )


if __name__ == "__main__":
    sys.exit(main())
