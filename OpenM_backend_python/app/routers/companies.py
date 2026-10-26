from pathlib import Path
from uuid import uuid4

import mimetypes

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..auth import get_current_employee, get_current_manager_or_admin, get_current_super_admin, get_password_hash
from ..database import get_db
from ..models import Contact, Customer, CustomerCompany, Employee, Organization
from ..schemas import (
    CustomerCompanyCreate,
    CustomerCompanyOut,
    CustomerCompanyUpdate,
    OrganizationCreate,
    OrganizationOut,
    OrganizationUpdate,
)
from ..services.storage_paths import resolve_storage_root


router = APIRouter(prefix="/companies", tags=["companies"])

_CUSTOMER_IMAGE_ROOT = resolve_storage_root() / "customer_images"
_CUSTOMER_IMAGE_ROOT.mkdir(parents=True, exist_ok=True)


def _raise_company_conflict_from_integrity_error(exc: IntegrityError) -> None:
    message = str(getattr(exc, "orig", exc)).lower()
    if "customer_companies.unique_name" in message:
        raise HTTPException(status_code=409, detail="A client company with this name already exists") from exc
    if "customer_companies.unique_code" in message:
        raise HTTPException(status_code=409, detail="A client company with this code already exists") from exc
    if "organizations.unique_name" in message:
        raise HTTPException(status_code=409, detail="A company with this name already exists") from exc
    if "organizations.unique_code" in message:
        raise HTTPException(status_code=409, detail="A company with this code already exists") from exc
    raise HTTPException(status_code=400, detail="Company data violates database constraints") from exc


def _flush_with_company_conflict_handling(db: Session) -> None:
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        _raise_company_conflict_from_integrity_error(exc)


def _generate_unique_code(db: Session) -> str:
    while True:
        candidate = f"C-{uuid4().hex[:8].upper()}"
        exists = db.query(Organization).filter(Organization.unique_code == candidate).first()
        if not exists:
            return candidate


def _generate_unique_customer_company_code(db: Session) -> str:
    while True:
        candidate = f"CC-{uuid4().hex[:8].upper()}"
        exists = db.query(CustomerCompany).filter(CustomerCompany.unique_code == candidate).first()
        if not exists:
            return candidate


def _normalize_customers_payload(customers_data: list[dict]) -> list[dict]:
    normalized: list[dict] = []
    for customer_data in customers_data:
        first_name = (customer_data.get("first_name") or "").strip()
        last_name = (customer_data.get("last_name") or "").strip()
        if not first_name or not last_name:
            continue

        payload = {
            "first_name": first_name,
            "last_name": last_name,
            "gender": customer_data.get("gender"),
            "email": customer_data.get("email"),
            "role": customer_data.get("role"),
            "phone_number": customer_data.get("phone_number"),
            "mobile_number": customer_data.get("mobile_number"),
            "image_url": customer_data.get("image_url"),
        }
        payload = {
            key: value
            for key, value in payload.items()
            if value is not None and (not isinstance(value, str) or value.strip() != "")
        }
        normalized.append(payload)
    return normalized


def _resolve_employee_organization_id(
    db: Session,
    current_employee,
    *,
    allow_fallback_for_privileged: bool,
) -> str | None:
    employee_organization_id = getattr(current_employee, "organization_id", None)
    if employee_organization_id:
        existing_organization = db.get(Organization, employee_organization_id)
        if existing_organization is not None:
            return employee_organization_id
        employee_organization_id = None

    if not allow_fallback_for_privileged:
        return None

    role = (getattr(current_employee, "role", None) or "").lower()
    if role not in {"manager", "admin"}:
        return None

    fallback_organization = db.query(Organization).order_by(Organization.unique_name.asc()).first()
    if fallback_organization is None:
        fallback_organization = Organization(
            unique_name="Default Company",
            unique_code=_generate_unique_code(db),
        )
        db.add(fallback_organization)
        _flush_with_company_conflict_handling(db)

    current_employee.organization_id = fallback_organization.id
    db.commit()
    return fallback_organization.id


@router.get("", response_model=list[OrganizationOut])
def list_companies(
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_employee=Depends(get_current_employee),
):
    # Keep list endpoint lightweight to avoid loading optional relations
    # (e.g. legacy contact table schemas during migration).
    query = db.query(
        Organization.id,
        Organization.unique_name,
        Organization.unique_code,
        Organization.logo_url,
    )

    if not current_employee.is_super_admin:
        # Only super admins see other organizations; everyone else is
        # limited to their own.
        employee_organization_id = getattr(current_employee, "organization_id", None)
        if employee_organization_id is None:
            return []
        query = query.filter(Organization.id == employee_organization_id)

    if search:
        query = query.filter(Organization.unique_name.ilike(f"%{search}%"))

    rows = query.order_by(Organization.unique_name.asc()).all()
    return [
        OrganizationOut(
            id=row.id,
            unique_name=row.unique_name,
            unique_code=row.unique_code,
            logo_url=row.logo_url,
            contact=None,
        )
        for row in rows
    ]


@router.get("/client-companies", response_model=list[CustomerCompanyOut])
@router.get("/customer-companies", response_model=list[CustomerCompanyOut])
def list_customer_companies(
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_employee=Depends(get_current_employee),
):
    employee_organization_id = _resolve_employee_organization_id(
        db,
        current_employee,
        allow_fallback_for_privileged=True,
    )
    if employee_organization_id is None:
        return []

    query = db.query(CustomerCompany).filter(CustomerCompany.organization_id == employee_organization_id)
    if search:
        query = query.filter(CustomerCompany.unique_name.ilike(f"%{search}%"))

    return query.order_by(CustomerCompany.unique_name.asc()).all()


@router.post("/client-companies", response_model=CustomerCompanyOut)
@router.post("/customer-companies", response_model=CustomerCompanyOut)
def create_customer_company(
    payload: CustomerCompanyCreate,
    db: Session = Depends(get_db),
    current_employee=Depends(get_current_manager_or_admin),
):
    employee_organization_id = _resolve_employee_organization_id(
        db,
        current_employee,
        allow_fallback_for_privileged=True,
    )
    if employee_organization_id is None:
        raise HTTPException(
            status_code=400,
            detail="Current employee has no company. Please assign a company first.",
        )

    data = payload.model_dump()
    contact_data = data.pop("contact", None)
    customers_data = _normalize_customers_payload(data.pop("customers", []))
    head_customer_index = data.pop("head_customer_index", None)
    if not data.get("unique_code"):
        data["unique_code"] = _generate_unique_customer_company_code(db)

    customer_company = CustomerCompany(**data, organization_id=employee_organization_id)
    if contact_data:
        customer_company.contact = Contact(**contact_data)
    db.add(customer_company)
    _flush_with_company_conflict_handling(db)

    created_customers = []
    for customer_data in customers_data:
        customer = Customer(customer_company_id=customer_company.id, **customer_data)
        db.add(customer)
        created_customers.append(customer)

    _flush_with_company_conflict_handling(db)

    if created_customers and head_customer_index is None:
        head_customer_index = 0

    if head_customer_index is not None and created_customers:
        head_customer = created_customers[head_customer_index]
        customer_company.main_customer_id = head_customer.id
        head_name = f"{head_customer.first_name} {head_customer.last_name}".strip()
        if customer_company.contact is None:
            customer_company.contact = Contact(customer_company_id=customer_company.id, head_of_company=head_name)
        else:
            customer_company.contact.head_of_company = head_name

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _raise_company_conflict_from_integrity_error(exc)

    db.refresh(customer_company)
    return customer_company


@router.patch("/client-companies/{customer_company_id}", response_model=CustomerCompanyOut)
@router.patch("/customer-companies/{customer_company_id}", response_model=CustomerCompanyOut)
def update_customer_company(
    customer_company_id: str,
    payload: CustomerCompanyUpdate,
    db: Session = Depends(get_db),
    current_employee=Depends(get_current_manager_or_admin),
):
    employee_organization_id = _resolve_employee_organization_id(
        db,
        current_employee,
        allow_fallback_for_privileged=True,
    )
    customer_company = db.query(CustomerCompany).filter(CustomerCompany.id == customer_company_id).first()
    if not customer_company:
        raise HTTPException(status_code=404, detail="Client company not found")
    if employee_organization_id is None or customer_company.organization_id != employee_organization_id:
        raise HTTPException(status_code=403, detail="You can only update customer companies from your own company")

    updates = payload.model_dump(exclude_none=True)
    contact_updates = updates.pop("contact", None)
    customers_updates = updates.pop("customers", None)
    if customers_updates is not None:
        customers_updates = _normalize_customers_payload(customers_updates)
    head_customer_index = updates.pop("head_customer_index", None)
    for field, value in updates.items():
        setattr(customer_company, field, value)

    if contact_updates is not None:
        if customer_company.contact is None:
            customer_company.contact = Contact(customer_company_id=customer_company.id)
        for field, value in contact_updates.items():
            setattr(customer_company.contact, field, value)

    if customers_updates is not None:
        db.query(Customer).filter(Customer.customer_company_id == customer_company.id).delete(
            synchronize_session=False,
        )
        _flush_with_company_conflict_handling(db)

        created_customers = []
        for customer_data in customers_updates:
            customer = Customer(customer_company_id=customer_company.id, **customer_data)
            db.add(customer)
            created_customers.append(customer)

        _flush_with_company_conflict_handling(db)

        if created_customers and head_customer_index is None:
            head_customer_index = 0

        if head_customer_index is not None and created_customers:
            head_customer = created_customers[head_customer_index]
            customer_company.main_customer_id = head_customer.id
            head_name = f"{head_customer.first_name} {head_customer.last_name}".strip()
            if customer_company.contact is None:
                customer_company.contact = Contact(customer_company_id=customer_company.id, head_of_company=head_name)
            else:
                customer_company.contact.head_of_company = head_name
        else:
            customer_company.main_customer_id = None

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _raise_company_conflict_from_integrity_error(exc)

    db.refresh(customer_company)
    return customer_company


@router.post("", response_model=OrganizationOut, status_code=201)
def create_company(
    payload: OrganizationCreate,
    db: Session = Depends(get_db),
    _super_admin=Depends(get_current_super_admin),
):
    data = payload.model_dump()
    contact_data = data.pop("contact", None)
    initial_admin = data.pop("initial_admin", None)
    if not data.get("unique_code"):
        data["unique_code"] = _generate_unique_code(db)

    organization = Organization(**data)
    if contact_data:
        organization.contact = Contact(**contact_data)
    db.add(organization)

    if initial_admin:
        organization.employees.append(
            Employee(
                first_name=initial_admin["first_name"].strip(),
                last_name=initial_admin["last_name"].strip(),
                email=str(initial_admin["email"]),
                login_name=initial_admin["login_name"].strip(),
                hashed_password=get_password_hash(initial_admin["password"]),
                role="Admin",
                department="Management",
            )
        )

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        message = str(getattr(exc, "orig", exc)).lower()
        if "employees." in message:
            raise HTTPException(status_code=409, detail="An employee with this email or login name already exists") from exc
        _raise_company_conflict_from_integrity_error(exc)

    db.refresh(organization)
    return organization


@router.patch("/{company_id}", response_model=OrganizationOut)
def update_company(
    company_id: str,
    payload: OrganizationUpdate,
    db: Session = Depends(get_db),
    current_employee=Depends(get_current_manager_or_admin),
):
    if not current_employee.is_super_admin and current_employee.organization_id != company_id:
        raise HTTPException(status_code=403, detail="You can only update your own organization")

    organization = db.query(Organization).filter(Organization.id == company_id).first()
    if not organization:
        raise HTTPException(status_code=404, detail="Company not found")

    updates = payload.model_dump(exclude_none=True)
    contact_updates = updates.pop("contact", None)
    for field, value in updates.items():
        setattr(organization, field, value)

    if contact_updates is not None:
        if organization.contact is None:
            organization.contact = Contact(organization_id=organization.id)
        for field, value in contact_updates.items():
            setattr(organization.contact, field, value)

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _raise_company_conflict_from_integrity_error(exc)

    db.refresh(organization)
    return organization


@router.post("/customers/{customer_id}/image", response_model=CustomerCompanyOut)
def upload_customer_image(
    customer_id: str,
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    customer = db.get(Customer, customer_id)
    if customer is None:
        raise HTTPException(status_code=404, detail="Customer not found")

    if customer.image_url:
        old_path = Path(customer.image_url)
        if old_path.exists():
            old_path.unlink()

    safe_name = Path(image.filename or "business_card.bin").name
    disk_path = _CUSTOMER_IMAGE_ROOT / f"{uuid4()}_{safe_name}"
    with disk_path.open("wb") as stream:
        stream.write(image.file.read())

    customer.image_url = str(disk_path)
    db.commit()
    db.refresh(customer)
    return customer.customer_company


@router.get("/customers/{customer_id}/image")
def download_customer_image(
    customer_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    customer = db.get(Customer, customer_id)
    if customer is None:
        raise HTTPException(status_code=404, detail="Customer not found")
    if not customer.image_url:
        raise HTTPException(status_code=404, detail="Customer has no image")

    path = Path(customer.image_url)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored customer image is missing")

    media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    return FileResponse(path, media_type=media_type, filename=path.name)
