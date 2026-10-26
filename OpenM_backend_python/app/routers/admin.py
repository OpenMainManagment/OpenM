from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete
from sqlalchemy.orm import Session

from ..auth import get_current_admin, get_password_hash
from ..company_validation import (
    get_employee_company_id,
    validate_company_exists,
    verify_company_data_isolation,
)
from ..database import get_db
from ..models import (
    Organization,
    OrganizationRole,
    OrganizationRolePermission,
    Department,
    DepartmentFolderTemplate,
    DepartmentProjectAction,
    DepartmentRole,
    Employee,
    Folder,
    FolderDepartmentAccess,
    FolderUserAccess,
    ProjectFolderTemplate,
    ProjectGanttStepTemplate,
    ProjectGanttSubStepTemplate,
    ProjectFolderTemplateDemoFile,
)
from ..schemas import (
    OrganizationRoleCreate,
    OrganizationRoleOut,
    OrganizationRoleUpdate,
    DepartmentCreate,
    DepartmentOut,
    DepartmentUpdate,
    EmployeeCreate,
    EmployeeOut,
    EmployeeUpdate,
    FolderAccessOut,
    FolderAddUserAccess,
    FolderDepartmentAccessOut,
    FolderSetDepartmentAccess,
    FolderUserAccessOut,
    ProjectFolderTemplateCreate,
    ProjectFolderTemplateDemoFileCreate,
    ProjectFolderTemplateDemoFileOut,
    ProjectFolderTemplateOut,
    ProjectGanttStepTemplateCreate,
    ProjectGanttStepTemplateOut,
    ProjectGanttStepTemplateUpdate,
    ProjectGanttSubStepTemplateCreate,
    ProjectGanttSubStepTemplateUpdate,
)
from ..services.storage_paths import resolve_demo_files_root


router = APIRouter(prefix="/admin", tags=["admin"])
_DEMO_FILES_ROOT = resolve_demo_files_root()


def _normalize_permissions(values: list[str] | None) -> list[str]:
    if not values:
        return []
    normalized: list[str] = []
    seen: set[str] = set()
    for value in values:
        key = value.strip()
        if not key:
            continue
        if key in seen:
            continue
        seen.add(key)
        normalized.append(key)
    return normalized


def _to_company_role_out(role: OrganizationRole) -> OrganizationRoleOut:
    permissions = sorted(permission.permission_key for permission in role.permissions)
    return OrganizationRoleOut(
        id=role.id,
        organization_id=role.organization_id,
        name=role.name,
        permissions=permissions,
    )


def _normalize_folder_templates(values: list[str] | None) -> list[str]:
    if not values:
        return []
    normalized: list[str] = []
    seen: set[str] = set()
    for value in values:
        name = value.strip()
        if not name:
            continue
        lower_name = name.lower()
        if lower_name in seen:
            continue
        seen.add(lower_name)
        normalized.append(name)
    return normalized


def _normalize_project_actions(values: list[str] | None) -> list[str]:
    if not values:
        return []
    normalized: list[str] = []
    seen: set[str] = set()
    for value in values:
        name = value.strip().lower()
        if not name:
            continue
        if name in seen:
            continue
        seen.add(name)
        normalized.append(name)
    return normalized


def _ensure_roles_belong_to_company(db: Session, organization_id: str, role_ids: list[str]) -> list[OrganizationRole]:
    if not role_ids:
        return []
    roles = db.query(OrganizationRole).filter(OrganizationRole.id.in_(role_ids)).all()
    if len(roles) != len(set(role_ids)):
        raise HTTPException(status_code=400, detail="One or more roles do not exist")
    if any(role.organization_id != organization_id for role in roles):
        raise HTTPException(status_code=400, detail="One or more roles are not in the selected Organization")
    return roles


def _ensure_roles_not_in_other_departments(
    db: Session,
    role_ids: list[str],
    current_department_id: str | None = None,
):
    if not role_ids:
        return

    query = db.query(DepartmentRole).filter(DepartmentRole.role_id.in_(role_ids))
    if current_department_id is not None:
        query = query.filter(DepartmentRole.department_id != current_department_id)

    existing_links = query.all()
    if not existing_links:
        return

    conflicting_role_ids = {link.role_id for link in existing_links}
    conflicting_roles = db.query(OrganizationRole).filter(OrganizationRole.id.in_(conflicting_role_ids)).all()
    conflicting_names = sorted(role.name for role in conflicting_roles)
    if conflicting_names:
        raise HTTPException(
            status_code=409,
            detail="These roles are already assigned to another department: " + ", ".join(conflicting_names),
        )
    raise HTTPException(status_code=409, detail="One or more roles are already assigned to another department")


def _to_department_out(department: Department) -> DepartmentOut:
    ordered_links = sorted(department.role_links, key=lambda link: (link.role.name.lower(), link.role.name))
    ordered_templates = sorted(department.folder_templates, key=lambda item: item.sort_order)
    ordered_actions = sorted(department.project_actions, key=lambda item: item.sort_order)
    return DepartmentOut(
        id=department.id,
        organization_id=department.organization_id,
        name=department.name,
        role_ids=[link.role_id for link in ordered_links],
        role_names=[link.role.name for link in ordered_links],
        folder_templates=[item.name for item in ordered_templates],
        project_actions=[item.action_key for item in ordered_actions],
    )


@router.get("/employees", response_model=list[EmployeeOut])
def list_employees(
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    # Only return employees from the admin's Organization
    admin_company_id = get_employee_company_id(admin, db)
    return (
        db.query(Employee)
        .filter(Employee.organization_id == admin_company_id)
        .order_by(Employee.last_name.asc(), Employee.first_name.asc())
        .all()
    )


@router.post("/employees", response_model=EmployeeOut)
def create_employee(
    payload: EmployeeCreate,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    # Validate admin can create employees for this Organization
    admin_company_id = get_employee_company_id(admin, db)
    
    # If payload specifies a organization_id, ensure it matches admin's Organization
    if payload.organization_id and payload.organization_id != admin_company_id:
        raise HTTPException(
            status_code=403,
            detail="You can only create employees for your own Organization"
        )
    
    # Validate Organization exists
    validate_company_exists(payload.organization_id or admin_company_id, db)
    
    # Check for duplicate login_name
    existing = db.query(Employee).filter(Employee.login_name == payload.login_name).first()
    if existing:
        raise HTTPException(status_code=409, detail="login_name already exists")

    # Use admin's Organization if not specified
    employee_company_id = payload.organization_id or admin_company_id
    
    employee = Employee(
        first_name=payload.first_name,
        last_name=payload.last_name,
        email=payload.email,
        login_name=payload.login_name,
        hashed_password=get_password_hash(payload.password),
        role=payload.role,
        department=payload.department,
        organization_id=employee_company_id,
    )
    db.add(employee)
    db.commit()
    db.refresh(employee)
    return employee


@router.patch("/employees/{employee_id}", response_model=EmployeeOut)
def update_employee(
    employee_id: str,
    payload: EmployeeUpdate,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    employee = db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    # Validate admin can update this employee (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    if employee.organization_id != admin_company_id:
        raise HTTPException(
            status_code=403,
            detail="You can only update employees in your own Organization"
        )

    data = payload.model_dump(exclude_unset=True)
    
    # Prevent changing organization_id via PATCH (unless explicitly allowed)
    if "organization_id" in data and data["organization_id"] != admin_company_id:
        raise HTTPException(
            status_code=403,
            detail="You cannot change an employee's Organization assignment"
        )
    
    for key, value in data.items():
        setattr(employee, key, value)

    db.commit()
    db.refresh(employee)
    return employee


@router.delete("/employees/{employee_id}")
def delete_employee(
    employee_id: str,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    employee = db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    if employee.id == admin.id:
        raise HTTPException(status_code=400, detail="You cannot delete your own admin account")

    # Validate admin can delete this employee (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    if employee.organization_id != admin_company_id:
        raise HTTPException(
            status_code=403,
            detail="You can only delete employees from your own Organization"
        )

    db.delete(employee)
    db.commit()
    return {"status": "deleted"}


@router.get("/company-roles", response_model=list[OrganizationRoleOut])
def list_company_roles(
    organization_id: str,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    # Validate admin can access this Organization
    admin_company_id = get_employee_company_id(admin, db)
    validate_company_exists(organization_id, db)
    verify_company_data_isolation(admin_company_id, organization_id)

    roles = (
        db.query(OrganizationRole)
        .filter(OrganizationRole.organization_id == organization_id)
        .order_by(OrganizationRole.name.asc())
        .all()
    )
    return [_to_company_role_out(role) for role in roles]


@router.post("/company-roles", response_model=OrganizationRoleOut)
def create_company_role(
    payload: OrganizationRoleCreate,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    # Validate admin can create roles for this Organization
    admin_company_id = get_employee_company_id(admin, db)
    validate_company_exists(payload.organization_id, db)
    verify_company_data_isolation(admin_company_id, payload.organization_id)

    role_name = payload.name.strip()
    if not role_name:
        raise HTTPException(status_code=400, detail="Role name is required")

    existing = (
        db.query(OrganizationRole)
        .filter(
            OrganizationRole.organization_id == payload.organization_id,
            OrganizationRole.name.ilike(role_name),
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Role already exists for this Organization")

    permissions = _normalize_permissions(payload.permissions)
    role = OrganizationRole(organization_id=payload.organization_id, name=role_name)
    db.add(role)
    db.flush()

    for permission in permissions:
        db.add(OrganizationRolePermission(role_id=role.id, permission_key=permission))

    db.commit()
    db.refresh(role)
    return _to_company_role_out(role)


@router.patch("/company-roles/{role_id}", response_model=OrganizationRoleOut)
def update_company_role(
    role_id: str,
    payload: OrganizationRoleUpdate,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    role = db.get(OrganizationRole, role_id)
    if role is None:
        raise HTTPException(status_code=404, detail="Role not found")

    # Validate admin can update this role (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, role.organization_id)

    if payload.name is not None:
        role_name = payload.name.strip()
        if not role_name:
            raise HTTPException(status_code=400, detail="Role name is required")

        existing = (
            db.query(OrganizationRole)
            .filter(
                OrganizationRole.organization_id == role.organization_id,
                OrganizationRole.name.ilike(role_name),
                OrganizationRole.id != role.id,
            )
            .first()
        )
        if existing is not None:
            raise HTTPException(status_code=409, detail="Role already exists for this Organization")

        role.name = role_name

    if payload.permissions is not None:
        permissions = _normalize_permissions(payload.permissions)
        db.execute(delete(OrganizationRolePermission).where(OrganizationRolePermission.role_id == role.id))
        for permission in permissions:
            db.add(OrganizationRolePermission(role_id=role.id, permission_key=permission))

    db.commit()
    db.refresh(role)
    return _to_company_role_out(role)


@router.delete("/company-roles/{role_id}")
def delete_company_role(
    role_id: str,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    role = db.get(OrganizationRole, role_id)
    if role is None:
        raise HTTPException(status_code=404, detail="Role not found")

    # Validate admin can delete this role (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, role.organization_id)

    db.delete(role)
    db.commit()
    return {"status": "deleted"}


@router.get("/departments", response_model=list[DepartmentOut])
def list_departments(
    organization_id: str,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    # Use admin Organization context for resilient UX:
    # if the UI sends an outdated/wrong organization_id, do not break the screen.
    admin_company_id = get_employee_company_id(admin, db)

    requested_company_id = (organization_id or "").strip()
    if not requested_company_id:
        requested_company_id = admin_company_id

    # If requested Organization does not exist, fall back to admin's Organization.
    try:
        validate_company_exists(requested_company_id, db)
    except HTTPException:
        requested_company_id = admin_company_id

    # If requested Organization is outside admin scope, fall back to admin's Organization.
    try:
        verify_company_data_isolation(admin_company_id, requested_company_id)
    except HTTPException:
        requested_company_id = admin_company_id

    departments = (
        db.query(Department)
        .filter(Department.organization_id == requested_company_id)
        .order_by(Department.name.asc())
        .all()
    )
    return [_to_department_out(item) for item in departments]


@router.post("/departments", response_model=DepartmentOut)
def create_department(
    payload: DepartmentCreate,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    # Validate admin can create departments for this Organization
    admin_company_id = get_employee_company_id(admin, db)
    validate_company_exists(payload.organization_id, db)
    verify_company_data_isolation(admin_company_id, payload.organization_id)

    department_name = payload.name.strip()
    if not department_name:
        raise HTTPException(status_code=400, detail="Department name is required")

    existing = (
        db.query(Department)
        .filter(
            Department.organization_id == payload.organization_id,
            Department.name.ilike(department_name),
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Department already exists for this Organization")

    roles = _ensure_roles_belong_to_company(db, payload.organization_id, payload.role_ids)
    _ensure_roles_not_in_other_departments(db, payload.role_ids)
    templates = _normalize_folder_templates(payload.folder_templates)
    project_actions = _normalize_project_actions(payload.project_actions)

    department = Department(organization_id=payload.organization_id, name=department_name)
    db.add(department)
    db.flush()

    for role in roles:
        db.add(DepartmentRole(department_id=department.id, role_id=role.id))
    for index, template_name in enumerate(templates):
        db.add(
            DepartmentFolderTemplate(
                department_id=department.id,
                name=template_name,
                sort_order=index,
            )
        )
    for index, action_key in enumerate(project_actions):
        db.add(
            DepartmentProjectAction(
                department_id=department.id,
                action_key=action_key,
                sort_order=index,
            )
        )

    db.commit()
    db.refresh(department)
    return _to_department_out(department)


@router.patch("/departments/{department_id}", response_model=DepartmentOut)
def update_department(
    department_id: str,
    payload: DepartmentUpdate,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    department = db.get(Department, department_id)
    if department is None:
        raise HTTPException(status_code=404, detail="Department not found")

    # Validate admin can update this department (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, department.organization_id)

    if payload.name is not None:
        department_name = payload.name.strip()
        if not department_name:
            raise HTTPException(status_code=400, detail="Department name is required")

        existing = (
            db.query(Department)
            .filter(
                Department.organization_id == department.organization_id,
                Department.name.ilike(department_name),
                Department.id != department.id,
            )
            .first()
        )
        if existing is not None:
            raise HTTPException(status_code=409, detail="Department already exists for this Organization")
        department.name = department_name

    if payload.role_ids is not None:
        roles = _ensure_roles_belong_to_company(db, department.organization_id, payload.role_ids)
        _ensure_roles_not_in_other_departments(
            db,
            payload.role_ids,
            current_department_id=department.id,
        )
        db.execute(delete(DepartmentRole).where(DepartmentRole.department_id == department.id))
        for role in roles:
            db.add(DepartmentRole(department_id=department.id, role_id=role.id))

    if payload.folder_templates is not None:
        templates = _normalize_folder_templates(payload.folder_templates)
        db.execute(
            delete(DepartmentFolderTemplate).where(
                DepartmentFolderTemplate.department_id == department.id
            )
        )
        for index, template_name in enumerate(templates):
            db.add(
                DepartmentFolderTemplate(
                    department_id=department.id,
                    name=template_name,
                    sort_order=index,
                )
            )

    if payload.project_actions is not None:
        project_actions = _normalize_project_actions(payload.project_actions)
        db.execute(
            delete(DepartmentProjectAction).where(
                DepartmentProjectAction.department_id == department.id
            )
        )
        for index, action_key in enumerate(project_actions):
            db.add(
                DepartmentProjectAction(
                    department_id=department.id,
                    action_key=action_key,
                    sort_order=index,
                )
            )

    db.commit()
    db.refresh(department)
    return _to_department_out(department)


@router.delete("/departments/{department_id}")
def delete_department(
    department_id: str,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    department = db.get(Department, department_id)
    if department is None:
        raise HTTPException(status_code=404, detail="Department not found")

    # Validate admin can delete this department (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, department.organization_id)

    db.delete(department)
    db.commit()
    return {"status": "deleted"}


# ── Folder access admin endpoints ─────────────────────────────────────────────

def _build_folder_access_out(folder: Folder) -> FolderAccessOut:
    return FolderAccessOut(
        folder_id=folder.id,
        folder_name=folder.name,
        project_id=folder.project_id,
        department_access=[
            FolderDepartmentAccessOut(
                id=da.id,
                department_id=da.department_id,
                department_name=da.department.name,
            )
            for da in folder.department_access
        ],
        user_access=[
            FolderUserAccessOut(
                id=ua.id,
                employee_id=ua.employee_id,
                employee_name=f"{ua.employee.first_name} {ua.employee.last_name}",
            )
            for ua in folder.user_access
        ],
    )


@router.get("/folders/{folder_id}/access", response_model=FolderAccessOut)
def get_folder_access(
    folder_id: str,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    folder = db.get(Folder, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")
    
    # Validate admin can access this folder (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, folder.project.organization_id)
    
    return _build_folder_access_out(folder)


@router.put("/folders/{folder_id}/department-access", response_model=FolderAccessOut)
def set_folder_department_access(
    folder_id: str,
    payload: FolderSetDepartmentAccess,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Replace the department access list for a folder.
    Passing an empty list removes all restrictions (folder becomes visible to everyone).
    """
    folder = db.get(Folder, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    # Validate admin can update this folder (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, folder.project.organization_id)

    # Validate that all supplied department IDs exist and belong to the same Organization
    for dept_id in payload.department_ids:
        dept = db.get(Department, dept_id)
        if dept is None:
            raise HTTPException(status_code=404, detail=f"Department {dept_id} not found")
        # Ensure department belongs to the folder's Organization
        if dept.organization_id != folder.project.organization_id:
            raise HTTPException(
                status_code=403,
                detail=f"Department {dept_id} does not belong to this folder's Organization"
            )

    db.execute(delete(FolderDepartmentAccess).where(FolderDepartmentAccess.folder_id == folder_id))
    for dept_id in payload.department_ids:
        db.add(FolderDepartmentAccess(folder_id=folder_id, department_id=dept_id))
    db.commit()
    db.refresh(folder)
    return _build_folder_access_out(folder)


# ── Project folder template endpoints ────────────────────────────────────────

_DEFAULT_FOLDER_NAMES = ["Angebot", "Auftrag", "Nacharbeit"]
_DEFAULT_GANTT_TEMPLATE_STATUS_KEYS = [
    "Sale",
    "Construction",
    "Procurement",
    "Installation",
    "Programming",
    "Delivery",
    "Commissioning",
    "Final Acceptance",
    "Completed",
]


def _resolve_demo_template(template_id: str) -> Path:
    candidate = (_DEMO_FILES_ROOT / template_id).resolve()
    root = _DEMO_FILES_ROOT.resolve()
    if root not in candidate.parents:
        raise HTTPException(status_code=400, detail="Invalid demo template id")
    if not candidate.is_file():
        raise HTTPException(status_code=404, detail="Demo template not found")
    return candidate


def _validate_duration_days(value: int) -> int:
    if value < 1:
        raise HTTPException(status_code=400, detail="duration_days must be at least 1")
    if value > 365:
        raise HTTPException(status_code=400, detail="duration_days must be at most 365")
    return value


def _list_company_gantt_templates(db: Session, organization_id: str) -> list[ProjectGanttStepTemplate]:
    return (
        db.query(ProjectGanttStepTemplate)
        .filter(ProjectGanttStepTemplate.organization_id == organization_id)
        .order_by(ProjectGanttStepTemplate.sort_order.asc(), ProjectGanttStepTemplate.created_at.asc())
        .all()
    )


@router.get("/project-folder-templates", response_model=list[ProjectFolderTemplateOut])
def list_project_folder_templates(
    organization_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    organization = db.get(Organization, organization_id)
    if organization is None:
        raise HTTPException(status_code=404, detail="Organization not found")
    return (
        db.query(ProjectFolderTemplate)
        .filter(ProjectFolderTemplate.organization_id == organization_id)
        .order_by(ProjectFolderTemplate.sort_order.asc(), ProjectFolderTemplate.name.asc())
        .all()
    )


@router.get("/project-gantt-step-templates", response_model=list[ProjectGanttStepTemplateOut])
def list_project_gantt_step_templates(
    organization_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    organization = db.get(Organization, organization_id)
    if organization is None:
        raise HTTPException(status_code=404, detail="Organization not found")
    return _list_company_gantt_templates(db, organization_id)


@router.post("/project-gantt-step-templates", response_model=list[ProjectGanttStepTemplateOut])
def add_project_gantt_step_template(
    organization_id: str,
    payload: ProjectGanttStepTemplateCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    organization = db.get(Organization, organization_id)
    if organization is None:
        raise HTTPException(status_code=404, detail="Organization not found")

    title = payload.title.strip()
    status_key = payload.status_key.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required")
    if not status_key:
        raise HTTPException(status_code=400, detail="status_key is required")

    duration_days = _validate_duration_days(payload.duration_days)
    sort_order = (
        db.query(ProjectGanttStepTemplate)
        .filter(ProjectGanttStepTemplate.organization_id == organization_id)
        .count()
    )

    db.add(
        ProjectGanttStepTemplate(
            organization_id=organization_id,
            status_key=status_key,
            title=title,
            description=(payload.description or "").strip() or None,
            duration_days=duration_days,
            sort_order=sort_order,
        )
    )
    db.commit()
    return _list_company_gantt_templates(db, organization_id)


@router.post("/project-gantt-step-templates/init-defaults", response_model=list[ProjectGanttStepTemplateOut])
def init_default_project_gantt_step_templates(
    organization_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    organization = db.get(Organization, organization_id)
    if organization is None:
        raise HTTPException(status_code=404, detail="Organization not found")

    existing = _list_company_gantt_templates(db, organization_id)
    if existing:
        return existing

    for index, status_key in enumerate(_DEFAULT_GANTT_TEMPLATE_STATUS_KEYS):
        db.add(
            ProjectGanttStepTemplate(
                organization_id=organization_id,
                status_key=status_key,
                title=status_key,
                duration_days=7,
                sort_order=index,
            )
        )
    db.commit()
    return _list_company_gantt_templates(db, organization_id)


@router.patch("/project-gantt-step-templates/{template_id}", response_model=list[ProjectGanttStepTemplateOut])
def update_project_gantt_step_template(
    template_id: str,
    payload: ProjectGanttStepTemplateUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    template = db.get(ProjectGanttStepTemplate, template_id)
    if template is None:
        raise HTTPException(status_code=404, detail="Template not found")

    if payload.status_key is not None:
        status_key = payload.status_key.strip()
        if not status_key:
            raise HTTPException(status_code=400, detail="status_key cannot be empty")
        template.status_key = status_key

    if payload.title is not None:
        title = payload.title.strip()
        if not title:
            raise HTTPException(status_code=400, detail="title cannot be empty")
        template.title = title

    if payload.description is not None:
        template.description = payload.description.strip() or None

    if payload.duration_days is not None:
        template.duration_days = _validate_duration_days(payload.duration_days)

    db.commit()
    return _list_company_gantt_templates(db, template.organization_id)


@router.delete("/project-gantt-step-templates/{template_id}", response_model=list[ProjectGanttStepTemplateOut])
def delete_project_gantt_step_template(
    template_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    template = db.get(ProjectGanttStepTemplate, template_id)
    if template is None:
        raise HTTPException(status_code=404, detail="Template not found")
    organization_id = template.organization_id
    db.delete(template)
    db.commit()

    remaining = _list_company_gantt_templates(db, organization_id)
    for index, item in enumerate(remaining):
        item.sort_order = index
    db.commit()
    return _list_company_gantt_templates(db, organization_id)


@router.post(
    "/project-gantt-step-templates/{template_id}/sub-steps",
    response_model=list[ProjectGanttStepTemplateOut],
)
def add_project_gantt_sub_step_template(
    template_id: str,
    payload: ProjectGanttSubStepTemplateCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    template = db.get(ProjectGanttStepTemplate, template_id)
    if template is None:
        raise HTTPException(status_code=404, detail="Template not found")

    title = payload.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required")

    duration_days = _validate_duration_days(payload.duration_days)
    sort_order = (
        db.query(ProjectGanttSubStepTemplate)
        .filter(ProjectGanttSubStepTemplate.parent_template_id == template_id)
        .count()
    )

    db.add(
        ProjectGanttSubStepTemplate(
            parent_template_id=template_id,
            title=title,
            description=(payload.description or "").strip() or None,
            duration_days=duration_days,
            sort_order=sort_order,
        )
    )
    db.commit()
    return _list_company_gantt_templates(db, template.organization_id)


@router.patch(
    "/project-gantt-sub-step-templates/{sub_template_id}",
    response_model=list[ProjectGanttStepTemplateOut],
)
def update_project_gantt_sub_step_template(
    sub_template_id: str,
    payload: ProjectGanttSubStepTemplateUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    sub_template = db.get(ProjectGanttSubStepTemplate, sub_template_id)
    if sub_template is None:
        raise HTTPException(status_code=404, detail="Sub-step template not found")

    if payload.title is not None:
        title = payload.title.strip()
        if not title:
            raise HTTPException(status_code=400, detail="title cannot be empty")
        sub_template.title = title

    if payload.description is not None:
        sub_template.description = payload.description.strip() or None

    if payload.duration_days is not None:
        sub_template.duration_days = _validate_duration_days(payload.duration_days)

    db.commit()
    parent_template = db.get(ProjectGanttStepTemplate, sub_template.parent_template_id)
    return _list_company_gantt_templates(db, parent_template.organization_id)


@router.delete(
    "/project-gantt-sub-step-templates/{sub_template_id}",
    response_model=list[ProjectGanttStepTemplateOut],
)
def delete_project_gantt_sub_step_template(
    sub_template_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    sub_template = db.get(ProjectGanttSubStepTemplate, sub_template_id)
    if sub_template is None:
        raise HTTPException(status_code=404, detail="Sub-step template not found")

    parent_template_id = sub_template.parent_template_id
    parent_template = db.get(ProjectGanttStepTemplate, parent_template_id)
    organization_id = parent_template.organization_id

    db.delete(sub_template)
    db.commit()

    remaining = (
        db.query(ProjectGanttSubStepTemplate)
        .filter(ProjectGanttSubStepTemplate.parent_template_id == parent_template_id)
        .order_by(ProjectGanttSubStepTemplate.sort_order.asc())
        .all()
    )
    for index, item in enumerate(remaining):
        item.sort_order = index
    db.commit()
    return _list_company_gantt_templates(db, organization_id)


@router.post("/project-folder-templates", response_model=list[ProjectFolderTemplateOut])
def add_project_folder_template(
    organization_id: str,
    payload: ProjectFolderTemplateCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    organization = db.get(Organization, organization_id)
    if organization is None:
        raise HTTPException(status_code=404, detail="Organization not found")

    parent_template_id = payload.parent_template_id
    if parent_template_id is not None:
        parent = db.get(ProjectFolderTemplate, parent_template_id)
        if parent is None:
            raise HTTPException(status_code=404, detail="Parent template not found")
        if parent.organization_id != organization_id:
            raise HTTPException(status_code=400, detail="Parent template is not in the selected Organization")

    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Folder name is required")

    existing = (
        db.query(ProjectFolderTemplate)
        .filter(
            ProjectFolderTemplate.organization_id == organization_id,
            ProjectFolderTemplate.name.ilike(name),
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="A template with this name already exists")

    count = (
        db.query(ProjectFolderTemplate)
        .filter(
            ProjectFolderTemplate.organization_id == organization_id,
            ProjectFolderTemplate.parent_template_id == parent_template_id,
        )
        .count()
    )
    db.add(
        ProjectFolderTemplate(
            organization_id=organization_id,
            parent_template_id=parent_template_id,
            name=name,
            sort_order=count,
        )
    )
    db.commit()
    return (
        db.query(ProjectFolderTemplate)
        .filter(ProjectFolderTemplate.organization_id == organization_id)
        .order_by(ProjectFolderTemplate.sort_order.asc(), ProjectFolderTemplate.name.asc())
        .all()
    )


@router.post("/project-folder-templates/init-defaults", response_model=list[ProjectFolderTemplateOut])
def init_default_project_folder_templates(
    organization_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    organization = db.get(Organization, organization_id)
    if organization is None:
        raise HTTPException(status_code=404, detail="Organization not found")

    existing = (
        db.query(ProjectFolderTemplate)
        .filter(ProjectFolderTemplate.organization_id == organization_id)
        .order_by(ProjectFolderTemplate.sort_order.asc())
        .all()
    )
    existing_names = {item.name.strip().lower() for item in existing}

    next_order = len(existing)
    for name in _DEFAULT_FOLDER_NAMES:
        key = name.strip().lower()
        if key in existing_names:
            continue
        db.add(
            ProjectFolderTemplate(
                organization_id=organization_id,
                name=name,
                sort_order=next_order,
            )
        )
        existing_names.add(key)
        next_order += 1

    db.commit()
    return (
        db.query(ProjectFolderTemplate)
        .filter(ProjectFolderTemplate.organization_id == organization_id)
        .order_by(ProjectFolderTemplate.sort_order.asc(), ProjectFolderTemplate.name.asc())
        .all()
    )


@router.delete(
    "/project-folder-templates/{template_id}",
    response_model=list[ProjectFolderTemplateOut],
)
def delete_project_folder_template(
    template_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    template = db.get(ProjectFolderTemplate, template_id)
    if template is None:
        raise HTTPException(status_code=404, detail="Template not found")
    organization_id = template.organization_id
    db.delete(template)
    db.commit()

    # Re-index sort_order so it stays contiguous
    remaining = (
        db.query(ProjectFolderTemplate)
        .filter(ProjectFolderTemplate.organization_id == organization_id)
        .order_by(ProjectFolderTemplate.sort_order.asc())
        .all()
    )
    for i, t in enumerate(remaining):
        t.sort_order = i
    db.commit()
    return remaining


@router.get(
    "/project-folder-templates/{template_id}/demo-files",
    response_model=list[ProjectFolderTemplateDemoFileOut],
)
def list_project_folder_template_demo_files(
    template_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    template = db.get(ProjectFolderTemplate, template_id)
    if template is None:
        raise HTTPException(status_code=404, detail="Template not found")
    return (
        db.query(ProjectFolderTemplateDemoFile)
        .filter(ProjectFolderTemplateDemoFile.folder_template_id == template_id)
        .order_by(
            ProjectFolderTemplateDemoFile.sort_order.asc(),
            ProjectFolderTemplateDemoFile.demo_template_id.asc(),
        )
        .all()
    )


@router.post(
    "/project-folder-templates/{template_id}/demo-files",
    response_model=list[ProjectFolderTemplateDemoFileOut],
)
def add_project_folder_template_demo_file(
    template_id: str,
    payload: ProjectFolderTemplateDemoFileCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    template = db.get(ProjectFolderTemplate, template_id)
    if template is None:
        raise HTTPException(status_code=404, detail="Template not found")

    _resolve_demo_template(payload.demo_template_id)

    target_name = (payload.target_file_name or "").strip() or None
    if target_name:
        target_name = Path(target_name).name
        if not target_name:
            raise HTTPException(status_code=400, detail="Invalid target file name")

    existing = (
        db.query(ProjectFolderTemplateDemoFile)
        .filter(
            ProjectFolderTemplateDemoFile.folder_template_id == template_id,
            ProjectFolderTemplateDemoFile.demo_template_id == payload.demo_template_id,
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Demo file already assigned to this folder template")

    count = (
        db.query(ProjectFolderTemplateDemoFile)
        .filter(ProjectFolderTemplateDemoFile.folder_template_id == template_id)
        .count()
    )
    db.add(
        ProjectFolderTemplateDemoFile(
            folder_template_id=template_id,
            demo_template_id=payload.demo_template_id,
            target_file_name=target_name,
            sort_order=count,
        )
    )
    db.commit()
    return (
        db.query(ProjectFolderTemplateDemoFile)
        .filter(ProjectFolderTemplateDemoFile.folder_template_id == template_id)
        .order_by(
            ProjectFolderTemplateDemoFile.sort_order.asc(),
            ProjectFolderTemplateDemoFile.demo_template_id.asc(),
        )
        .all()
    )


@router.delete(
    "/project-folder-template-demo-files/{demo_file_id}",
    response_model=list[ProjectFolderTemplateDemoFileOut],
)
def delete_project_folder_template_demo_file(
    demo_file_id: str,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin),
):
    item = db.get(ProjectFolderTemplateDemoFile, demo_file_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Template demo file not found")

    template_id = item.folder_template_id
    db.delete(item)
    db.commit()

    remaining = (
        db.query(ProjectFolderTemplateDemoFile)
        .filter(ProjectFolderTemplateDemoFile.folder_template_id == template_id)
        .order_by(ProjectFolderTemplateDemoFile.sort_order.asc())
        .all()
    )
    for i, row in enumerate(remaining):
        row.sort_order = i
    db.commit()
    return remaining


@router.post("/folders/{folder_id}/user-access", response_model=FolderAccessOut)
def add_folder_user_access(
    folder_id: str,
    payload: FolderAddUserAccess,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    """Grant a specific user personal access to a folder."""
    folder = db.get(Folder, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")
    
    employee = db.get(Employee, payload.employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    # Validate admin can grant access (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, folder.project.organization_id)
    verify_company_data_isolation(admin_company_id, employee.organization_id)

    existing = (
        db.query(FolderUserAccess)
        .filter(
            FolderUserAccess.folder_id == folder_id,
            FolderUserAccess.employee_id == payload.employee_id,
        )
        .first()
    )
    if existing is None:
        db.add(FolderUserAccess(folder_id=folder_id, employee_id=payload.employee_id))
        db.commit()
        db.refresh(folder)
    return _build_folder_access_out(folder)


@router.delete("/folders/{folder_id}/user-access/{employee_id}", response_model=FolderAccessOut)
def remove_folder_user_access(
    folder_id: str,
    employee_id: str,
    db: Session = Depends(get_db),
    admin=Depends(get_current_admin),
):
    folder = db.get(Folder, folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    # Validate admin can revoke access (same Organization)
    admin_company_id = get_employee_company_id(admin, db)
    verify_company_data_isolation(admin_company_id, folder.project.organization_id)

    db.execute(
        delete(FolderUserAccess).where(
            FolderUserAccess.folder_id == folder_id,
            FolderUserAccess.employee_id == employee_id,
        )
    )
    db.commit()
    db.refresh(folder)
    return _build_folder_access_out(folder)
