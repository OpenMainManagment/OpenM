#!/usr/bin/env python3
"""
Verify that the admin user exists in the database.
"""

import sys
import os

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '.'))

from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from app.models import Employee
from app.database import Base, engine

def verify_admin_user():
    try:
        # Create a new session
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        db = SessionLocal()
        
        # Check if admin user exists
        admin = db.execute(select(Employee).where(Employee.login_name == "admin")).first()
        
        if admin:
            print("SUCCESS: Admin user found in database")
            print(f"User ID: {admin[0].id}")
            print(f"User Name: {admin[0].first_name} {admin[0].last_name}")
            print(f"User Role: {admin[0].role}")
            return True
        else:
            print("INFO: Admin user not found in database")
            return False
            
    except Exception as e:
        print(f"ERROR checking database: {e}")
        return False
    finally:
        db.close()

if __name__ == "__main__":
    verify_admin_user()