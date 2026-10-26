import base64
import requests
from crewai.tools import BaseTool
from pydantic import BaseModel, Field
from typing import Type


# ── MIME type registry ────────────────────────────────────────────────────────
MIME_TYPES: dict[str, str] = {
    ".pdf":  "application/pdf",
    ".doc":  "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls":  "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".png":  "image/png",
    ".jpg":  "image/jpeg",
    ".jpeg": "image/jpeg",
    ".txt":  "text/plain",
}


def _resolve_mime_type(file_name: str) -> str:
    """Return the MIME type based on the file name extension."""
    dot_index = file_name.rfind(".")
    if dot_index == -1:
        return "application/octet-stream"
    ext = file_name[dot_index:].lower()
    return MIME_TYPES.get(ext, "application/octet-stream")


# ── Input schema ──────────────────────────────────────────────────────────────
class MultipartFileUploadInput(BaseModel):
    """Input schema for MultipartFileUploadTool."""

    api_url: str = Field(
        ...,
        description="The full endpoint URL to POST the file to, e.g. https://api.example.com/documents",
    )
    session_token: str = Field(
        ...,
        description="Bearer token used in the Authorization header.",
    )
    file_base64: str = Field(
        default="",
        description=(
            "Base64-encoded content of the file. "
            "Leave empty (or pass an empty string) to fall back to file_url."
        ),
    )
    file_url: str = Field(
        default="",
        description=(
            "URL from which the file can be downloaded. "
            "Used only when file_base64 is empty."
        ),
    )
    file_name: str = Field(
        ...,
        description='The file name including extension, e.g. "Angebot_Projekt42.pdf".',
    )
    project_id: str = Field(
        ...,
        description="The target project ID to associate with the uploaded file.",
    )
    folder_id: str = Field(
        ...,
        description="The target folder ID to associate with the uploaded file.",
    )


# ── Tool ──────────────────────────────────────────────────────────────────────
class MultipartFileUploadTool(BaseTool):
    """Tool for uploading a file to a REST API via multipart/form-data."""

    name: str = "MultipartFileUploadTool"
    description: str = (
        "Uploads a file to a specified REST API endpoint using multipart/form-data. "
        "The file can be supplied as a Base64-encoded string or via a download URL "
        "(fallback). The tool attaches project_id, folder_id, and file_name as "
        "additional form fields and authenticates with a Bearer session token."
    )
    args_schema: Type[BaseModel] = MultipartFileUploadInput

    # ── Core logic ─────────────────────────────────────────────────────────────
    def _run(
        self,
        api_url: str,
        session_token: str,
        file_name: str,
        project_id: str,
        folder_id: str,
        file_base64: str = "",
        file_url: str = "",
    ) -> str:
        """
        Execute the multipart file upload.

        Steps:
          1. Obtain raw file bytes – either by decoding the Base64 string or by
             downloading from file_url.
          2. Resolve the MIME type from the file name extension.
          3. POST the file and metadata fields to api_url.
          4. Return a structured result string.
        """
        try:
            # ── Step 1: Obtain file bytes ──────────────────────────────────────
            file_bytes: bytes

            if file_base64.strip():
                # Decode Base64 → binary
                try:
                    file_bytes = base64.b64decode(file_base64)
                except Exception as decode_err:
                    return f"EXCEPTION: Failed to decode Base64 content – {decode_err}"
            elif file_url.strip():
                # Download from URL
                try:
                    download_response = requests.get(file_url, timeout=60)
                    if download_response.status_code not in (200, 201):
                        return (
                            f"ERROR {download_response.status_code}: "
                            f"Failed to download file from file_url – "
                            f"{download_response.text}"
                        )
                    file_bytes = download_response.content
                except Exception as dl_err:
                    return f"EXCEPTION: Failed to download file from file_url – {dl_err}"
            else:
                return (
                    "EXCEPTION: Neither file_base64 nor file_url was provided. "
                    "Please supply at least one source for the file content."
                )

            # ── Step 2: Resolve MIME type ──────────────────────────────────────
            mime_type = _resolve_mime_type(file_name)

            # ── Step 3: Build and send the multipart POST request ──────────────
            headers = {
                "Authorization": f"Bearer {session_token}",
                # Do NOT manually set Content-Type; requests sets it with the
                # correct boundary when files= is used.
            }

            multipart_files = {
                "file": (file_name, file_bytes, mime_type),
            }

            form_data = {
                "project_id": project_id,
                "folder_id":  folder_id,
                "file_name":  file_name,
            }

            upload_response = requests.post(
                api_url,
                headers=headers,
                files=multipart_files,
                data=form_data,
                timeout=120,
            )

            # ── Step 4: Return structured result ──────────────────────────────
            if upload_response.status_code in (200, 201):
                # Attempt to parse JSON; fall back to raw text
                try:
                    response_body = str(upload_response.json())
                except Exception:
                    response_body = upload_response.text

                return f"SUCCESS: Document uploaded. Response: {response_body}"

            return (
                f"ERROR {upload_response.status_code}: {upload_response.text}"
            )

        except Exception as exc:
            return f"EXCEPTION: {exc}"
