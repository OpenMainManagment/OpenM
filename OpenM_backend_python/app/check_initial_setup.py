"""Check PostgreSQL connectivity and initial setup before starting OpenM."""

from sqlalchemy import inspect
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from .database import engine
from .models import Employee
from .services.initial_setup import is_initial_setup_required


def check_initial_setup(database_engine: Engine) -> str:
    with database_engine.connect() as connection:
        connection.exec_driver_sql("SELECT 1")
        if not inspect(connection).has_table(Employee.__tablename__):
            return "PostgreSQL connected. Database schema not initialized; setup status will be checked when the app starts."
        with Session(bind=connection) as session:
            if is_initial_setup_required(session):
                return "PostgreSQL connected. Initial setup is required; complete it in the application."
            return "PostgreSQL connected. Initial setup is complete."


if __name__ == "__main__":
    print(check_initial_setup(engine))
