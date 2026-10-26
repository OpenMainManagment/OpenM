from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..auth import get_current_employee
from ..database import get_db
from ..models import Employee, Folder, Project
from ..schemas import FolderCreate, FolderOut
from ..services.storage_paths import ensure_folder_storage_dir, resolve_storage_root


router = APIRouter(prefix="/folders", tags=["folders"])

_STORAGE_ROOT = resolve_storage_root()


def _employee_can_see_folder(folder: Folder, employee: Employee) -> bool:
    """Return True if the employee is allowed to see the folder.

    Rules:
    - Admin employees always see all folders.
    - If the folder has no department_access rows it is visible to everyone.
    - If department_access rows exist the employee must either belong to one of
      those departments OR have a personal FolderUserAccess grant.
    """
    if (employee.role or "").lower() == "admin":
        return True
    if not folder.department_access:
        return True
    # personal grant overrides department restriction
    if any(ua.employee_id == employee.id for ua in folder.user_access):
        return True
    # department match (Employee.department is a free-text name stored on the employee)
    allowed_dept_names = {da.department.name for da in folder.department_access}
    return bool(employee.department and employee.department in allowed_dept_names)


@router.get("", response_model=list[FolderOut])
def list_folders(
    project_id: str,
    parent_folder_id: str | None = Query(default=None),
    include_all: bool = Query(default=False),
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    query = db.query(Folder).filter(Folder.project_id == project_id)
    if not include_all:
        if parent_folder_id is None:
            query = query.filter(Folder.parent_folder_id.is_(None))
        else:
            query = query.filter(Folder.parent_folder_id == parent_folder_id)
    if search:
        query = query.filter(Folder.name.ilike(f"%{search}%"))
    folders = query.order_by(Folder.name.asc()).all()
    return [f for f in folders if _employee_can_see_folder(f, current_employee)]


@router.post("", response_model=FolderOut)
def create_folder(
    payload: FolderCreate,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    project = db.get(Project, payload.project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    employee_organization_id = getattr(current_employee, "organization_id", None)
    is_admin = (getattr(current_employee, "role", "") or "").lower() == "admin"
    if not is_admin and employee_organization_id != project.organization_id:
        raise HTTPException(status_code=403, detail="You can only create folders for your own company")

    folder = Folder(**payload.model_dump())
    db.add(folder)
    db.commit()
    db.refresh(folder)
    ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)
    return folder
