#!/usr/bin/env python3
"""Direct SQLite query to check action_buttons table."""

import sqlite3
from pathlib import Path

# Database file path
db_path = Path(__file__).parent / "database" / "openm.db"

try:
    # Connect to the database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    print("Connected to database successfully")
    
    # Get table information
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = cursor.fetchall()
    print("\nTables in database:")
    for table in tables:
        print(f"  {table[0]}")
    
    # Check if action_buttons table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='action_buttons';")
    table_exists = cursor.fetchone()
    
    if table_exists:
        print("\nAction buttons table found!")
        
        # Get column information
        cursor.execute("PRAGMA table_info(action_buttons);")
        columns = cursor.fetchall()
        print("\nColumns in action_buttons table:")
        for col in columns:
            print(f"  {col[1]} ({col[2]}) - Nullable: {col[3]}, Primary Key: {col[5]}")
        
        # Count total records
        cursor.execute("SELECT COUNT(*) FROM action_buttons;")
        total_count = cursor.fetchone()[0]
        print(f"\nTotal action buttons: {total_count}")
        
        # Count NULL company_id records
        cursor.execute("SELECT COUNT(*) FROM action_buttons WHERE company_id IS NULL;")
        null_count = cursor.fetchone()[0]
        print(f"Action buttons with NULL company_id: {null_count}")
        
        # Count empty string company_id records  
        cursor.execute("SELECT COUNT(*) FROM action_buttons WHERE company_id = '';")
        empty_count = cursor.fetchone()[0]
        print(f"Action buttons with empty company_id: {empty_count}")
        
        # Show records with NULL or empty company_id
        cursor.execute("SELECT id, unique_name, company_id FROM action_buttons WHERE company_id IS NULL OR company_id = '';")
        null_or_empty_records = cursor.fetchall()
        
        if null_or_empty_records:
            print("\nRecords with NULL or empty company_id:")
            for record in null_or_empty_records:
                print(f"  ID: {record[0]}, Name: {record[1]}, Company ID: '{record[2]}'")
        else:
            print("\nNo records found with NULL or empty company_id")
            
    else:
        print("action_buttons table not found in database")
        
    conn.close()
    
except Exception as e:
    print(f"Error: {e}")