"""Report tables or columns missing from the configured PostgreSQL database."""

from sqlalchemy import inspect

from app import models  # noqa: F401
from app.database import Base, engine


def main() -> None:
    inspector = inspect(engine)
    existing_tables = set(inspector.get_table_names())
    any_issues = False

    for table in Base.metadata.tables.values():
        if table.name not in existing_tables:
            print(f"[MISSING TABLE] {table.name}")
            any_issues = True
            continue

        actual_columns = {
            column["name"] for column in inspector.get_columns(table.name)
        }
        missing_columns = {column.name for column in table.columns} - actual_columns
        if missing_columns:
            any_issues = True
            print(f"[TABLE] {table.name}")
            for column_name in sorted(missing_columns):
                print(f"    MISSING COLUMN: {column_name}")

    if not any_issues:
        print("No schema drift found.")
    else:
        print("Restart the backend to attempt adding missing columns.")


if __name__ == "__main__":
    main()
