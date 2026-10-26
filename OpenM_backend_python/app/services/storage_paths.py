from __future__ import annotations

import os
import re
from pathlib import Path

from sqlalchemy.orm import Session

from ..models import Folder


def resolve_storage_root() -> Path:
    configured_path = os.getenv("OPENM_STORAGE_ROOT", "").strip()
    if configured_path:
        root = Path(configured_path)
    else:
        root = Path(__file__).resolve().parents[2] / "storage"
    root.mkdir(parents=True, exist_ok=True)
    return root


def resolve_demo_files_root() -> Path:
    configured_path = os.getenv("OPENM_DEMO_FILES_ROOT", "").strip()
    if configured_path:
        root = Path(configured_path)
    else:
        root = Path(__file__).resolve().parents[2] / "demo_files"
    root.mkdir(parents=True, exist_ok=True)
    return root


def safe_segment(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._ -]", "_", value).strip(" .")
    return cleaned or "untitled"


def ensure_folder_storage_dir(db: Session, folder: Folder, storage_root: Path) -> Path:
    chain: list[Folder] = []
    current: Folder | None = folder
    visited: set[str] = set()

    while current is not None:
        if current.id in visited:
            break
        visited.add(current.id)
        chain.append(current)
        if not current.parent_folder_id:
            break
        current = db.get(Folder, current.parent_folder_id)

    chain.reverse()

    directory = storage_root / f"project_{folder.project_id}"
    for item in chain:
        directory = directory / f"{safe_segment(item.name)}_{item.id[:8]}"

    directory.mkdir(parents=True, exist_ok=True)
    return directory


def build_unique_file_path(directory: Path, file_name: str) -> Path:
    safe_name = Path(file_name).name
    if not safe_name:
        raise ValueError("Invalid file name")

    candidate = directory / safe_name
    if not candidate.exists():
        return candidate

    stem = Path(safe_name).stem
    suffix = Path(safe_name).suffix
    for index in range(1, 10_000):
        candidate = directory / f"{stem} ({index}){suffix}"
        if not candidate.exists():
            return candidate

    raise RuntimeError("Unable to allocate unique file name")
