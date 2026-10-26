import threading

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import inspect, text

from .database import Base, SessionLocal, engine
from .models import PartCategory, PartCategoryScope, ProjectStatus, Todo
from .routers import actions, admin, ai, auth, chat, companies, files, folders, manufacturers, parts, projects, todos
from .routers.todos import apply_due_representations
from .routers.settings import router as settings_router
from .routers.settings import mail_settings_router

app = FastAPI(title="OpenM Customer and File Management API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)


def _sql_default_literal(value: object) -> str | None:
    """Convert a Python default value into a valid SQL literal for the
    ALTER TABLE ... DEFAULT clause. repr() is NOT safe here: repr(False)
    is the string "False", which SQLite rejects as a column default (it
    needs 0/1); repr() of a string also uses Python's quoting rules, not
    SQL's. Returns None when the value can't be safely represented, in
    which case the caller should add the column without a DEFAULT."""
    if isinstance(value, bool):
        return "1" if value else "0"
    if value is None:
        return "NULL"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return "'" + value.replace("'", "''") + "'"
    return None


def _sync_missing_columns() -> None:
    """create_all() only creates tables that don't exist yet — it never adds
    new columns to a table that's already there. On a database created
    before newer model fields existed (e.g. Todo.representation_delegate_login),
    that leaves the real table missing columns the ORM expects, and every
    query touching them fails at the SQL level ("no such column: ...").
    even though the Python model looks correct. This adds any missing
    columns to existing tables so older databases stay in sync with the
    current models without needing a full migration tool.

    This must never be able to prevent the server from starting: any
    failure here is logged and swallowed rather than raised, and all
    schema reads happen on a single connection *before* any ALTER TABLE
    runs, to avoid a second connection colliding with an open write
    transaction on file-based SQLite ("database is locked")."""
    try:
        with engine.connect() as connection:
            inspector = inspect(connection)
            existing_tables = set(inspector.get_table_names())

            # Gather everything we need to do up front, on this one
            # connection, before starting any write transaction.
            columns_to_add: list[tuple[str, object]] = []
            for table in Base.metadata.sorted_tables:
                if table.name not in existing_tables:
                    continue  # brand-new table, create_all() already handled it
                existing_columns = {
                    col["name"] for col in inspector.get_columns(table.name)
                }
                for column in table.columns:
                    if column.name not in existing_columns:
                        columns_to_add.append((table.name, column))

        if not columns_to_add:
            return

        with engine.begin() as connection:
            for table_name, column in columns_to_add:
                try:
                    col_type = column.type.compile(engine.dialect)
                except Exception:
                    continue  # exotic type we can't safely ALTER for; skip

                default_literal = None
                if column.default is not None and getattr(
                    column.default, "is_scalar", False
                ):
                    default_literal = _sql_default_literal(column.default.arg)

                default_clause = (
                    f" DEFAULT {default_literal}" if default_literal is not None else ""
                )
                nullable_clause = (
                    "" if (column.nullable or not default_clause) else " NOT NULL"
                )

                try:
                    connection.execute(
                        text(
                            f'ALTER TABLE "{table_name}" '
                            f'ADD COLUMN "{column.name}" {col_type}'
                            f"{default_clause}{nullable_clause}"
                        )
                    )
                    print(f"[startup] Added missing column {table_name}.{column.name}")
                except Exception:
                    # Best-effort: don't block startup over one column we
                    # couldn't add automatically; log and move on.
                    print(
                        f"[startup] Could not auto-add column "
                        f"{table_name}.{column.name}; add it manually if needed."
                    )
    except Exception as exc:  # pragma: no cover - must never block startup
        print(f"[startup] Schema auto-sync skipped due to error: {exc}")


_sync_missing_columns()


@app.get("/")
async def root():
    return {"message": "Welcome to the OpenM Customer and File Management API"}


@app.get("/health")
async def health_check():
    # Test database connection
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        db.close()
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": "disconnected", "error": str(e)}


# Include routers
app.include_router(actions.router)
app.include_router(admin.router)
app.include_router(ai.router)
app.include_router(auth.router)
app.include_router(chat.router)
app.include_router(companies.router)
app.include_router(files.router)
app.include_router(folders.router)
app.include_router(manufacturers.router)
app.include_router(parts.router)
app.include_router(projects.router)
app.include_router(todos.router)
app.include_router(settings_router)
app.include_router(mail_settings_router)