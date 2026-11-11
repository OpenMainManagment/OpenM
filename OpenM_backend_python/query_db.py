"""Inspect action buttons in the configured PostgreSQL database."""

from sqlalchemy import inspect, text

from app.database import engine


def main() -> None:
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    print("Connected to database successfully")
    print("\nTables in database:")
    for table_name in sorted(tables):
        print(f"  {table_name}")

    if "action_buttons" not in tables:
        print("\naction_buttons table not found")
        return

    columns = inspector.get_columns("action_buttons")
    print("\nColumns in action_buttons:")
    for column in columns:
        print(f"  {column['name']} ({column['type']})")

    if "company_id" not in {column["name"] for column in columns}:
        return

    with engine.connect() as connection:
        total = connection.execute(
            text("SELECT COUNT(*) FROM action_buttons")
        ).scalar_one()
        null_count = connection.execute(
            text("SELECT COUNT(*) FROM action_buttons WHERE company_id IS NULL")
        ).scalar_one()
        empty_count = connection.execute(
            text("SELECT COUNT(*) FROM action_buttons WHERE company_id = ''")
        ).scalar_one()
    print(f"\nTotal action buttons: {total}")
    print(f"Action buttons with NULL company_id: {null_count}")
    print(f"Action buttons with empty company_id: {empty_count}")


if __name__ == "__main__":
    main()
