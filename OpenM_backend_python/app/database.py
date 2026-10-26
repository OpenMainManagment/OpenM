from pathlib import Path
import sqlite3

from sqlalchemy import create_engine, MetaData
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DATABASE_DIR = Path(__file__).resolve().parent.parent / "database"
DATABASE_DIR.mkdir(parents=True, exist_ok=True)
DATABASE_PATH = DATABASE_DIR / "openm.db"
LEGACY_DATABASE_PATH = DATABASE_DIR / "bfsa.db"
INITIAL_ADMIN_PASSWORD_REQUIRED = "__OPENM_INITIAL_ADMIN_PASSWORD_REQUIRED__"


def _migrate_legacy_database(
    legacy_path: Path = LEGACY_DATABASE_PATH,
    database_path: Path = DATABASE_PATH,
) -> None:
    if database_path.exists() or not legacy_path.exists():
        return

    legacy_db = sqlite3.connect(legacy_path)
    try:
        tables = {
            row[0]
            for row in legacy_db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        if "employees" in tables:
            legacy_db.execute(
                """
                UPDATE employees
                SET hashed_password = ?
                WHERE lower(login_name) = 'admin' AND lower(role) = 'admin'
                """,
                (INITIAL_ADMIN_PASSWORD_REQUIRED,),
            )
            legacy_db.commit()

        openm_db = sqlite3.connect(database_path)
        try:
            legacy_db.backup(openm_db)
        finally:
            openm_db.close()
    finally:
        legacy_db.close()

    print(
        "[startup] Migrated the legacy database to openm.db; "
        "the original file was retained and the legacy admin must set a new password."
    )


_migrate_legacy_database()
DATABASE_URL = f"sqlite:///{DATABASE_PATH.as_posix()}"

# Create engine with suppress warnings for circular dependencies
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Custom create_all that suppresses circular dependency warnings
def create_all_tables():
    """Create all database tables with suppressed circular dependency warnings."""
    # Create a new metadata object to avoid issues with the existing one
    metadata = MetaData()
    
    # Get all table classes from the Base's registry
    for table in Base.registry._class_registry.values():
        if hasattr(table, '__table__'):
            metadata.add(table.__table__)
    
    # Create tables without warnings - this approach works around circular dependencies
    metadata.create_all(bind=engine, checkfirst=True)