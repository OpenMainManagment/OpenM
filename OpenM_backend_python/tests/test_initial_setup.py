import os
import sqlite3
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.auth import verify_password
from app.database import (
    INITIAL_ADMIN_PASSWORD_REQUIRED,
    Base,
    _migrate_legacy_database,
    get_db,
)
from app.models import Employee, Organization
from app.routers.auth import router as auth_router

setup_app = FastAPI()
setup_app.include_router(auth_router)


@pytest.fixture()
def setup_client():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    test_session = sessionmaker(bind=engine)

    def override_get_db():
        db = test_session()
        try:
            yield db
        finally:
            db.close()

    setup_app.dependency_overrides[get_db] = override_get_db
    try:
        with TestClient(setup_app) as client:
            yield client, test_session
    finally:
        setup_app.dependency_overrides.clear()
        engine.dispose()


def _initial_setup_payload():
    return {
        "organization_name": "Example Organization",
        "first_name": "Open",
        "last_name": "Manager",
        "email": "admin@example.com",
        "login_name": "openmanager",
        "password": "A-strong-password-2026",
    }


def test_initial_setup_creates_admin_and_disables_setup(setup_client):
    client, test_session = setup_client

    status_response = client.get("/auth/setup/status").json()
    assert status_response["setup_required"] is True
    assert status_response["legacy_admin_password_reset"] is False

    response = client.post("/auth/setup", json=_initial_setup_payload())

    assert response.status_code == 201
    assert response.json()["access_token"]
    status_response = client.get("/auth/setup/status").json()
    assert status_response["setup_required"] is False
    assert status_response["legacy_admin_password_reset"] is False

    with test_session() as db:
        employee = db.query(Employee).filter_by(login_name="openmanager").one()
        assert employee.role == "Admin"
        assert verify_password(
            _initial_setup_payload()["password"],
            employee.hashed_password,
        )
        assert employee.hashed_password != _initial_setup_payload()["password"]

    login_response = client.post(
        "/auth/login",
        json={
            "username": "openmanager",
            "password": _initial_setup_payload()["password"],
        },
    )
    assert login_response.status_code == 200


def test_initial_setup_is_one_time(setup_client):
    client, _ = setup_client

    first_response = client.post("/auth/setup", json=_initial_setup_payload())
    second_response = client.post("/auth/setup", json=_initial_setup_payload())

    assert first_response.status_code == 201
    assert second_response.status_code == 409


def test_initial_setup_requires_strong_password(setup_client):
    client, _ = setup_client
    payload = _initial_setup_payload()
    payload["password"] = "short"

    response = client.post("/auth/setup", json=payload)

    assert response.status_code == 422
    assert client.get("/auth/setup/status").json()["setup_required"] is True


def test_legacy_admin_must_set_new_password(setup_client):
    client, test_session = setup_client
    with test_session() as db:
        organization = Organization(
            unique_name="Existing Organization",
            unique_code="ORG-EXISTING",
        )
        db.add(organization)
        db.flush()
        db.add(
            Employee(
                organization_id=organization.id,
                first_name="Old",
                last_name="Admin",
                email="admin@existing.example",
                login_name="admin",
                hashed_password=INITIAL_ADMIN_PASSWORD_REQUIRED,
                role="Admin",
                department="Management",
            )
        )
        db.commit()

    status_response = client.get("/auth/setup/status").json()
    assert status_response["setup_required"] is True
    assert status_response["legacy_admin_password_reset"] is True
    assert status_response["organization_name"] == "Existing Organization"

    payload = _initial_setup_payload()
    payload["organization_name"] = "A name the setup must not apply to existing data"
    setup_response = client.post("/auth/setup", json=payload)
    assert setup_response.status_code == 201

    with test_session() as db:
        employee = db.query(Employee).filter_by(login_name="openmanager").one()
        assert employee.organization.unique_name == "Existing Organization"
        assert verify_password(payload["password"], employee.hashed_password)

    assert client.post(
        "/auth/login",
        json={"username": "admin", "password": "admin123"},
    ).status_code == 401
    assert client.post(
        "/auth/login",
        json={"username": "openmanager", "password": payload["password"]},
    ).status_code == 200


def test_legacy_database_migration_preserves_data_and_locks_default_admin(
    tmp_path,
):
    legacy_path = tmp_path / "bfsa.db"
    openm_path = tmp_path / "openm.db"

    with sqlite3.connect(legacy_path) as db:
        db.execute(
            """
            CREATE TABLE employees (
                login_name TEXT,
                role TEXT,
                hashed_password TEXT
            )
            """
        )
        db.execute(
            "INSERT INTO employees VALUES (?, ?, ?)",
            ("admin", "Admin", "legacy hash"),
        )
        db.execute("CREATE TABLE projects (name TEXT)")
        db.execute("INSERT INTO projects VALUES (?)", ("Preserved project",))

    _migrate_legacy_database(legacy_path, openm_path)

    for database_path in (legacy_path, openm_path):
        with sqlite3.connect(database_path) as db:
            password_marker = db.execute(
                "SELECT hashed_password FROM employees WHERE login_name = 'admin'"
            ).fetchone()[0]
            preserved_project = db.execute(
                "SELECT name FROM projects"
            ).fetchone()[0]
        assert password_marker == INITIAL_ADMIN_PASSWORD_REQUIRED
        assert preserved_project == "Preserved project"
