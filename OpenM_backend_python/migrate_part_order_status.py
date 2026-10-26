#!/usr/bin/env python3
"""
One-off migration for the part order status rework:
- adds the shipping_number column to project_order_items
- remaps the old order_status values to the new status vocabulary
  (In Progress, Quotation, Purchasing, Ordered, Delivery, In Stock, Loaded, Installed)
"""

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "database" / "openm.db"

STATUS_MAP = {
    "NOT_ORDERED": "IN_PROGRESS",
    "ORDERED": "ORDERED",
    "SHIPPED": "DELIVERY",
    "DELAYED": "DELIVERY",
    "DELIVERED": "IN_STOCK",
    "CANCELLED": "IN_PROGRESS",
}


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()

        cursor.execute("PRAGMA table_info(project_order_items)")
        columns = {row[1] for row in cursor.fetchall()}
        if "shipping_number" not in columns:
            cursor.execute(
                "ALTER TABLE project_order_items ADD COLUMN shipping_number VARCHAR(120)"
            )
            print("Added shipping_number column")
        else:
            print("shipping_number column already present")

        for old_value, new_value in STATUS_MAP.items():
            cursor.execute(
                "UPDATE project_order_items SET order_status = ? WHERE order_status = ?",
                (new_value, old_value),
            )
            if cursor.rowcount:
                print(f"Remapped {cursor.rowcount} rows from '{old_value}' to '{new_value}'")

        conn.commit()
        print("Migration complete")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
