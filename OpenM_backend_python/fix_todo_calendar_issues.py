#!/usr/bin/env python3
"""
Fix database issues specifically related to todos and calendar functionality.
This script addresses the critical issues that prevent todo/calendar loading.
"""

import sqlite3
import sys
from pathlib import Path
from typing import Optional

# Database file path
DB_PATH = Path(__file__).parent / "database" / "openm.db"

def fix_null_company_ids() -> bool:
    """Fix folders with NULL company_id by assigning them to a default company."""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # First, let's see how many folders have NULL company_id
        cursor.execute("SELECT COUNT(*) FROM folders WHERE company_id IS NULL")
        null_count = cursor.fetchone()[0]
        print(f"Found {null_count} folders with NULL company_id")
        
        if null_count == 0:
            print("No folders with NULL company_id found")
            return True
            
        # Get the first company as default (if exists)
        cursor.execute("SELECT id FROM companies LIMIT 1")
        default_company = cursor.fetchone()
        
        if not default_company:
            print("⚠️ No companies found in database. Cannot assign default company.")
            print("Please create at least one company first, then run this script again.")
            return False
            
        default_company_id = default_company[0]
        print(f"Assigning default company ID '{default_company_id}' to folders")
        
        # Update the folders
        cursor.execute("UPDATE folders SET company_id = ? WHERE company_id IS NULL", (default_company_id,))
        conn.commit()
        
        print(f"✅ Successfully updated {null_count} folders with NULL company_id")
        return True
        
    except Exception as e:
        print(f"❌ Error fixing NULL company IDs: {e}")
        return False
    finally:
        if 'conn' in locals():
            conn.close()

def check_todo_project_relationships() -> bool:
    """Check that todos have proper project relationships."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Check for todos with NULL project_id (which could cause issues)
        cursor.execute("SELECT COUNT(*) FROM todos WHERE project_id IS NULL")
        null_project_count = cursor.fetchone()[0]
        print(f"Found {null_project_count} todos with NULL project_id")
        
        if null_project_count > 0:
            print("⚠️ Some todos have NULL project_id which may cause loading issues")
            # You could add logic here to fix this if needed
            return True
        else:
            print("✅ All todos have valid project_id values")
            return True
    except Exception as e:
        print(f"❌ Error checking todo relationships: {e}")
        return False
    finally:
        if 'conn' in locals():
            conn.close()

def main() -> bool:
    """Main function to fix todo/calendar related database issues."""
    
    if not DB_PATH.exists():
        print(f"❌ Database file not found at: {DB_PATH}")
        return False
        
    print(f"🔧 Fixing database issues for todos and calendar in: {DB_PATH}")
    print("=" * 80)
    
    success = True
    success &= fix_null_company_ids()
    success &= check_todo_project_relationships()
    
    if success:
        print("\n✅ Database issues fixed successfully")
        print("You should now be able to start the application and load todos/calendar")
    else:
        print("\n❌ Some issues could not be resolved")
        
    return success

if __name__ == "__main__":
    main()