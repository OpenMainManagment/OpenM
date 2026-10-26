import json
import os
import subprocess
import tempfile
import uuid
from pathlib import Path

import requests
from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from ..auth import create_access_token, get_current_employee
from ..database import get_db
from ..models import Employee
from ..schemas import ChatMessageResponse

router = APIRouter(prefix="/chat", tags=["chat"])

_AIS_CHAT_DIR = Path(__file__).resolve().parents[2] / "ais" / "chat"
_API_BASE_URL = "http://127.0.0.1:8002"
_CREW_TIMEOUT_SECONDS = 180
_LM_STUDIO_BASE_URL = "http://localhost:1234/v1"
_LM_STUDIO_UNREACHABLE_MESSAGE = (
    "AI assistant is unreachable: LM Studio's local server isn't responding at "
    f"{_LM_STUDIO_BASE_URL}. Start LM Studio (or run `lms server start`) with the "
    "qwen3-14b model loaded, then try again."
)


def _lm_studio_reachable() -> bool:
    try:
        response = requests.get(f"{_LM_STUDIO_BASE_URL}/models", timeout=3)
        return response.status_code < 500
    except requests.RequestException:
        return False


def _crew_subprocess_env() -> dict:
    """ais/chat is its own uv project with its own venv, separate from the
    main backend's .venv. If we inherit this process's environment as-is,
    VIRTUAL_ENV still points at the backend's venv and `uv run` refuses to
    proceed ("does not match the project environment"). Stripping the
    inherited venv vars lets uv resolve/create ais/chat's own venv instead."""
    env = os.environ.copy()
    env.pop("VIRTUAL_ENV", None)
    env.pop("PYTHONHOME", None)
    return env


@router.post("/message", response_model=ChatMessageResponse)
def send_chat_message(
    message: str = Form(default=""),
    project_id: str = Form(default=""),
    folder_id: str = Form(default=""),
    project_context: str = Form(default=""),
    file: UploadFile | None = File(default=None),
    _db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    """Forwards a chat message (and optional file) to the ProjectChatbot
    crew under ais/chat, which runs against a local LM Studio server. The
    crew is a standalone project with its own dependencies, so it's
    invoked out-of-process via `uv run` rather than imported directly."""
    if not _lm_studio_reachable():
        return ChatMessageResponse(response=_LM_STUDIO_UNREACHABLE_MESSAGE, error=True)

    session_token = create_access_token(
        subject=current_employee.id,
        organization_id=current_employee.organization_id,
    )

    file_name = ""
    file_base64 = ""
    if file is not None:
        file_name = file.filename or "upload.bin"
        import base64

        file_base64 = base64.b64encode(file.file.read()).decode("ascii")

    full_message = message
    if project_context.strip():
        full_message = (
            f"{message}\n\n[Project context — use this instead of calling the API]\n{project_context}"
        )

    inputs = {
        "user_message": full_message,
        "user_id": current_employee.id,
        "user_role": current_employee.role or "employee",
        "api_base_url": _API_BASE_URL,
        "session_token": session_token,
        "file_name": file_name,
        "confirmed_project_id": project_id,
        "confirmed_folder_id": folder_id,
        "file_base64": file_base64,
        "file_url": "",
    }

    with tempfile.TemporaryDirectory() as tmp_dir:
        input_path = Path(tmp_dir) / f"input-{uuid.uuid4().hex}.json"
        output_path = Path(tmp_dir) / f"output-{uuid.uuid4().hex}.json"
        input_path.write_text(json.dumps(inputs), encoding="utf-8")

        try:
            completed = subprocess.run(
                ["uv", "run", "python", "src/project_chatbot/api_main.py", str(input_path), str(output_path)],
                cwd=_AIS_CHAT_DIR,
                env=_crew_subprocess_env(),
                timeout=_CREW_TIMEOUT_SECONDS,
                capture_output=True,
                check=False,
            )
        except FileNotFoundError:
            return ChatMessageResponse(
                response="AI assistant is unavailable: 'uv' was not found on the backend's PATH.",
                error=True,
            )
        except subprocess.TimeoutExpired:
            return ChatMessageResponse(
                response="AI assistant timed out waiting for a response from LM Studio.",
                error=True,
            )

        if completed.returncode != 0 and not output_path.exists():
            stderr_tail = completed.stderr.decode("utf-8", errors="ignore")[-500:]
            return ChatMessageResponse(
                response=f"AI assistant crashed before responding: {stderr_tail or 'unknown error'}",
                error=True,
            )

        if not output_path.exists():
            return ChatMessageResponse(
                response="AI assistant did not return a response. Make sure LM Studio is "
                "running on the standard port with the qwen3-14b model loaded.",
                error=True,
            )

        result = json.loads(output_path.read_text(encoding="utf-8"))

    if "error" in result:
        return ChatMessageResponse(response=f"AI assistant error: {result['error']}", error=True)

    return ChatMessageResponse(response=result.get("response", ""), error=False)
