import mimetypes
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..auth import create_access_token, get_current_employee, get_password_hash, verify_password
from ..database import INITIAL_ADMIN_PASSWORD_REQUIRED, get_db
from ..models import Department, Employee, Organization
from ..schemas import (
    EmployeeLogin,
    EmployeeOut,
    EmployeePasswordChange,
    EmployeeProfileUpdate,
    InitialSetupRequest,
    Token,
)
from ..services.storage_paths import resolve_storage_root

router = APIRouter(prefix="/auth", tags=["auth"])

_EMPLOYEE_IMAGE_ROOT = resolve_storage_root() / "employee_images"
_EMPLOYEE_IMAGE_ROOT.mkdir(parents=True, exist_ok=True)


def _pending_legacy_admin(db: Session) -> Employee | None:
    employee = (
        db.query(Employee)
        .filter(func.lower(Employee.login_name) == "admin")
        .first()
    )
    if (
        employee is not None
        and (employee.role or "").lower() == "admin"
        and employee.hashed_password == INITIAL_ADMIN_PASSWORD_REQUIRED
    ):
        return employee
    return None


@router.get("/setup/status")
def get_setup_status(db: Session = Depends(get_db)):
    pending_admin = _pending_legacy_admin(db)
    return {
        "setup_required": (
            db.query(Employee.id).first() is None or pending_admin is not None
        ),
        "legacy_admin_password_reset": pending_admin is not None,
        "organization_name": (
            pending_admin.organization.unique_name
            if pending_admin is not None and pending_admin.organization is not None
            else None
        ),
    }


@router.post("/setup", response_model=Token, status_code=status.HTTP_201_CREATED)
def initialize_application(
    payload: InitialSetupRequest,
    db: Session = Depends(get_db),
):
    if db.get_bind().dialect.name == "sqlite":
        db.connection().exec_driver_sql("BEGIN IMMEDIATE")

    has_employees = db.query(Employee.id).first() is not None
    pending_admin = _pending_legacy_admin(db) if has_employees else None
    if has_employees and pending_admin is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Initial setup has already been completed",
        )

    password_hash = get_password_hash(payload.password)
    if pending_admin is not None:
        admin_employee = pending_admin
        organization = db.get(Organization, pending_admin.organization_id)
        if organization is None:
            organization = Organization(
                unique_name=payload.organization_name,
                unique_code=f"ORG-{uuid4().hex[:8].upper()}",
            )
            db.add(organization)
            db.flush()
            admin_employee.organization_id = organization.id
        admin_employee.first_name = payload.first_name
        admin_employee.last_name = payload.last_name
        admin_employee.email = str(payload.email)
        admin_employee.login_name = payload.login_name
        admin_employee.hashed_password = password_hash
        admin_employee.is_super_admin = True
    else:
        organization = (
            db.query(Organization)
            .filter(Organization.unique_name == payload.organization_name)
            .first()
        )
        if organization is None:
            organization = Organization(
                unique_name=payload.organization_name,
                unique_code=f"ORG-{uuid4().hex[:8].upper()}",
            )
            db.add(organization)
            db.flush()

        admin_employee = Employee(
            organization_id=organization.id,
            first_name=payload.first_name,
            last_name=payload.last_name,
            email=str(payload.email),
            login_name=payload.login_name,
            hashed_password=password_hash,
            role="Admin",
            department="Management",
            is_super_admin=True,
        )
        db.add(admin_employee)

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Initial setup could not be completed with these account details",
        ) from exc

    return Token(
        access_token=create_access_token(
            admin_employee.id,
            organization_id=admin_employee.organization_id,
        )
    )


@router.post("/login", response_model=Token)
def login(payload: EmployeeLogin, db: Session = Depends(get_db)):
    # First try to find by login_name
    employee = db.query(Employee).filter(Employee.login_name == payload.username).first()

    # If not found, try by email
    if employee is None:
        employee = db.query(Employee).filter(Employee.email == payload.username).first()

    if employee is None or not verify_password(payload.password, employee.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid employee credentials")

    return Token(access_token=create_access_token(employee.id, organization_id=employee.organization_id))


@router.get("/employees/me", response_model=EmployeeOut)
def get_current_employee_info(
    current_employee: Employee = Depends(get_current_employee),
):
    return current_employee


@router.patch("/employees/me", response_model=EmployeeOut)
def update_current_employee_profile(
    payload: EmployeeProfileUpdate,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    """Self-service profile edit. Deliberately does not accept
    role/department/organization_id/login_name — those stay admin-only
    via PATCH /admin/employees/{employee_id}."""
    data = payload.model_dump(exclude_unset=True)

    new_email = data.get("email")
    if new_email and new_email != current_employee.email:
        existing = (
            db.query(Employee)
            .filter(Employee.email == new_email, Employee.id != current_employee.id)
            .first()
        )
        if existing:
            raise HTTPException(status_code=409, detail="Email already in use")

    for field, value in data.items():
        setattr(current_employee, field, value)

    db.commit()
    db.refresh(current_employee)
    return current_employee


@router.post("/employees/me/password")
def change_current_employee_password(
    payload: EmployeePasswordChange,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    if not verify_password(payload.current_password, current_employee.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Current password is incorrect")

    current_employee.hashed_password = get_password_hash(payload.new_password)
    db.commit()
    return {"status": "ok"}


@router.post("/employees/me/image", response_model=EmployeeOut)
def upload_current_employee_image(
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    if current_employee.image_url:
        old_path = Path(current_employee.image_url)
        if old_path.exists():
            old_path.unlink()

    safe_name = Path(image.filename or "profile_photo.bin").name
    disk_path = _EMPLOYEE_IMAGE_ROOT / f"{uuid4()}_{safe_name}"
    with disk_path.open("wb") as stream:
        stream.write(image.file.read())

    current_employee.image_url = str(disk_path)
    db.commit()
    db.refresh(current_employee)
    return current_employee


@router.get("/employees/me/image")
def download_current_employee_image(
    current_employee: Employee = Depends(get_current_employee),
):
    if not current_employee.image_url:
        raise HTTPException(status_code=404, detail="No profile photo set")

    path = Path(current_employee.image_url)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored profile photo is missing")

    media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    return FileResponse(path, media_type=media_type, filename=path.name)


@router.get("/employees/{employee_id}/image")
def download_employee_image(
    employee_id: str,
    db: Session = Depends(get_db),
    _current_employee: Employee = Depends(get_current_employee),
):
    employee = db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")
    if not employee.image_url:
        raise HTTPException(status_code=404, detail="Employee has no profile photo")

    path = Path(employee.image_url)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored profile photo is missing")

    media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    return FileResponse(path, media_type=media_type, filename=path.name)


@router.get("/employees", response_model=list[EmployeeOut])
def list_employees(db: Session = Depends(get_db)):
    return db.query(Employee).all()


@router.get("/departments", response_model=list[str])
def list_departments(
    db: Session = Depends(get_db),
    _current_employee: Employee = Depends(get_current_employee),
):
    names = db.query(Department.name).order_by(Department.name.asc()).all()
    result = [item[0].strip() for item in names if item[0] and item[0].strip()]
    if result:
        return result

    fallback = db.query(Employee.department).all()
    unique: list[str] = []
    seen: set[str] = set()
    for row in fallback:
        value = (row[0] or '').strip()
        if not value:
            continue
        key = value.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(value)
    unique.sort()
    return unique