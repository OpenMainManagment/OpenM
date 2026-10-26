from pathlib import Path
import shutil

from pypdf import PdfReader


def _extract_from_txt(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def _extract_from_pdf(path: Path) -> str:
    reader = PdfReader(str(path))
    return "\n".join((page.extract_text() or "") for page in reader.pages)


def _extract_from_image_with_ocr(path: Path) -> str:
    try:
        import pytesseract
        from PIL import Image
    except Exception:
        return ""

    try:
        if shutil.which("tesseract") is None:
            windows_default = Path("C:/Program Files/Tesseract-OCR/tesseract.exe")
            if windows_default.exists():
                pytesseract.pytesseract.tesseract_cmd = str(windows_default)
        return pytesseract.image_to_string(Image.open(path))
    except Exception:
        return ""


def extract_text(path_str: str, mime_type: str | None) -> str:
    path = Path(path_str)
    if not path.exists():
        return ""

    suffix = path.suffix.lower()
    if suffix in {".txt", ".md", ".csv", ".json", ".log"}:
        return _extract_from_txt(path)
    if suffix == ".pdf" or (mime_type or "").lower() == "application/pdf":
        return _extract_from_pdf(path)
    if suffix in {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"}:
        return _extract_from_image_with_ocr(path)

    return ""
