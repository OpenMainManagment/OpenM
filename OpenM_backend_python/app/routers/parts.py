from pathlib import Path
import base64
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session, selectinload

from ..auth import get_current_admin, get_current_employee, get_current_manager_or_admin
from ..database import get_db
from ..models import Part, PartCategory, PartCategoryScope, PartDrawing
from ..schemas import (
    PartCategoryCreate,
    PartCategoryOut,
    PartDrawingOut,
    PartLinkChildrenRequest,
    PartOut,
)
from ..services.storage_paths import resolve_storage_root


router = APIRouter(prefix="/parts", tags=["parts"])

_PARTS_IMAGE_ROOT = resolve_storage_root() / "part_images"
_PARTS_IMAGE_ROOT.mkdir(parents=True, exist_ok=True)

_PARTS_CAD_ROOT = resolve_storage_root() / "part_cad"
_PARTS_CAD_ROOT.mkdir(parents=True, exist_ok=True)

_PARTS_DRAWINGS_ROOT = resolve_storage_root() / "part_drawings"
_PARTS_DRAWINGS_ROOT.mkdir(parents=True, exist_ok=True)

_PARTS_INSTRUCTIONS_ROOT = resolve_storage_root() / "part_instructions"
_PARTS_INSTRUCTIONS_ROOT.mkdir(parents=True, exist_ok=True)

_EXAMPLE_PART_IMAGE_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z6n0AAAAASUVORK5CYII="
)


def _ensure_example_image(file_name: str) -> str:
    path = _PARTS_IMAGE_ROOT / file_name
    if not path.exists():
        path.write_bytes(_EXAMPLE_PART_IMAGE_BYTES)
    return str(path)

def _normalize_part_role(value: str | None) -> str:
    role = (value or "main").strip().lower()
    if role not in {"main", "sub"}:
        raise HTTPException(status_code=400, detail="part_role must be 'main' or 'sub'")
    return role


def _normalize_part_status(value: str | None) -> str:
    status = (value or "active").strip().lower()
    if status not in {"active", "inactive"}:
        raise HTTPException(status_code=400, detail="status must be 'active' or 'inactive'")
    return status


def _expected_category_scope(part_role: str) -> PartCategoryScope:
    return PartCategoryScope.SUB if part_role == "sub" else PartCategoryScope.MAIN


def _normalize_category_name(value: str) -> str:
    name = value.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Category name is required")
    if len(name) > 120:
        raise HTTPException(status_code=400, detail="Category name must be <= 120 characters")
    return name


def _load_category_for_part(db: Session, category_id: str | None, part_role: str) -> PartCategory | None:
    normalized_category_id = (category_id or "").strip()
    if not normalized_category_id:
        return None
    category = db.get(PartCategory, normalized_category_id)
    if category is None:
        raise HTTPException(status_code=404, detail="Category not found")

    expected_scope = _expected_category_scope(part_role)
    if category.scope != expected_scope:
        raise HTTPException(
            status_code=400,
            detail=f"Category scope '{category.scope.value}' does not match part role '{part_role}'",
        )
    return category


def _is_ancestor(db: Session, ancestor_id: str, node_id: str) -> bool:
    """Return True if ancestor_id is in the parent chain of node_id."""
    current = db.get(Part, node_id)
    visited: set[str] = set()

    while current is not None and current.parent_part_id is not None:
        if current.id in visited:
            break
        visited.add(current.id)

        if current.parent_part_id == ancestor_id:
            return True

        current = db.get(Part, current.parent_part_id)

    return False


def _safe_unlink(file_path: str | None) -> None:
    if not file_path:
        return
    path = Path(file_path)
    if path.exists():
        path.unlink()


def _delete_part_files(part: Part) -> None:
    _safe_unlink(part.image_url)
    _safe_unlink(part.cad_file_url)
    _safe_unlink(part.instructions_url)
    for drawing in part.drawings:
        _safe_unlink(drawing.file_url)


@router.get("", response_model=list[PartOut])
def list_parts(
    parent_part_id: str | None = Query(default=None),
    include_all: bool = Query(default=False),
    part_role: str | None = Query(default=None),
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    query = db.query(Part).options(selectinload(Part.category))

    if not include_all:
        if parent_part_id is None:
            query = query.filter(Part.parent_part_id.is_(None))
        else:
            query = query.filter(Part.parent_part_id == parent_part_id)

    if search:
        query = query.filter(
            Part.name.ilike(f"%{search}%") | Part.id_number.ilike(f"%{search}%")
        )

    if part_role is not None and part_role.strip():
        query = query.filter(Part.part_role == _normalize_part_role(part_role))

    return query.order_by(Part.name.asc()).all()


@router.get("/categories", response_model=list[PartCategoryOut])
def list_part_categories(
    scope: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    query = db.query(PartCategory)
    normalized_scope = (scope or "").strip().lower()
    if normalized_scope:
        if normalized_scope not in {"main", "sub"}:
            raise HTTPException(status_code=400, detail="scope must be 'main' or 'sub'")
        query = query.filter(PartCategory.scope == PartCategoryScope(normalized_scope))
    return query.order_by(PartCategory.scope.asc(), PartCategory.name.asc()).all()


@router.post("/categories", response_model=PartCategoryOut)
def create_part_category(
    payload: PartCategoryCreate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_admin),
):
    name = _normalize_category_name(payload.name)
    exists = (
        db.query(PartCategory)
        .filter(PartCategory.scope == payload.scope)
        .filter(PartCategory.name.ilike(name))
        .first()
    )
    if exists is not None:
        raise HTTPException(status_code=400, detail="Category already exists for this scope")

    category = PartCategory(scope=payload.scope, name=name)
    db.add(category)
    db.commit()
    db.refresh(category)
    return category


@router.delete("/categories/{category_id}")
def delete_part_category(
    category_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_admin),
):
    category = db.get(PartCategory, category_id)
    if category is None:
        raise HTTPException(status_code=404, detail="Category not found")

    db.query(Part).filter(Part.category_id == category.id).update({Part.category_id: None})
    db.delete(category)
    db.commit()
    return {"status": "deleted"}


@router.post("", response_model=PartOut)
def create_part(
    name: str = Form(...),
    parent_part_id: str | None = Form(default=None),
    rival_part_id: str | None = Form(default=None),
    category_id: str | None = Form(default=None),
    description: str | None = Form(default=None),
    part_source: str | None = Form(default=None),
    status: str = Form(default="active"),
    notes: str | None = Form(default=None),
    part_role: str = Form(default="main"),
    id_number: str | None = Form(default=None),
    sell_price: float = Form(default=0.0),
    buy_price: float = Form(default=0.0),
    image: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_admin),
):
    if parent_part_id:
        parent = db.get(Part, parent_part_id)
        if parent is None:
            raise HTTPException(status_code=404, detail="Parent part not found")

    normalized_rival_part_id = (rival_part_id or "").strip() or None
    if normalized_rival_part_id is not None:
        rival = db.get(Part, normalized_rival_part_id)
        if rival is None:
            raise HTTPException(status_code=404, detail="Rival part not found")
        if rival.part_role != "main":
            raise HTTPException(status_code=400, detail="Rival part must be a main part")

    normalized_role = _normalize_part_role(part_role)
    normalized_status = _normalize_part_status(status)
    if parent_part_id:
        normalized_role = "sub"

    category = _load_category_for_part(db, category_id=category_id, part_role=normalized_role)

    image_url = None
    if image is not None:
        safe_name = Path(image.filename or "part_image.bin").name
        disk_path = _PARTS_IMAGE_ROOT / f"{uuid.uuid4()}_{safe_name}"
        with disk_path.open("wb") as stream:
            stream.write(image.file.read())
        image_url = str(disk_path)

    part = Part(
        parent_part_id=parent_part_id,
        rival_part_id=normalized_rival_part_id,
        category_id=category.id if category else None,
        name=name.strip(),
        description=(description or "").strip() or None,
        part_source=(part_source or "").strip() or None,
        status=normalized_status,
        notes=(notes or "").strip() or None,
        part_role=normalized_role,
        image_url=image_url,
        id_number=(id_number or "").strip() or None,
        sell_price=sell_price,
        buy_price=buy_price,
    )
    db.add(part)
    db.commit()
    db.refresh(part)
    return part


@router.post("/reset-from-structure", response_model=list[PartOut])
def reset_parts_from_structure(
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_admin),
):
    """Clear parts and recreate a fresh structure with seeded example main parts."""
    existing_parts = (
        db.query(Part)
        .options(selectinload(Part.drawings))
        .all()
    )

    for part in existing_parts:
        _delete_part_files(part)
        db.delete(part)

    db.flush()

    existing_categories = db.query(PartCategory).all()
    by_scope_name = {
        (category.scope.value, category.name.strip().lower()): category
        for category in existing_categories
    }
    defaults = {
        PartCategoryScope.MAIN: ["Vacuum Systems", "Robotic Arms", "Conveyor Modules"],
        PartCategoryScope.SUB: ["Sensors", "Mounting Kits", "Cables"],
    }
    for scope, names in defaults.items():
        for name in names:
            key = (scope.value, name.strip().lower())
            if key in by_scope_name:
                continue
            category = PartCategory(scope=scope, name=name)
            db.add(category)
            db.flush()
            by_scope_name[key] = category

    main_vacuum = by_scope_name[(PartCategoryScope.MAIN.value, "vacuum systems")]
    main_arms = by_scope_name[(PartCategoryScope.MAIN.value, "robotic arms")]
    main_conveyor = by_scope_name[(PartCategoryScope.MAIN.value, "conveyor modules")]

    sub_sensors = by_scope_name[(PartCategoryScope.SUB.value, "sensors")]
    sub_mounting = by_scope_name[(PartCategoryScope.SUB.value, "mounting kits")]
    sub_cables = by_scope_name[(PartCategoryScope.SUB.value, "cables")]

    root_main_components = Part(
        name="Main Components",
        part_role="main",
        id_number="MAIN-ROOT",
        category_id=main_vacuum.id,
        status="active",
    )
    root_sub_components = Part(
        name="Sub Components",
        part_role="main",
        id_number="SUB-ROOT",
        category_id=main_arms.id,
        status="active",
    )

    db.add(root_main_components)
    db.add(root_sub_components)
    db.flush()

    example_main_parts = [
        Part(
            name="Vacuum Base Unit",
            parent_part_id=root_main_components.id,
            part_role="main",
            id_number="EX-MAIN-VAC-001",
            image_url=_ensure_example_image("example_vacuum_base.png"),
            buy_price=180.0,
            sell_price=265.0,
            category_id=main_vacuum.id,
            part_source="Vacuum",
            status="active",
        ),
        Part(
            name="Vacuum Gripper Module",
            parent_part_id=root_main_components.id,
            part_role="main",
            id_number="EX-MAIN-VAC-002",
            image_url=_ensure_example_image("example_vacuum_gripper.png"),
            buy_price=140.0,
            sell_price=220.0,
            category_id=main_vacuum.id,
            part_source="Vacuum",
            status="active",
        ),
        Part(
            name="Robotic Arm Alpha",
            parent_part_id=root_main_components.id,
            part_role="main",
            id_number="EX-MAIN-ARM-001",
            image_url=_ensure_example_image("example_robotic_arm_alpha.png"),
            buy_price=420.0,
            sell_price=620.0,
            category_id=main_arms.id,
            part_source="Robotic arm",
            status="active",
        ),
        Part(
            name="Robotic Arm Flex",
            parent_part_id=root_main_components.id,
            part_role="main",
            id_number="EX-MAIN-ARM-002",
            image_url=_ensure_example_image("example_robotic_arm_flex.png"),
            buy_price=390.0,
            sell_price=590.0,
            category_id=main_arms.id,
            part_source="Robotic arm",
            status="active",
        ),
        Part(
            name="Conveyor Drive Unit",
            parent_part_id=root_main_components.id,
            part_role="main",
            id_number="EX-MAIN-CNV-001",
            buy_price=310.0,
            sell_price=460.0,
            category_id=main_conveyor.id,
            part_source="Conveyor",
            status="active",
        ),
        Part(
            name="Conveyor End Module",
            parent_part_id=root_main_components.id,
            part_role="main",
            id_number="EX-MAIN-CNV-002",
            buy_price=275.0,
            sell_price=430.0,
            category_id=main_conveyor.id,
            part_source="Conveyor",
            status="active",
        ),
    ]

    example_sub_parts = [
        Part(
            parent_part_id=root_sub_components.id,
            name="Vacuum Pressure Sensor",
            part_role="sub",
            id_number="EX-SUB-SEN-001",
            buy_price=35.0,
            sell_price=58.0,
            category_id=sub_sensors.id,
            part_source="Sensor",
            status="active",
        ),
        Part(
            parent_part_id=root_sub_components.id,
            name="Arm Position Sensor",
            part_role="sub",
            id_number="EX-SUB-SEN-002",
            buy_price=42.0,
            sell_price=66.0,
            category_id=sub_sensors.id,
            part_source="Sensor",
            status="active",
        ),
        Part(
            parent_part_id=root_sub_components.id,
            name="Universal Mount Plate",
            part_role="sub",
            id_number="EX-SUB-MNT-001",
            buy_price=22.0,
            sell_price=39.0,
            category_id=sub_mounting.id,
            part_source="Mount",
            status="active",
        ),
        Part(
            parent_part_id=root_sub_components.id,
            name="Heavy Duty Bracket",
            part_role="sub",
            id_number="EX-SUB-MNT-002",
            buy_price=19.0,
            sell_price=33.0,
            category_id=sub_mounting.id,
            part_source="Mount",
            status="active",
        ),
        Part(
            parent_part_id=root_sub_components.id,
            name="Servo Cable 1.5m",
            part_role="sub",
            id_number="EX-SUB-CBL-001",
            buy_price=7.5,
            sell_price=14.0,
            category_id=sub_cables.id,
            part_source="Cable",
            status="active",
        ),
        Part(
            parent_part_id=root_sub_components.id,
            name="Power Cable 3m",
            part_role="sub",
            id_number="EX-SUB-CBL-002",
            buy_price=9.0,
            sell_price=16.0,
            category_id=sub_cables.id,
            part_source="Cable",
            status="active",
        ),
    ]

    for example in example_main_parts:
        db.add(example)
    for example in example_sub_parts:
        db.add(example)

    db.commit()

    return db.query(Part).filter(Part.parent_part_id.is_(None)).order_by(Part.name.asc()).all()


@router.get("/{part_id}", response_model=PartOut)
def get_part(
    part_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")
    return part


@router.patch("/{part_id}", response_model=PartOut)
def update_part(
    part_id: str,
    name: str = Form(...),
    parent_part_id: str | None = Form(default=None),
    rival_part_id: str | None = Form(default=None),
    category_id: str | None = Form(default=None),
    description: str | None = Form(default=None),
    part_source: str | None = Form(default=None),
    status: str = Form(default="active"),
    notes: str | None = Form(default=None),
    part_role: str = Form(default="main"),
    id_number: str | None = Form(default=None),
    sell_price: float = Form(default=0.0),
    buy_price: float = Form(default=0.0),
    image: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    if parent_part_id == part.id:
        raise HTTPException(status_code=400, detail="Part cannot be parent of itself")

    normalized_rival_part_id = (rival_part_id or "").strip() or None
    if normalized_rival_part_id == part.id:
        raise HTTPException(status_code=400, detail="Part cannot be rival of itself")

    if parent_part_id:
        parent = db.get(Part, parent_part_id)
        if parent is None:
            raise HTTPException(status_code=404, detail="Parent part not found")

    if normalized_rival_part_id is not None:
        rival = db.get(Part, normalized_rival_part_id)
        if rival is None:
            raise HTTPException(status_code=404, detail="Rival part not found")
        if rival.part_role != "main":
            raise HTTPException(status_code=400, detail="Rival part must be a main part")

    normalized_role = _normalize_part_role(part_role)
    normalized_status = _normalize_part_status(status)
    if parent_part_id:
        normalized_role = "sub"

    category = _load_category_for_part(db, category_id=category_id, part_role=normalized_role)

    part.name = name.strip()
    part.parent_part_id = parent_part_id
    part.rival_part_id = normalized_rival_part_id
    part.category_id = category.id if category else None
    part.description = (description or "").strip() or None
    part.part_source = (part_source or "").strip() or None
    part.status = normalized_status
    part.notes = (notes or "").strip() or None
    part.part_role = normalized_role
    part.id_number = (id_number or "").strip() or None
    part.sell_price = sell_price
    part.buy_price = buy_price

    if image is not None:
        if part.image_url:
            old_path = Path(part.image_url)
            if old_path.exists():
                old_path.unlink()

        safe_name = Path(image.filename or "part_image.bin").name
        disk_path = _PARTS_IMAGE_ROOT / f"{uuid.uuid4()}_{safe_name}"
        with disk_path.open("wb") as stream:
            stream.write(image.file.read())
        part.image_url = str(disk_path)

    db.commit()
    db.refresh(part)
    return part


@router.post("/{parent_part_id}/children")
def link_existing_parts(
    parent_part_id: str,
    payload: PartLinkChildrenRequest,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_admin),
):
    parent = db.get(Part, parent_part_id)
    if parent is None:
        raise HTTPException(status_code=404, detail="Parent part not found")

    if not payload.child_part_ids:
        return {"status": "ok", "linked": 0}

    children = db.query(Part).filter(Part.id.in_(payload.child_part_ids)).all()
    found_ids = {part.id for part in children}
    missing_ids = [item for item in payload.child_part_ids if item not in found_ids]
    if missing_ids:
        raise HTTPException(status_code=404, detail=f"Parts not found: {', '.join(missing_ids)}")

    for child in children:
        if child.id == parent.id:
            raise HTTPException(status_code=400, detail="Part cannot be linked to itself")
        if _is_ancestor(db, ancestor_id=child.id, node_id=parent.id):
            raise HTTPException(status_code=400, detail="Invalid link: circular part hierarchy")

    for child in children:
        child.parent_part_id = parent.id
        child.part_role = "sub"

    db.commit()
    return {"status": "ok", "linked": len(children)}


@router.delete("/{part_id}")
def delete_part(
    part_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_admin),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    children = db.query(Part).filter(Part.parent_part_id == part.id).all()
    for child in children:
        child.parent_part_id = None
        child.part_role = "main"

    if part.image_url:
        image_path = Path(part.image_url)
        if image_path.exists():
            image_path.unlink()

    db.delete(part)
    db.commit()
    return {"status": "deleted"}


@router.get("/{part_id}/image")
def download_part_image(
    part_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    if not part.image_url:
        raise HTTPException(status_code=404, detail="Part has no image")

    path = Path(part.image_url)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored part image is missing")

    return FileResponse(path=path, filename=path.name)


# ── CAD file ────────────────────────────────────────────────────────────────

@router.post("/{part_id}/cad", response_model=PartOut)
def upload_cad_file(
    part_id: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    if part.cad_file_url:
        old = Path(part.cad_file_url)
        if old.exists():
            old.unlink()

    safe_name = Path(file.filename or "cad_file.bin").name
    disk_path = _PARTS_CAD_ROOT / f"{uuid.uuid4()}_{safe_name}"
    with disk_path.open("wb") as f:
        f.write(file.file.read())

    part.cad_file_url = str(disk_path)
    part.cad_file_name = safe_name
    db.commit()
    db.refresh(part)
    return part


@router.delete("/{part_id}/cad", response_model=PartOut)
def delete_cad_file(
    part_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    if part.cad_file_url:
        old = Path(part.cad_file_url)
        if old.exists():
            old.unlink()
        part.cad_file_url = None
        part.cad_file_name = None
        db.commit()
        db.refresh(part)
    return part


@router.get("/{part_id}/cad/download")
def download_cad_file(
    part_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")
    if not part.cad_file_url:
        raise HTTPException(status_code=404, detail="No CAD file for this part")
    path = Path(part.cad_file_url)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored CAD file is missing")
    return FileResponse(path=path, filename=part.cad_file_name or path.name)


# ── 2D Drawings ─────────────────────────────────────────────────────────────

@router.post("/{part_id}/drawings", response_model=PartDrawingOut)
def upload_drawing(
    part_id: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    safe_name = Path(file.filename or "drawing.bin").name
    disk_path = _PARTS_DRAWINGS_ROOT / f"{uuid.uuid4()}_{safe_name}"
    with disk_path.open("wb") as f:
        f.write(file.file.read())

    drawing = PartDrawing(
        part_id=part_id,
        file_url=str(disk_path),
        file_name=safe_name,
    )
    db.add(drawing)
    db.commit()
    db.refresh(drawing)
    return drawing


@router.delete("/{part_id}/drawings/{drawing_id}")
def delete_drawing(
    part_id: str,
    drawing_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    drawing = db.get(PartDrawing, drawing_id)
    if drawing is None or drawing.part_id != part_id:
        raise HTTPException(status_code=404, detail="Drawing not found")

    path = Path(drawing.file_url)
    if path.exists():
        path.unlink()

    db.delete(drawing)
    db.commit()
    return {"status": "deleted"}


@router.get("/{part_id}/drawings/{drawing_id}/download")
def download_drawing(
    part_id: str,
    drawing_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    drawing = db.get(PartDrawing, drawing_id)
    if drawing is None or drawing.part_id != part_id:
        raise HTTPException(status_code=404, detail="Drawing not found")
    path = Path(drawing.file_url)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored drawing file is missing")
    return FileResponse(path=path, filename=drawing.file_name)


# ── Instructions PDF ─────────────────────────────────────────────────────────

@router.post("/{part_id}/instructions", response_model=PartOut)
def upload_instructions(
    part_id: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    if part.instructions_url:
        old = Path(part.instructions_url)
        if old.exists():
            old.unlink()

    safe_name = Path(file.filename or "instructions.pdf").name
    disk_path = _PARTS_INSTRUCTIONS_ROOT / f"{uuid.uuid4()}_{safe_name}"
    with disk_path.open("wb") as f:
        f.write(file.file.read())

    part.instructions_url = str(disk_path)
    part.instructions_name = safe_name
    db.commit()
    db.refresh(part)
    return part


@router.delete("/{part_id}/instructions", response_model=PartOut)
def delete_instructions(
    part_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")

    if part.instructions_url:
        old = Path(part.instructions_url)
        if old.exists():
            old.unlink()
        part.instructions_url = None
        part.instructions_name = None
        db.commit()
        db.refresh(part)
    return part


@router.get("/{part_id}/instructions/download")
def download_instructions(
    part_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    part = db.get(Part, part_id)
    if part is None:
        raise HTTPException(status_code=404, detail="Part not found")
    if not part.instructions_url:
        raise HTTPException(status_code=404, detail="No instructions for this part")
    path = Path(part.instructions_url)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored instructions file is missing")
    return FileResponse(path=path, filename=part.instructions_name or path.name)
