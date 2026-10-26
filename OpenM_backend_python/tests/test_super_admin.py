import os
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.auth import get_password_hash
from app.database import Base, get_db
from app.models import Employee, Organization
from app.routers.auth import router as auth_router
from app.routers.companies import router as companies_router

api_app = FastAPI()
api_app.include_router(auth_router)
api_app.include_router(companies_router)

SETUP_PAYLOAD = {
    "organization_name": "Root Organization",
    "first_name": "Super",
    "last_name": "Admin",
    "email": "super@example.com",
    "login_name": "superadmin",
    "password": "A-strong-password-2026",
}

NEW_ORGANIZATION = {
    "unique_name": "Second Organization",
    "initial_admin": {
        "first_name": "Second",
        "last_name": "Admin",
        "email": "second@example.com",
        "login_name": "secondadmin",
        "password": "Another-strong-pass-2026",
    },
}


@pytest.fixture()
def client_and_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine)

    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    api_app.dependency_overrides[get_db] = override_get_db
    try:
        with TestClient(api_app) as client:
            yield client, session_factory
    finally:
        api_app.dependency_overrides.clear()
        engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, username: str, password: str) -> str:
    response = client.post("/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200
    return response.json()["access_token"]


def _setup_super_admin(client) -> str:
    response = client.post("/auth/setup", json=SETUP_PAYLOAD)
    assert response.status_code == 201
    return response.json()["access_token"]


def test_initial_setup_creates_organization_and_super_admin(client_and_session):
    client, session_factory = client_and_session
    token = _setup_super_admin(client)

    me = client.get("/auth/employees/me", headers=_auth(token)).json()
    assert me["role"] == "Admin"
    assert me["is_super_admin"] is True

    with session_factory() as db:
        organization = db.query(Organization).one()
        assert organization.unique_name == "Root Organization"
        assert db.query(Employee).one().organization_id == organization.id


def test_super_admin_creates_organization_with_its_own_admin(client_and_session):
    client, _ = client_and_session
    token = _setup_super_admin(client)

    response = client.post("/companies", json=NEW_ORGANIZATION, headers=_auth(token))
    assert response.status_code == 201
    new_organization_id = response.json()["id"]

    names = {item["unique_name"] for item in client.get("/companies", headers=_auth(token)).json()}
    assert names == {"Root Organization", "Second Organization"}

    second_token = _login(client, "secondadmin", NEW_ORGANIZATION["initial_admin"]["password"])
    second_me = client.get("/auth/employees/me", headers=_auth(second_token)).json()
    assert second_me["organization_id"] == new_organization_id
    assert second_me["role"] == "Admin"
    assert second_me["is_super_admin"] is False


def test_organization_admin_cannot_create_or_see_other_organizations(client_and_session):
    client, _ = client_and_session
    token = _setup_super_admin(client)
    client.post("/companies", json=NEW_ORGANIZATION, headers=_auth(token))
    second_token = _login(client, "secondadmin", NEW_ORGANIZATION["initial_admin"]["password"])

    forbidden = client.post(
        "/companies",
        json={"unique_name": "Rogue Organization"},
        headers=_auth(second_token),
    )
    assert forbidden.status_code == 403

    visible = client.get("/companies", headers=_auth(second_token)).json()
    assert [item["unique_name"] for item in visible] == ["Second Organization"]

    root_id = next(
        item["id"] for item in client.get("/companies", headers=_auth(token)).json()
        if item["unique_name"] == "Root Organization"
    )
    other_update = client.patch(
        f"/companies/{root_id}",
        json={"unique_name": "Hijacked"},
        headers=_auth(second_token),
    )
    assert other_update.status_code == 403


def test_duplicate_organization_or_admin_login_is_rejected(client_and_session):
    client, session_factory = client_and_session
    token = _setup_super_admin(client)

    assert client.post("/companies", json=NEW_ORGANIZATION, headers=_auth(token)).status_code == 201

    duplicate_name = client.post("/companies", json=NEW_ORGANIZATION, headers=_auth(token))
    assert duplicate_name.status_code == 409

    duplicate_login = dict(NEW_ORGANIZATION, unique_name="Third Organization")
    assert client.post("/companies", json=duplicate_login, headers=_auth(token)).status_code == 409

    with session_factory() as db:
        assert db.query(Organization).count() == 2


def test_manager_cannot_create_organizations(client_and_session):
    client, session_factory = client_and_session
    _setup_super_admin(client)
    with session_factory() as db:
        organization = db.query(Organization).one()
        db.add(
            Employee(
                organization_id=organization.id,
                first_name="Max",
                last_name="Manager",
                email="manager@example.com",
                login_name="manager",
                hashed_password=get_password_hash("manager-password-1"),
                role="manager",
            )
        )
        db.commit()

    manager_token = _login(client, "manager", "manager-password-1")
    response = client.post(
        "/companies",
        json={"unique_name": "Manager Organization"},
        headers=_auth(manager_token),
    )
    assert response.status_code == 403
