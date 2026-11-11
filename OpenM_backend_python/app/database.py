import os
from pathlib import Path

from sqlalchemy import MetaData, create_engine
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import DeclarativeBase, sessionmaker

APP_DATA_DIR = Path(
    os.getenv(
        "OPENM_STATE_ROOT",
        str(Path(__file__).resolve().parent.parent / "state"),
    )
).resolve()
APP_DATA_DIR.mkdir(parents=True, exist_ok=True)

DATABASE_URL = os.getenv("OPENM_DATABASE_URL") or URL.create(
    "postgresql+psycopg",
    username=os.getenv("OPENM_DB_USER", "openm"),
    password=os.getenv("OPENM_DB_PASSWORD"),
    host=os.getenv("OPENM_DB_HOST", "localhost"),
    port=int(os.getenv("OPENM_DB_PORT", "5432")),
    database=os.getenv("OPENM_DB_NAME", "openm"),
)

if make_url(DATABASE_URL).get_backend_name() != "postgresql":
    raise ValueError("OPENM_DATABASE_URL must use PostgreSQL")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_all_tables():
    """Create all database tables with suppressed circular dependency warnings."""
    metadata = MetaData()

    for table in Base.registry._class_registry.values():
        if hasattr(table, "__table__"):
            metadata.add(table.__table__)

    metadata.create_all(bind=engine, checkfirst=True)
