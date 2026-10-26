import os
import sys

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from datetime import timedelta

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.database import Base
from app.models import Company, Employee, Part, Project, ProjectOrderItem, ProjectStatus
from app.routers.projects import (
    _ensure_project_order_items,
    create_project_gantt_sub_step,
    delete_project_gantt_sub_step,
    start_project_gantt,
    update_project_gantt_step_duration,
    update_project_gantt_sub_step_assignee,
    update_project_gantt_sub_step_duration,
    update_project_order_notes,
)
from app.schemas import (
    ProjectGanttSubStepCreate,
    ProjectGanttStepDurationUpdate,
    ProjectGanttSubStepAssigneeUpdate,
    ProjectGanttSubStepDurationUpdate,
    ProjectOrderNotesUpdate,
    ProjectOut,
)


@pytest.fixture()
def db_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()


def make_project(session):
    project = Project(company_id="company-1", name="Test Project")
    session.add(project)
    session.flush()
    return project


def make_company(session, *, company_id="company-1"):
    company = Company(id=company_id, unique_name=f"Company {company_id}", unique_code=f"CODE-{company_id}")
    session.add(company)
    session.flush()
    return company


def make_employee(session, *, company_id="company-1", login_name="planner"):
    employee = Employee(
        company_id=company_id,
        first_name="Plan",
        last_name="Ner",
        email=f"{login_name}@example.com",
        login_name=login_name,
        hashed_password="dummy",
    )
    session.add(employee)
    session.flush()
    return employee


def test_ensure_project_order_items_creates_entries_for_base_cases_and_main_parts(db_session):
    project = make_project(db_session)

    base_case_part = Part(name="Base case", part_role="base_case")
    main_part = Part(name="Main part", part_role="main")
    main_part_with_parent = Part(name="Main child", part_role="main", parent_part_id="parent-id")
    other_part = Part(name="Other part", part_role="other")

    db_session.add_all([base_case_part, main_part, main_part_with_parent, other_part])
    db_session.flush()

    _ensure_project_order_items(db_session, project)
    db_session.commit()

    order_items = (
        db_session.query(ProjectOrderItem)
        .filter(ProjectOrderItem.project_id == project.id)
        .all()
    )

    part_ids = {item.part_id for item in order_items}
    assert base_case_part.id in part_ids
    assert main_part.id in part_ids
    assert main_part_with_parent.id in part_ids
    assert other_part.id not in part_ids

    # Calling it again should not create duplicates.
    _ensure_project_order_items(db_session, project)
    db_session.commit()
    assert db_session.query(ProjectOrderItem).filter(ProjectOrderItem.project_id == project.id).count() == 3


def test_update_project_order_notes_persists_notes(db_session):
    project = make_project(db_session)

    update_project_order_notes(db_session, project.id, ProjectOrderNotesUpdate(top_note="Top note", bottom_note="Bottom note"))
    db_session.commit()

    project_after = db_session.get(Project, project.id)
    assert project_after is not None
    assert project_after.order_top_note == "Top note"
    assert project_after.order_bottom_note == "Bottom note"

    project_out = ProjectOut.model_validate(project_after)
    assert project_out.order_top_note == "Top note"
    assert project_out.order_bottom_note == "Bottom note"


def test_update_project_order_notes_accepts_empty_values(db_session):
    project = make_project(db_session)

    update_project_order_notes(db_session, project.id, ProjectOrderNotesUpdate(top_note="", bottom_note=""))
    db_session.commit()

    project_after = db_session.get(Project, project.id)
    assert project_after is not None
    assert project_after.order_top_note is None
    assert project_after.order_bottom_note is None


def test_start_project_gantt_rejects_statuses_before_sale(db_session):
    make_company(db_session)
    project = make_project(db_session)
    project.status = ProjectStatus.QUOTE
    db_session.commit()

    with pytest.raises(Exception) as exc_info:
        start_project_gantt(project.id, db_session, _current_employee=None)

    error = exc_info.value
    assert getattr(error, "status_code", None) == 400
    assert getattr(error, "detail", None) == "Gantt can only start when project status is Sale or later"


def test_start_project_gantt_allows_statuses_after_sale(db_session):
    make_company(db_session)
    project = make_project(db_session)
    project.status = ProjectStatus.CONSTRUCTION
    db_session.commit()

    response = start_project_gantt(project.id, db_session, _current_employee=None)

    assert response.project.gantt_started is True
    assert response.project.gantt_started_at is not None
    assert len(response.gantt_steps) > 0
    assert response.gantt_steps[0].status_key == ProjectStatus.SALE.value


def test_overview_duration_change_rescales_sub_steps_and_shifts_following_steps(db_session):
    make_company(db_session)
    project = make_project(db_session)
    project.status = ProjectStatus.SALE
    db_session.commit()

    started = start_project_gantt(project.id, db_session, _current_employee=None)
    first_step = started.gantt_steps[0]
    second_step = started.gantt_steps[1]

    original_second_start = second_step.planned_start_date
    original_second_end = second_step.planned_end_date

    updated = update_project_gantt_step_duration(
        project.id,
        first_step.id,
        payload=ProjectGanttStepDurationUpdate(duration_days=14),
        db=db_session,
        _current_employee=None,
    )

    first_after = next(item for item in updated.gantt_steps if item.id == first_step.id)
    second_after = next(item for item in updated.gantt_steps if item.id == second_step.id)

    assert first_after.planned_start_date is not None
    assert first_after.planned_end_date is not None
    assert (first_after.planned_end_date - first_after.planned_start_date).days + 1 == 14
    assert len(first_after.sub_steps) == 3
    assert first_after.sub_steps[0].planned_start_date == first_after.planned_start_date
    assert first_after.sub_steps[-1].planned_end_date == first_after.planned_end_date

    assert original_second_start is not None
    assert original_second_end is not None
    assert second_after.planned_start_date == original_second_start + timedelta(days=7)
    assert second_after.planned_end_date == original_second_end + timedelta(days=7)


def test_sub_step_duration_change_updates_parent_and_following_step(db_session):
    make_company(db_session)
    project = make_project(db_session)
    project.status = ProjectStatus.SALE
    db_session.commit()

    started = start_project_gantt(project.id, db_session, _current_employee=None)
    first_step = started.gantt_steps[0]
    second_step = started.gantt_steps[1]

    tree_before = update_project_gantt_step_duration(
        project.id,
        first_step.id,
        payload=ProjectGanttStepDurationUpdate(duration_days=9),
        db=db_session,
        _current_employee=None,
    )
    first_before = next(item for item in tree_before.gantt_steps if item.id == first_step.id)
    target_sub = first_before.sub_steps[0]
    old_parent_end = first_before.planned_end_date
    old_second_start = next(item for item in tree_before.gantt_steps if item.id == second_step.id).planned_start_date

    tree_after = update_project_gantt_sub_step_duration(
        project.id,
        target_sub.id,
        payload=ProjectGanttSubStepDurationUpdate(duration_days=6),
        db=db_session,
        _current_employee=None,
    )

    first_after = next(item for item in tree_after.gantt_steps if item.id == first_step.id)
    second_after = next(item for item in tree_after.gantt_steps if item.id == second_step.id)

    assert old_parent_end is not None
    assert first_after.planned_end_date is not None
    assert first_after.planned_end_date > old_parent_end

    assert old_second_start is not None
    assert second_after.planned_start_date is not None
    assert second_after.planned_start_date > old_second_start


def test_sub_step_assignee_can_be_set_and_cleared(db_session):
    make_company(db_session)
    make_employee(db_session, login_name="planner")
    project = make_project(db_session)
    project.status = ProjectStatus.SALE
    db_session.commit()

    started = start_project_gantt(project.id, db_session, _current_employee=None)
    first_step = started.gantt_steps[0]

    tree = update_project_gantt_step_duration(
        project.id,
        first_step.id,
        payload=ProjectGanttStepDurationUpdate(duration_days=7),
        db=db_session,
        _current_employee=None,
    )
    target_sub = next(item for item in tree.gantt_steps if item.id == first_step.id).sub_steps[0]

    assigned = update_project_gantt_sub_step_assignee(
        project.id,
        target_sub.id,
        payload=ProjectGanttSubStepAssigneeUpdate(assignee_login="planner"),
        db=db_session,
        _current_employee=None,
    )
    assigned_sub = next(item for item in assigned.gantt_steps if item.id == first_step.id).sub_steps[0]
    assert assigned_sub.assignee_login == "planner"

    cleared = update_project_gantt_sub_step_assignee(
        project.id,
        target_sub.id,
        payload=ProjectGanttSubStepAssigneeUpdate(assignee_login=None),
        db=db_session,
        _current_employee=None,
    )
    cleared_sub = next(item for item in cleared.gantt_steps if item.id == first_step.id).sub_steps[0]
    assert cleared_sub.assignee_login is None


def test_create_sub_step_extends_parent_and_shifts_following(db_session):
    make_company(db_session)
    project = make_project(db_session)
    project.status = ProjectStatus.SALE
    db_session.commit()

    started = start_project_gantt(project.id, db_session, _current_employee=None)
    first_step = started.gantt_steps[0]
    second_step = started.gantt_steps[1]

    tree_before = update_project_gantt_step_duration(
        project.id,
        first_step.id,
        payload=ProjectGanttStepDurationUpdate(duration_days=7),
        db=db_session,
        _current_employee=None,
    )
    first_before = next(item for item in tree_before.gantt_steps if item.id == first_step.id)
    second_before = next(item for item in tree_before.gantt_steps if item.id == second_step.id)

    created = create_project_gantt_sub_step(
        project.id,
        first_step.id,
        payload=ProjectGanttSubStepCreate(title="New detail", duration_days=3),
        db=db_session,
        _current_employee=None,
    )

    first_after = next(item for item in created.gantt_steps if item.id == first_step.id)
    second_after = next(item for item in created.gantt_steps if item.id == second_step.id)

    assert len(first_after.sub_steps) == len(first_before.sub_steps) + 1
    assert first_after.planned_end_date is not None
    assert first_before.planned_end_date is not None
    assert first_after.planned_end_date == first_before.planned_end_date + timedelta(days=3)
    assert second_after.planned_start_date == second_before.planned_start_date + timedelta(days=3)


def test_delete_sub_step_shrinks_parent_and_shifts_following(db_session):
    make_company(db_session)
    project = make_project(db_session)
    project.status = ProjectStatus.SALE
    db_session.commit()

    started = start_project_gantt(project.id, db_session, _current_employee=None)
    first_step = started.gantt_steps[0]
    second_step = started.gantt_steps[1]

    tree_before = update_project_gantt_step_duration(
        project.id,
        first_step.id,
        payload=ProjectGanttStepDurationUpdate(duration_days=12),
        db=db_session,
        _current_employee=None,
    )
    first_before = next(item for item in tree_before.gantt_steps if item.id == first_step.id)
    second_before = next(item for item in tree_before.gantt_steps if item.id == second_step.id)
    removed_sub = first_before.sub_steps[-1]
    removed_duration = (
        (removed_sub.planned_end_date - removed_sub.planned_start_date).days + 1
        if removed_sub.planned_start_date is not None and removed_sub.planned_end_date is not None
        else 1
    )

    deleted = delete_project_gantt_sub_step(
        project.id,
        removed_sub.id,
        db=db_session,
        _current_employee=None,
    )

    first_after = next(item for item in deleted.gantt_steps if item.id == first_step.id)
    second_after = next(item for item in deleted.gantt_steps if item.id == second_step.id)

    assert len(first_after.sub_steps) == len(first_before.sub_steps) - 1
    assert first_after.planned_end_date == first_before.planned_end_date - timedelta(days=removed_duration)
    assert second_after.planned_start_date == second_before.planned_start_date - timedelta(days=removed_duration)
