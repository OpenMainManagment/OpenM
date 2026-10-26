from pathlib import Path
import tempfile

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy.orm import Session

from ..auth import get_current_employee
from ..database import get_db
from ..models import Document
from ..schemas import AiSummaryRequest, AiSummaryResponse, BusinessCardScanResponse
from ..services.text_extraction import extract_text


router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/business-card-extract", response_model=BusinessCardScanResponse)
def business_card_extract(
        file: UploadFile = File(...),
        _current_employee=Depends(get_current_employee),
):
        suffix = Path(file.filename or "business-card.jpg").suffix or ".jpg"
        temp_path = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
                    temp_file.write(file.file.read())
                    temp_path = temp_file.name
            extracted_text = extract_text(temp_path, file.content_type)
            return BusinessCardScanResponse(extracted_text=extracted_text.strip())
        finally:
            if temp_path:
                    Path(temp_path).unlink(missing_ok=True)


@router.post("/folder-summary", response_model=AiSummaryResponse)
def folder_summary(
    payload: AiSummaryRequest,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    docs = (
        db.query(Document)
        .filter(Document.folder_id == payload.folder_id)
        .order_by(Document.created_at.desc())
        .all()
    )

    if not docs:
        return AiSummaryResponse(
            summary="No files found in this folder yet.",
            suggestions=[
                "Upload first project documents.",
                "Add a naming convention for files.",
            ],
        )

    names = [d.file_name for d in docs]
    extracted_texts: list[str] = []
    for doc in docs[:5]:
        text = extract_text(doc.file_path, doc.mime_type)
        if text.strip():
            extracted_texts.append(text.strip())

    preview = None
    if extracted_texts:
        combined = "\n".join(extracted_texts)
        preview = combined[:1000]

    summary = f"Folder has {len(docs)} files. Latest files: {', '.join(names[:5])}."
    if preview:
        summary = f"{summary} Extracted text was found in uploaded files."
    suggestions = [
        "Mark overdue ToDos linked to this folder.",
        "Group files by project phase (Angebot, Auftrag, Nacharbeit).",
        "Review extracted text preview for missing metadata.",
    ]

    if payload.project_context:
        summary = f"{summary} Context: {payload.project_context}"

    return AiSummaryResponse(summary=summary, suggestions=suggestions, extracted_text_preview=preview)
