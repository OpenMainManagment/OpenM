import os
from uuid import uuid4

import pytest
from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import make_url


@pytest.fixture()
def postgres_engine():
    url = os.environ.get("OPENM_TEST_DATABASE_URL")
    if not url:
        pytest.fail("Set OPENM_TEST_DATABASE_URL to a dedicated PostgreSQL test database")
    if make_url(url).get_backend_name() != "postgresql":
        pytest.fail("OPENM_TEST_DATABASE_URL must point to PostgreSQL")

    schema = f"openm_test_{uuid4().hex}"
    admin_engine = create_engine(url)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    engine = create_engine(url)

    @event.listens_for(engine, "connect")
    def set_search_path(dbapi_connection, _connection_record):
        with dbapi_connection.cursor() as cursor:
            cursor.execute(f'SET search_path TO "{schema}"')
        dbapi_connection.commit()

    try:
        yield engine
    finally:
        engine.dispose()
        try:
            with admin_engine.begin() as connection:
                connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        finally:
            admin_engine.dispose()
