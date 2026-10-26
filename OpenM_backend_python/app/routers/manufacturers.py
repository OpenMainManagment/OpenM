"""Router for admin-managed Manufacturers: companies/websites parts can be
ordered from. Its own dedicated table, scoped per company."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..auth import get_current_admin, get_current_employee
from ..database import get_db
from ..models import Employee, Manufacturer
from ..schemas import ManufacturerCreate, ManufacturerOut, ManufacturerUpdate

router = APIRouter(prefix="/manufacturers", tags=["manufacturers"])


def _list_company_manufacturers(db: Session, organization_id: str) -> list[Manufacturer]:
    return (
        db.query(Manufacturer)
        .filter(Manufacturer.organization_id == organization_id)
        .order_by(Manufacturer.name.asc())
        .all()
    )


@router.get("", response_model=list[ManufacturerOut])
def list_manufacturers(
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    """Any authenticated employee can read the list (needed to pick a
    manufacturer when ordering a part), but only admins can edit it."""
    return _list_company_manufacturers(db, current_employee.organization_id)


@router.post("", response_model=list[ManufacturerOut])
def add_manufacturer(
    payload: ManufacturerCreate,
    db: Session = Depends(get_db),
    current_admin: Employee = Depends(get_current_admin),
):
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="name is required")

    db.add(
        Manufacturer(
            organization_id=current_admin.organization_id,
            name=name,
            website=(payload.website or "").strip() or None,
            contact_email=(payload.contact_email or "").strip() or None,
            phone_number=(payload.phone_number or "").strip() or None,
            notes=(payload.notes or "").strip() or None,
        )
    )
    db.commit()
    return _list_company_manufacturers(db, current_admin.organization_id)


@router.patch("/{manufacturer_id}", response_model=list[ManufacturerOut])
def update_manufacturer(
    manufacturer_id: str,
    payload: ManufacturerUpdate,
    db: Session = Depends(get_db),
    current_admin: Employee = Depends(get_current_admin),
):
    manufacturer = db.get(Manufacturer, manufacturer_id)
    if manufacturer is None or manufacturer.organization_id != current_admin.organization_id:
        raise HTTPException(status_code=404, detail="Manufacturer not found")

    if payload.name is not None:
        name = payload.name.strip()
        if not name:
            raise HTTPException(status_code=400, detail="name cannot be empty")
        manufacturer.name = name
    if payload.website is not None:
        manufacturer.website = payload.website.strip() or None
    if payload.contact_email is not None:
        manufacturer.contact_email = payload.contact_email.strip() or None
    if payload.phone_number is not None:
        manufacturer.phone_number = payload.phone_number.strip() or None
    if payload.notes is not None:
        manufacturer.notes = payload.notes.strip() or None

    db.commit()
    return _list_company_manufacturers(db, current_admin.organization_id)


@router.delete("/{manufacturer_id}", response_model=list[ManufacturerOut])
def delete_manufacturer(
    manufacturer_id: str,
    db: Session = Depends(get_db),
    current_admin: Employee = Depends(get_current_admin),
):
    manufacturer = db.get(Manufacturer, manufacturer_id)
    if manufacturer is None or manufacturer.organization_id != current_admin.organization_id:
        raise HTTPException(status_code=404, detail="Manufacturer not found")

    db.delete(manufacturer)
    db.commit()
    return _list_company_manufacturers(db, current_admin.organization_id)
