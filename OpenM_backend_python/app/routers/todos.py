from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..auth import get_current_employee, get_current_manager_or_admin
from ..database import get_db
from ..models import Employee, Project, Todo
from ..schemas import (
    TodoCreate,
    TodoOut,
    TodoReorderRequest,
    TodoRepresentationRequest,
    TodoUpdate,
)


router = APIRouter(prefix="/todos", tags=["todos"])


def _normalize_login(value: str | None) -> str:
    return (value or "").strip().lower()


def _parse_coworker_logins(raw_value: str | None) -> list[str]:
    if not raw_value:
        return []
    items = [item.strip() for item in raw_value.split(",")]
    unique: list[str] = []
    seen: set[str] = set()
    for item in items:
        if not item:
            continue
        key = item.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)
    return unique


def _serialize_coworker_logins(logins: list[str]) -> str:
    cleaned: list[str] = []
    seen: set[str] = set()
    for item in logins:
        value = item.strip()
        if not value:
            continue
        key = value.lower()
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(value)
    return ",".join(cleaned)


def _to_todo_out(todo: Todo) -> TodoOut:
    return TodoOut(
        id=todo.id,
        name=todo.name,
        organization_id=todo.organization_id,
        project_id=todo.project_id,
        folder_id=todo.folder_id,
        department=todo.department,
        main_employer=todo.main_employer,
        coworker_logins=_parse_coworker_logins(todo.coworker_logins),
        description=todo.description,
        start_date=todo.start_date,
        end_date=todo.end_date,
        project_status=todo.project_status,
        sort_order=todo.sort_order,
    )


def _can_edit_todo(employee: Employee, todo: Todo) -> bool:
    role = (employee.role or "employee").lower()
    if role in {"admin", "manager"}:
        return True
    login = _normalize_login(employee.login_name)
    if not login:
        return False
    if _normalize_login(todo.main_employer) == login:
        return True
    coworker_set = {_normalize_login(item) for item in _parse_coworker_logins(todo.coworker_logins)}
    return login in coworker_set


def _todo_date_range(todo: Todo) -> tuple[date, date] | None:
    start = todo.start_date or todo.end_date
    end = todo.end_date or todo.start_date
    if start is None or end is None:
        return None
    if start > end:
        return end, start
    return start, end


def _todo_intersects_range(todo: Todo, start: date, end: date) -> bool:
    interval = _todo_date_range(todo)
    if interval is None:
        return False
    todo_start, todo_end = interval
    return not (todo_end < start or todo_start > end)


def _clear_representation(todo: Todo) -> None:
    todo.representation_delegate_login = None
    todo.representation_start_date = None
    todo.representation_end_date = None
    todo.representation_original_main_employer = None
    todo.representation_active = False


def apply_due_representations(db: Session) -> int:
    today = date.today()
    candidates = (
        db.query(Todo)
        .filter(Todo.representation_delegate_login.isnot(None))
        .filter(Todo.representation_start_date.isnot(None))
        .filter(Todo.representation_end_date.isnot(None))
        .all()
    )

    changed = False
    updates = 0

    for todo in candidates:
        start = todo.representation_start_date
        end = todo.representation_end_date
        delegate = (todo.representation_delegate_login or "").strip()

        if not delegate or start is None or end is None:
            _clear_representation(todo)
            changed = True
            updates += 1
            continue

        if start > end:
            start, end = end, start
            todo.representation_start_date = start
            todo.representation_end_date = end
            changed = True

        if start <= today <= end:
            if todo.representation_original_main_employer is None:
                todo.representation_original_main_employer = todo.main_employer
            if _normalize_login(todo.main_employer) != _normalize_login(delegate):
                todo.main_employer = delegate
                changed = True
                updates += 1
            if not todo.representation_active:
                todo.representation_active = True
                changed = True
        elif today > end:
            if todo.representation_active:
                todo.main_employer = todo.representation_original_main_employer
            _clear_representation(todo)
            changed = True
            updates += 1

    if changed:
        db.commit()

    return updates


@router.get("", response_model=list[TodoOut])
def list_todos(
    organization_id: str | None = None,
    client_company_id: str | None = None,
    customer_company_id: str | None = None,
    project_id: str | None = None,
    folder_id: str | None = None,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    apply_due_representations(db)

    query = db.query(Todo)
    resolved_client_company_id = client_company_id or customer_company_id

    if resolved_client_company_id:
        query = query.join(Project, Todo.project_id == Project.id).filter(
            Project.customer_company_id == resolved_client_company_id,
        )
    if organization_id:
        query = query.filter(Todo.organization_id == organization_id)
    if project_id:
        query = query.filter(Todo.project_id == project_id)
    if folder_id:
        query = query.filter(Todo.folder_id == folder_id)
    results = query.order_by(
        Todo.project_status.asc(),
        Todo.sort_order.asc(),
        Todo.end_date.asc().nulls_last(),
    ).all()
    return [_to_todo_out(item) for item in results]


@router.post("", response_model=TodoOut)
def create_todo(
    payload: TodoCreate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    data = payload.model_dump()
    data["coworker_logins"] = _serialize_coworker_logins(payload.coworker_logins)
    if data.get("sort_order") is None:
        max_sort_order = (
            db.query(Todo.sort_order)
            .filter(Todo.project_status == data.get("project_status"))
            .order_by(Todo.sort_order.desc())
            .first()
        )
        data["sort_order"] = (max_sort_order[0] + 1) if max_sort_order else 0

    todo = Todo(**data)
    db.add(todo)
    db.commit()
    db.refresh(todo)
    return _to_todo_out(todo)


@router.patch("/reorder")
def reorder_todos(
    payload: TodoReorderRequest,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    if not payload.ordered_todo_ids:
        return {"status": "ok", "updated": 0}

    todos = db.query(Todo).filter(Todo.id.in_(payload.ordered_todo_ids)).all()
    by_id = {todo.id: todo for todo in todos}

    missing_ids = [item for item in payload.ordered_todo_ids if item not in by_id]
    if missing_ids:
        raise HTTPException(status_code=404, detail=f"Todos not found: {', '.join(missing_ids)}")

    for index, todo_id in enumerate(payload.ordered_todo_ids):
        todo = by_id[todo_id]
        todo.project_status = payload.project_status
        todo.sort_order = index

    db.commit()
    return {"status": "ok", "updated": len(payload.ordered_todo_ids)}


@router.get("/{todo_id}", response_model=TodoOut)
def get_todo(
    todo_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    apply_due_representations(db)

    todo = db.get(Todo, todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")
    return _to_todo_out(todo)


@router.post("/representation")
def set_todo_representation(
    payload: TodoRepresentationRequest,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    start = payload.start_date
    end = payload.end_date
    if start > end:
        raise HTTPException(status_code=400, detail="start_date must be before end_date")

    delegate_login = payload.delegate_login.strip()
    if not delegate_login:
        raise HTTPException(status_code=400, detail="delegate_login is required")

    current_login = _normalize_login(current_employee.login_name)
    if _normalize_login(delegate_login) == current_login:
        raise HTTPException(status_code=400, detail="delegate_login must be another coworker")

    delegate_exists = (
        db.query(Employee)
        .filter(func.lower(Employee.login_name) == _normalize_login(delegate_login))
        .first()
    )
    if delegate_exists is None:
        raise HTTPException(status_code=404, detail="Coworker not found")

    own_todos = (
        db.query(Todo)
        .filter(func.lower(Todo.main_employer) == current_login)
        .all()
    )

    matched = [todo for todo in own_todos if _todo_intersects_range(todo, start, end)]
    for todo in matched:
        if todo.representation_active and todo.representation_original_main_employer is not None:
            todo.main_employer = todo.representation_original_main_employer

        todo.representation_delegate_login = delegate_login
        todo.representation_start_date = start
        todo.representation_end_date = end
        todo.representation_original_main_employer = todo.main_employer
        todo.representation_active = False

    if matched:
        db.commit()

    activated_now = apply_due_representations(db)
    return {
        "status": "ok",
        "updated": len(matched),
        "activated_now": activated_now,
    }


@router.patch("/{todo_id}", response_model=TodoOut)
def update_todo(
    todo_id: str,
    payload: TodoUpdate,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    todo = db.get(Todo, todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    if not _can_edit_todo(current_employee, todo):
        raise HTTPException(status_code=403, detail="You are not allowed to edit this todo")

    changes = payload.model_dump(exclude_unset=True)
    if "coworker_logins" in changes:
        changes["coworker_logins"] = _serialize_coworker_logins(
            payload.coworker_logins or []
        )
    for key, value in changes.items():
        setattr(todo, key, value)

    db.commit()
    db.refresh(todo)
    return _to_todo_out(todo)


@router.delete("/{todo_id}")
def delete_todo(
    todo_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    todo = db.get(Todo, todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")
    db.delete(todo)
    db.commit()
    return {"status": "deleted"}
