#!/usr/bin/env python3
"""
Fix database issues with NULL company_id values in folders.

This script addresses the issue where 53 folders have NULL company_id values,
which is causing critical problems in the application.

The script provides two options:
1. Remove folders with NULL company_id (safest but data loss)
2. Assign them to a default company (preserves data)

Usage:
    python fix_database_issues.py --option remove
    python fix_database_issues.py --option assign-default
    
By default, it will show what would happen without making changes.
"""

import sqlite3
import sys
from pathlib import Path
from typing import Optional

# Database file path
DB_PATH = Path(__file__).parent / "database" / "openm.db"

def get_default_company_id(conn) -> Optional[str]:
    """Get the ID of the first company in the database, or None if no companies exist."""
    cursor = conn.cursor()
    
    try:
        cursor.execute("SELECT id FROM companies LIMIT 1")
        result = cursor.fetchone()
        return result[0] if result else None
    except Exception as e:
        print(f"Error getting default company: {e}")
        return None

def check_null_folders(conn) -> int:
    """Check how many folders have NULL company_id."""
    cursor = conn.cursor()
    
    try:
        cursor.execute("SELECT COUNT(*) FROM folders WHERE company_id IS NULL")
        count = cursor.fetchone()[0]
        return count
    except Exception as e:
        print(f"Error counting NULL folders: {e}")
        return 0

def list_null_folders(conn) -> list:
    """List all folders with NULL company_id."""
    cursor = conn.cursor()
    
    try:
        cursor.execute("SELECT id, name, project_id FROM folders WHERE company_id IS NULL")
        return cursor.fetchall()
    except Exception as e:
        print(f"Error listing NULL folders: {e}")
        return []

def remove_null_folders(conn) -> int:
    """Remove all folders with NULL company_id."""
    cursor = conn.cursor()
    
    try:
        # Get count before deletion
        count = check_null_folders(conn)
        
        if count == 0:
            print("No folders with NULL company_id to remove")
            return 0
            
        # Delete the folders
        cursor.execute("DELETE FROM folders WHERE company_id IS NULL")
        conn.commit()
        print(f"Removed {count} folders with NULL company_id")
        return count
    except Exception as e:
        print(f"Error removing NULL folders: {e}")
        conn.rollback()
        return 0

def assign_default_company_to_null_folders(conn, default_company_id: str) -> int:
    """Assign the default company ID to all folders with NULL company_id."""
    cursor = conn.cursor()
    
    try:
        # Get count before update
        count = check_null_folders(conn)
        
        if count == 0:
            print("No folders with NULL company_id to update")
            return 0
            
        # Update the folders
        cursor.execute("UPDATE folders SET company_id = ? WHERE company_id IS NULL", (default_company_id,))
        conn.commit()
        print(f"Assigned default company ID '{default_company_id}' to {count} folders with NULL company_id")
        return count
    except Exception as e:
        print(f"Error updating folders: {e}")
        conn.rollback()
        return 0

def main(option: str = "dry-run"):
    """Main function to handle database fixing."""
    
    if not DB_PATH.exists():
        print(f"❌ Database file not found at: {DB_PATH}")
        sys.exit(1)
        
    print(f"🔧 Fixing database issues in: {DB_PATH}")
    print("=" * 80)
    
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        
        # Check for NULL company_id folders
        null_count = check_null_folders(conn)
        
        if null_count == 0:
            print("✅ No folders with NULL company_id found. Database is clean.")
            return
            
        print(f"⚠️ Found {null_count} folders with NULL company_id")
        
        # List the problematic folders
        null_folders = list_null_folders(conn)
        print("\nFolders with NULL company_id:")
        for folder in null_folders:
            print(f"  ID: {folder['id']}, Name: {folder['name']}, Project ID: {folder['project_id']}")
        
        # Get default company
        default_company_id = get_default_company_id(conn)
        
        if not default_company_id:
            print("⚠️ No companies found in database. Cannot assign default company.")
            print("Option 1: Remove folders (data loss)")
            print("Option 2: Manual intervention required")
            return
            
        print(f"\nDefault company ID: {default_company_id}")
        
        if option == "remove":
            print("\n🔧 Removing folders with NULL company_id...")
            removed_count = remove_null_folders(conn)
            print(f"✅ Removed {removed_count} folders successfully")
            
        elif option == "assign-default":
            print("\n🔧 Assigning default company to folders with NULL company_id...")
            assigned_count = assign_default_company_to_null_folders(conn, default_company_id)
            print(f"✅ Assigned default company to {assigned_count} folders successfully")
            
        else:  # dry-run
            print("\n📋 Dry run - no changes made")
            print("To actually fix the issue, use:")
            print("  python fix_database_issues.py --option remove")
            print("  python fix_database_issues.py --option assign-default")
            
    except Exception as e:
        print(f"❌ Error during database operation: {e}")
        sys.exit(1)
        
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    # Parse command line arguments
    import argparse
    
    parser = argparse.ArgumentParser(description="Fix NULL company_id issues in folders")
    parser.add_argument("--option", choices=["remove", "assign-default"], 
                       default="dry-run",
                       help="Fix option: remove or assign default company")
    
    args = parser.parse_args()
    
    main(args.option)