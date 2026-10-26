import os
import sys

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.auth import get_current_employee, get_current_manager_or_admin
from app.database import Base, get_db
from app.main import app
from app.models import Company, Employee, Project, ProjectStatus, Todo


@pytest.fixture()
def api_client_with_db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)

    session = TestingSessionLocal()
    company = Company(id="company-1", unique_name="Main", unique_code="MAIN-1")
    manager = Employee(
        id="employee-manager",
        company_id=company.id,
        first_name="Project",
        last_name="Manager",
        email="manager@example.com",
        login_name="manager",
        hashed_password="dummy",
        role="manager",
        department="Planning",
    )
    engineer = Employee(
        id="employee-engineer",
        company_id=company.id,
        first_name="Build",
        last_name="Engineer",
        email="engineer@example.com",
        login_name="engineer",
        hashed_password="dummy",
        role="employee",
        department="Assembly",
    )
    project = Project(
        id="project-1",
        company_id=company.id,
        name="API Gantt",
        status=ProjectStatus.SALE,
        gantt_started=True,
    )

    foreign_company = Company(id="company-2", unique_name="Foreign", unique_code="FOREIGN-1")
    foreign_employee = Employee(
        id="employee-foreign",
        company_id=foreign_company.id,
        first_name="Other",
        last_name="User",
        email="other@example.com",
        login_name="other",
        hashed_password="dummy",
        role="employee",
        department="Planning",
    )

    session.add_all([
        company,
        manager,
        engineer,
        project,
        foreign_company,
        foreign_employee,
    ])
    session.commit()

    def _override_get_db():
        try:
            yield session
        finally:
            pass

    def _override_current_employee():
        return manager

    app.dependency_overrides[get_db] = _override_get_db
    app.dependency_overrides[get_current_employee] = _override_current_employee
    app.dependency_overrides[get_current_manager_or_admin] = _override_current_employee

    client = TestClient(app)
    client.app.state.test_db_session = session
    try:
        yield client
    finally:
        app.dependency_overrides.clear()
        session.close()


def _first_step(tree_payload: dict) -> dict:
    return tree_payload["gantt_steps"][0]


def test_create_and_delete_sub_step_via_api(api_client_with_db):
    client = api_client_with_db

    tree_before = client.get("/projects/project-1/gantt-tree")
    assert tree_before.status_code == 200
    first_before = _first_step(tree_before.json())
    initial_sub_count = len(first_before["sub_steps"])

    create_response = client.post(
        f"/projects/project-1/gantt/steps/{first_before['id']}/sub-steps",
        json={"title": "Extra Detail", "duration_days": 2},
    )
    assert create_response.status_code == 200
    first_created = _first_step(create_response.json())
    assert len(first_created["sub_steps"]) == initial_sub_count + 1

    created_sub = first_created["sub_steps"][-1]
    delete_response = client.delete(
        f"/projects/project-1/gantt/sub-steps/{created_sub['id']}"
    )
    assert delete_response.status_code == 200
    first_deleted = _first_step(delete_response.json())
    assert len(first_deleted["sub_steps"]) == initial_sub_count


def test_assignee_update_rejects_foreign_company_employee(api_client_with_db):
    client = api_client_with_db

    tree = client.get("/projects/project-1/gantt-tree")
    assert tree.status_code == 200
    first = _first_step(tree.json())
    sub_step_id = first["sub_steps"][0]["id"]

    response = client.patch(
        f"/projects/project-1/gantt/sub-steps/{sub_step_id}/assignee",
        json={"assignee_login": "other"},
    )
    assert response.status_code == 400
    assert "project company" in response.json().get("detail", "")


def test_multi_assignees_create_todos(api_client_with_db):
    client = api_client_with_db

    tree = client.get("/projects/project-1/gantt-tree")
    assert tree.status_code == 200
    first = _first_step(tree.json())
    sub_step_id = first["sub_steps"][0]["id"]

    response = client.patch(
        f"/projects/project-1/gantt/sub-steps/{sub_step_id}/assignees",
        json={"assignee_logins": ["manager", "engineer"]},
    )
    assert response.status_code == 200

    updated_sub_step = _first_step(response.json())["sub_steps"][0]
    assert set(updated_sub_step.get("assignee_logins", [])) == {
        "manager",
        "engineer",
    }

    todos = (
        client.app.state.test_db_session.query(Todo)
        .filter(Todo.gantt_sub_step_id == sub_step_id)
        .all()
    )
    assert len(todos) == 2
    assert {todo.main_employer for todo in todos} == {"manager", "engineer"}
