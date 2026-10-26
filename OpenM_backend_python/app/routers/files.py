from pathlib import Path
import mimetypes
import shutil

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..auth import get_current_employee, get_current_manager_or_admin
from ..database import get_db
from ..models import Document, Folder
from ..schemas import CreateFromDemoRequest, DemoTemplateOut, DocumentOut, FileMoveRequest, FileRenameRequest
from ..services.storage_paths import (
    build_unique_file_path,
    ensure_folder_storage_dir,
    resolve_demo_files_root,
    resolve_storage_root,
)


router = APIRouter(prefix="/files", tags=["files"])


def _detect_category(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in {".doc", ".docx", ".odt", ".rtf"}:
        return "word"
    if ext in {".xls", ".xlsx", ".ods", ".csv"}:
        return "excel"
    if ext in {".ppt", ".pptx", ".odp"}:
        return "powerpoint"
    return "other"


def _resolve_demo_template(template_id: str) -> Path:
    candidate = (_DEMO_FILES_ROOT / template_id).resolve()
    root = _DEMO_FILES_ROOT.resolve()
    if root not in candidate.parents:
        raise HTTPException(status_code=400, detail="Invalid demo template id")
    if not candidate.is_file():
        raise HTTPException(status_code=404, detail="Demo template not found")
    return candidate


_STORAGE_ROOT = resolve_storage_root()
_DEMO_FILES_ROOT = resolve_demo_files_root()


@router.get("", response_model=list[DocumentOut])
def list_files(
    folder_id: str,
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    query = db.query(Document).filter(Document.folder_id == folder_id)
    if search:
        query = query.filter(Document.file_name.ilike(f"%{search}%"))
    return query.order_by(Document.created_at.desc()).all()


@router.post("/upload", response_model=DocumentOut)
def upload_file(
    folder_id: str | None = Form(default=None),
    folder_id_query: str | None = Query(default=None, alias="folder_id"),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_employee=Depends(get_current_manager_or_admin),
):
    resolved_folder_id = folder_id or folder_id_query
    if not resolved_folder_id:
        raise HTTPException(status_code=422, detail="folder_id is required")

    folder = db.get(Folder, resolved_folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    safe_name = Path(file.filename or "file.bin").name
    target_dir = ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)
    disk_path = build_unique_file_path(target_dir, safe_name)

    with disk_path.open("wb") as stream:
        stream.write(file.file.read())

    doc = Document(
        folder_id=resolved_folder_id,
        project_id=folder.project_id,
        file_name=safe_name,
        file_path=str(disk_path),
        mime_type=file.content_type,
        uploaded_by_employee_id=current_employee.id,
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return doc


@router.get("/demo-templates", response_model=list[DemoTemplateOut])
def list_demo_templates(
    category: str | None = Query(default=None),
    _current_employee=Depends(get_current_employee),
):
    normalized_category = (category or "").strip().lower()
    templates: list[DemoTemplateOut] = []

    for path in _DEMO_FILES_ROOT.rglob("*"):
        if not path.is_file():
            continue
        detected_category = _detect_category(path)
        if normalized_category and detected_category != normalized_category:
            continue
        templates.append(
            DemoTemplateOut(
                id=str(path.relative_to(_DEMO_FILES_ROOT)).replace("\\", "/"),
                file_name=path.name,
                category=detected_category,
            )
        )

    templates.sort(key=lambda item: item.file_name.lower())
    return templates


@router.post("/create-from-demo", response_model=DocumentOut)
def create_file_from_demo(
    payload: CreateFromDemoRequest,
    db: Session = Depends(get_db),
    current_employee=Depends(get_current_manager_or_admin),
):
    folder = db.get(Folder, payload.folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")

    source_path = _resolve_demo_template(payload.template_id)
    target_name = (payload.file_name or "").strip() or source_path.name
    target_name = Path(target_name).name
    if not target_name:
        raise HTTPException(status_code=400, detail="Invalid file name")

    target_dir = ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)
    disk_path = build_unique_file_path(target_dir, target_name)
    shutil.copyfile(source_path, disk_path)
    mime_type = mimetypes.guess_type(target_name)[0]

    doc = Document(
        folder_id=folder.id,
        project_id=folder.project_id,
        file_name=target_name,
        file_path=str(disk_path),
        mime_type=mime_type,
        uploaded_by_employee_id=current_employee.id,
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return doc


@router.patch("/{file_id}/rename", response_model=DocumentOut)
def rename_file(
    file_id: str,
    payload: FileRenameRequest,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    doc = db.get(Document, file_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="File not found")

    new_name = Path(payload.file_name.strip()).name
    if not new_name:
        raise HTTPException(status_code=400, detail="Invalid file name")

    folder = db.get(Folder, doc.folder_id)
    if folder is not None:
        target_dir = ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)
        current_path = Path(doc.file_path)

        if current_path.exists():
            next_path = build_unique_file_path(target_dir, new_name)
            shutil.move(str(current_path), str(next_path))
            doc.file_path = str(next_path)

    doc.file_name = new_name
    db.commit()
    db.refresh(doc)
    return doc


@router.patch("/{file_id}/move", response_model=DocumentOut)
def move_file(
    file_id: str,
    payload: FileMoveRequest,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    doc = db.get(Document, file_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="File not found")

    folder = db.get(Folder, payload.folder_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="Target folder not found")

    current_path = Path(doc.file_path)
    if current_path.exists():
        target_dir = ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)
        next_path = build_unique_file_path(target_dir, doc.file_name)
        shutil.move(str(current_path), str(next_path))
        doc.file_path = str(next_path)

    doc.folder_id = folder.id
    doc.project_id = folder.project_id
    db.commit()
    db.refresh(doc)
    return doc


@router.put("/{file_id}/content", response_model=DocumentOut)
def replace_file_content(
    file_id: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    doc = db.get(Document, file_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="File not found")

    disk_path = Path(doc.file_path)
    disk_path.parent.mkdir(parents=True, exist_ok=True)
    with disk_path.open("wb") as stream:
        stream.write(file.file.read())

    if file.content_type:
        doc.mime_type = file.content_type

    db.commit()
    db.refresh(doc)
    return doc


@router.post("/migrate-storage-layout")
def migrate_storage_layout(
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    docs = db.query(Document).order_by(Document.created_at.asc()).all()

    moved_count = 0
    unchanged_count = 0
    skipped_missing_file = 0
    skipped_missing_folder = 0
    errors: list[dict[str, str]] = []

    for doc in docs:
        folder = db.get(Folder, doc.folder_id)
        if folder is None:
            skipped_missing_folder += 1
            continue

        current_path = Path(doc.file_path)
        if not current_path.exists():
            skipped_missing_file += 1
            continue

        target_dir = ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)
        try:
            is_same_dir = current_path.resolve().parent == target_dir.resolve()
        except OSError:
            is_same_dir = current_path.parent == target_dir

        if is_same_dir:
            unchanged_count += 1
            continue

        try:
            next_path = build_unique_file_path(target_dir, doc.file_name)
            shutil.move(str(current_path), str(next_path))
            doc.file_path = str(next_path)
            moved_count += 1
        except Exception as exc:  # noqa: BLE001
            errors.append({"document_id": doc.id, "error": str(exc)})

    db.commit()
    return {
        "status": "ok",
        "total_documents": len(docs),
        "moved": moved_count,
        "unchanged": unchanged_count,
        "skipped_missing_file": skipped_missing_file,
        "skipped_missing_folder": skipped_missing_folder,
        "errors": errors,
    }


@router.delete("/{file_id}")
def delete_file(
    file_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    doc = db.get(Document, file_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="File not found")

    disk_file = Path(doc.file_path)
    if disk_file.exists():
        disk_file.unlink()

    db.delete(doc)
    db.commit()
    return {"status": "deleted"}


@router.get("/{file_id}/download")
def download_file(
    file_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    doc = db.get(Document, file_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="File not found")

    path = Path(doc.file_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Stored file is missing")

    return FileResponse(path=path, filename=doc.file_name, media_type=doc.mime_type)
