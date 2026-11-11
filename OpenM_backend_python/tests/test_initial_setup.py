import os
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.auth import verify_password
from app.check_initial_setup import check_initial_setup
from app.database import Base, get_db
from app.models import Employee
from app.routers.auth import router as auth_router

setup_app = FastAPI()
setup_app.include_router(auth_router)


@pytest.fixture()
def setup_client(postgres_engine):
    engine = postgres_engine
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


def test_startup_checker_matches_setup_status(setup_client, postgres_engine):
    client, _ = setup_client
    assert client.get("/auth/setup/status").json()["setup_required"] is True
    assert "Initial setup is required" in check_initial_setup(postgres_engine)

    assert client.post("/auth/setup", json=_initial_setup_payload()).status_code == 201
    assert client.get("/auth/setup/status").json()["setup_required"] is False
    assert "Initial setup is complete" in check_initial_setup(postgres_engine)


def test_startup_checker_with_uninitialized_schema(postgres_engine):
    assert "Database schema not initialized" in check_initial_setup(postgres_engine)


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


def test_app_startup_and_health_use_postgresql(postgres_engine, monkeypatch):
    import app.database

    monkeypatch.setattr(app.database, "engine", postgres_engine)
    monkeypatch.setattr(app.database, "SessionLocal", sessionmaker(bind=postgres_engine))
    from app.main import app

    with TestClient(app) as client:
        assert client.get("/health").json() == {
            "status": "healthy",
            "database": "connected",
        }
