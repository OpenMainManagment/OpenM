"""Standalone diagnostic: checks the real openm.db file for any columns that
the current models.py expects but the database table doesn't actually have.

Run this from the OpenM_backend folder with your venv active:

    python diagnose_schema.py

It does NOT modify anything - it only reports what's missing.
"""

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent / "database" / "openm.db"

# Import the real models so we check against exactly what the app expects.
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from app.database import Base  # noqa: E402
from app import models  # noqa: E402  (ensures all models are registered on Base)


def main() -> None:
    if not DB_PATH.is_file():
        print(f"No database file found at: {DB_PATH}")
        print("(the app will create one on next startup)")
        return

    print(f"Checking: {DB_PATH}\n")
    conn = sqlite3.connect(str(DB_PATH))
    cur = conn.cursor()

    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    existing_tables = {row[0] for row in cur.fetchall()}

    any_issues = False
    for table in Base.metadata.tables.values():
        if table.name not in existing_tables:
            print(f"[MISSING TABLE] {table.name} does not exist in the database at all.")
            any_issues = True
            continue

        cur.execute(f'PRAGMA table_info("{table.name}")')
        actual_columns = {row[1] for row in cur.fetchall()}
        expected_columns = {col.name for col in table.columns}
        missing = expected_columns - actual_columns

        if missing:
            any_issues = True
            print(f"[TABLE] {table.name}")
            for col_name in sorted(missing):
                print(f"    MISSING COLUMN: {col_name}")

    conn.close()

    if not any_issues:
        print("No schema drift found — every table/column the models expect is present.")
        print("If /todos is still failing, the problem is something else (check the")
        print("backend terminal for a traceback the next time you hit the endpoint).")
    else:
        print("\nFound the issues above. Restarting the backend should auto-fix them")
        print("(main.py's _sync_missing_columns runs on every startup). If a column")
        print("still shows as missing after a restart, check the startup log for a")
        print("line like '[startup] Could not auto-add column ...' explaining why.")


if __name__ == "__main__":
    main()
