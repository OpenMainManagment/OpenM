#!/usr/bin/env python3
"""Script to check action_buttons table for records with NULL or empty company_id."""

import sys
import os
from pathlib import Path

# Add the app directory to Python path
sys.path.insert(0, str(Path(__file__).resolve().parent / 'app'))

from database import engine, SessionLocal
from models import ActionButton

def check_action_buttons():
    """Check action_buttons table for records with NULL or empty company_id."""
    db = SessionLocal()
    
    try:
        # Count all action buttons
        total_count = db.query(ActionButton).count()
        print(f"Total action buttons: {total_count}")
        
        # Check for records where company_id is NULL
        null_company_count = db.query(ActionButton).filter(ActionButton.company_id.is_(None)).count()
        print(f"Action buttons with NULL company_id: {null_company_count}")
        
        # Check for records where company_id is empty string
        empty_company_count = db.query(ActionButton).filter(ActionButton.company_id == "").count()
        print(f"Action buttons with empty company_id: {empty_company_count}")
        
        # Get all records with NULL or empty company_id
        null_or_empty_records = db.query(ActionButton).filter(
            (ActionButton.company_id.is_(None)) | 
            (ActionButton.company_id == "")
        ).all()
        
        print(f"\nRecords with NULL or empty company_id:")
        for record in null_or_empty_records:
            print(f"  ID: {record.id}, Name: {record.unique_name}, Company ID: {record.company_id}")
            
    except Exception as e:
        print(f"Error querying database: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    check_action_buttons()