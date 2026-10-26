"""Router for Project Action Buttons and Workflow Nodes management."""

import json
import imaplib
import mimetypes
import os
import re
import smtplib
import base64
import requests
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..auth import get_current_employee
from ..database import get_db
from ..models import (
    ActionButton,
    ActionButtonDepartment,
    ActionExecution,
    ActionExecutionStatus,
    Organization,
    OrganizationSettings,
    Contact,
    CustomerCompany,
    Department,
    Document,
    Employee,
    EmployeeMailSettings,
    Folder,
    Part,
    PartDrawing,
    Project,
    ProjectStatus,
    Todo,
    WorkflowNode,
)
from ..schemas import (
    ActionButtonCreate,
    ActionButtonOut,
    ActionButtonUpdate,
    ActionExecutionCreate,
    ActionExecutionOut,
    ActionExecutionUpdate,
    GoogleMailTestRequest,
    WorkflowNodeCreate,
    WorkflowNodeOut,
    WorkflowNodeUpdate,
)
from ..services.storage_paths import (
    build_unique_file_path,
    ensure_folder_storage_dir,
    resolve_storage_root,
)

router = APIRouter(prefix="/api/actions", tags=["actions"])

_ACTION_BUTTON_TRIGGER = "action_button_pressed"
_STORAGE_ROOT = resolve_storage_root()


def _is_hello_world_node(node_data: dict[str, Any]) -> bool:
    """Best-effort identification for the Hello World test node."""
    candidates = [
        str(node_data.get("name") or ""),
        str(node_data.get("type") or ""),
        str(node_data.get("function") or ""),
    ]
    return any("hello world" in value.lower() for value in candidates)


def _is_ticket_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "create_ticket":
        return True

    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "ticket" in type_name


def _is_project_parts_mail_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "send_project_parts_email":
        return True

    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "parts mail" in type_name or "projekt teile mail" in type_name


def _is_add_folder_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name in {"add_folder", "create_folder"}:
        return True

    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "add folder" in type_name or "folder" in type_name and "add" in type_name


def _is_file_to_todo_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name in {"file_to_todo", "file_consumer"}:
        return True

    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "file to todo" in type_name or "file consumer" in type_name


def _is_person_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "assign_person":
        return True
    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "person node" in type_name


def _is_customer_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "assign_customer":
        return True
    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "customer node" in type_name


def _is_parts_offer_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "send_parts_offer_email":
        return True
    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "parts offer" in type_name


def _is_parts_order_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "send_parts_order_email":
        return True
    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "parts order" in type_name


def _is_ai_text_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "ai_text_generate":
        return True
    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "ai text" in type_name


def _is_save_email_draft_node(node_data: dict[str, Any]) -> bool:
    function_name = str(
        _node_value(node_data, ["function", "functionLabel"]) or "",
    ).strip().lower()
    if function_name == "save_email_draft":
        return True
    type_name = str(_node_value(node_data, ["type", "typeName", "name"]) or "").strip().lower()
    return "save email draft" in type_name or "email draft" in type_name


def _parse_json_object(raw_value: Any) -> dict[str, Any]:
    if isinstance(raw_value, dict):
        return raw_value
    if not isinstance(raw_value, str):
        return {}
    try:
        decoded = json.loads(raw_value)
    except (TypeError, ValueError):
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _to_safe_port_token(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "_", value.strip().lower())
    normalized = normalized.strip("_")
    return normalized or "file"


def _folder_file_port_name(file_name: str) -> str:
    return f"file_{_to_safe_port_token(file_name)}"


def _normalize_port_name(value: str | None) -> str:
    raw = (value or "").strip().lower()
    if not raw:
        return ""
    if raw in {"unknown", "none", "null"}:
        return ""
    if raw.startswith("instance of"):
        return ""
    return raw


def _add_folder_config(node_data: dict[str, Any]) -> dict[str, Any]:
    config = node_data.get("folder_files_config")
    if isinstance(config, dict):
        return config

    nested_data = node_data.get("data")
    if isinstance(nested_data, dict):
        nested = nested_data.get("folder_files_config")
        if isinstance(nested, dict):
            return nested

    return {}


def _file_to_todo_config(node_data: dict[str, Any]) -> dict[str, Any]:
    config = node_data.get("file_todo_config")
    if isinstance(config, dict):
        return config

    nested_data = node_data.get("data")
    if isinstance(nested_data, dict):
        nested = nested_data.get("file_todo_config")
        if isinstance(nested, dict):
            return nested

    return {}


def _ticket_config(node_data: dict[str, Any]) -> dict[str, Any]:
    config = node_data.get("ticket_config")
    if isinstance(config, dict):
        return config

    config = node_data.get("todo_config")
    if isinstance(config, dict):
        return config

    nested_data = node_data.get("data")
    if isinstance(nested_data, dict):
        nested_ticket = nested_data.get("ticket_config")
        if isinstance(nested_ticket, dict):
            return nested_ticket
        nested_todo = nested_data.get("todo_config")
        if isinstance(nested_todo, dict):
            return nested_todo

    return {}


def _project_parts_mail_config(node_data: dict[str, Any]) -> dict[str, Any]:
    config = node_data.get("mail_parts_config")
    if isinstance(config, dict):
        return config

    nested_data = node_data.get("data")
    if isinstance(nested_data, dict):
        nested = nested_data.get("mail_parts_config")
        if isinstance(nested, dict):
            return nested

    return {}


def _generic_node_config(node_data: dict[str, Any], key: str) -> dict[str, Any]:
    config = node_data.get(key)
    if isinstance(config, dict):
        return config

    nested_data = node_data.get("data")
    if isinstance(nested_data, dict):
        nested = nested_data.get(key)
        if isinstance(nested, dict):
            return nested

    return {}


def _person_config(node_data: dict[str, Any]) -> dict[str, Any]:
    return _generic_node_config(node_data, "person_config")


def _customer_config(node_data: dict[str, Any]) -> dict[str, Any]:
    return _generic_node_config(node_data, "customer_config")


def _parts_offer_config(node_data: dict[str, Any]) -> dict[str, Any]:
    return _generic_node_config(node_data, "parts_offer_config")


def _parts_order_config(node_data: dict[str, Any]) -> dict[str, Any]:
    return _generic_node_config(node_data, "parts_order_config")


def _ai_text_config(node_data: dict[str, Any]) -> dict[str, Any]:
    return _generic_node_config(node_data, "ai_text_config")


def _save_email_draft_config(node_data: dict[str, Any]) -> dict[str, Any]:
    return _generic_node_config(node_data, "save_email_draft_config")


def _smtp_bool(value: str | None, default: bool = True) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _resolve_smtp_config(db: Session, organization_id: str | None) -> dict[str, Any]:
    """Resolve SMTP settings for a Organization: prefer the admin-editable
    OrganizationSettings row (Server Settings screen); fall back to the
    OPENM_SMTP_* environment variables for companies that haven't configured
    it yet."""
    host = None
    port = None
    username = None
    password = None
    use_tls = None
    sender = None

    if organization_id:
        row = db.query(OrganizationSettings).filter(OrganizationSettings.organization_id == organization_id).first()
        if row is not None:
            host = row.smtp_host
            port = row.smtp_port
            username = row.smtp_username
            password = row.smtp_password
            use_tls = row.smtp_use_tls
            sender = row.mail_from

    host = (host or os.getenv("OPENM_SMTP_HOST") or "").strip()
    port = port or int((os.getenv("OPENM_SMTP_PORT") or "587").strip() or 587)
    username = (username or os.getenv("OPENM_SMTP_USERNAME") or "").strip()
    password = password or os.getenv("OPENM_SMTP_PASSWORD") or ""
    if use_tls is None:
        use_tls = _smtp_bool(os.getenv("OPENM_SMTP_USE_TLS"), default=True)
    sender = (sender or os.getenv("OPENM_MAIL_FROM") or username or "").strip()

    return {
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "use_tls": use_tls,
        "sender": sender,
    }


def _send_smtp_email(
    *,
    recipient: str,
    subject: str,
    body: str,
    db: Session,
    organization_id: str | None,
    attachments: list[tuple[str, str]] | None = None,
) -> tuple[bool, str]:
    config = _resolve_smtp_config(db, organization_id)
    host = config["host"]
    if not host:
        return False, "SMTP is not configured (Admin > Server Settings > Email)"

    port = config["port"]
    username = config["username"]
    password = config["password"]
    use_tls = config["use_tls"]
    sender = config["sender"]
    if not sender:
        return False, "Mail-from / SMTP username must be configured"

    message = EmailMessage()
    message["From"] = sender
    message["To"] = recipient
    message["Subject"] = subject
    message.set_content(body)

    for filename, file_path in attachments or []:
        try:
            path = Path(file_path)
            if not path.is_file():
                continue
            data = path.read_bytes()
            guessed_type, _ = mimetypes.guess_type(filename or path.name)
            maintype, subtype = (guessed_type or "application/octet-stream").split("/", 1)
            message.add_attachment(
                data,
                maintype=maintype,
                subtype=subtype,
                filename=filename or path.name,
            )
        except Exception:  # pragma: no cover - best-effort attachment handling
            continue

    try:
        with smtplib.SMTP(host=host, port=port, timeout=20) as smtp:
            smtp.ehlo()
            if use_tls:
                smtp.starttls()
                smtp.ehlo()
            if username:
                smtp.login(username, password)
            smtp.send_message(message)
    except Exception as exc:  # pragma: no cover - external SMTP behavior
        return False, str(exc)

    return True, "sent"


def _send_google_test_email(*, recipient: str, subject: str, body: str) -> tuple[bool, str]:
    google_sender = (os.getenv("OPENM_GOOGLE_TEST_EMAIL") or "").strip()
    google_app_password = os.getenv("OPENM_GOOGLE_TEST_APP_PASSWORD") or ""
    if not google_sender:
        return False, "OPENM_GOOGLE_TEST_EMAIL not configured"
    if not google_app_password:
        return False, "OPENM_GOOGLE_TEST_APP_PASSWORD not configured"

    message = EmailMessage()
    message["From"] = google_sender
    message["To"] = recipient
    message["Subject"] = subject
    message.set_content(body)

    try:
        with smtplib.SMTP(host="smtp.gmail.com", port=587, timeout=20) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(google_sender, google_app_password)
            smtp.send_message(message)
    except Exception as exc:  # pragma: no cover - external SMTP behavior
        return False, str(exc)

    return True, "sent"


def _execute_project_parts_mail_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    config = _project_parts_mail_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    recipient = str(config.get("recipient_email") or config.get("recipient") or "").strip()
    if not recipient:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Project Parts Mail Node",
            "result": "skipped",
            "reason": "recipient_email missing",
        }

    project_id = str(config.get("project_id") or context.get("project_id") or "").strip()
    project = db.get(Project, project_id) if project_id else None

    parts = db.query(Part).order_by(Part.name.asc()).all()
    if parts:
        parts_lines = [
            f"- {part.name} (ID: {part.id}, Nr: {part.id_number or '-'}, EK: {part.buy_price:.2f}, VK: {part.sell_price:.2f})"
            for part in parts
        ]
        parts_text = "\n".join(parts_lines)
    else:
        parts_text = "- No parts available"

    project_name = project.name if project is not None else "Unknown Project"
    subject = str(config.get("subject") or "").strip()
    if not subject:
        subject = f"Projektteile: {project_name} ({project_id or 'n/a'})"

    body = (
        "Projektteile Export\n\n"
        f"Project ID: {project_id or 'n/a'}\n"
        f"Project Name: {project_name}\n"
        f"Triggered by: {context.get('action_button_name') or '-'}\n"
        f"Generated at: {datetime.utcnow().isoformat()}Z\n\n"
        "Hinweis: Teile sind aktuell global im parts_catalog gespeichert.\n"
        "Die Liste enthaelt daher alle vorhandenen Teile.\n\n"
        f"Parts Count: {len(parts)}\n\n"
        f"{parts_text}\n"
    )

    sent, details = _send_smtp_email(
        recipient=recipient,
        subject=subject,
        body=body,
        db=db,
        organization_id=context.get("organization_id") or (project.organization_id if project else None),
    )

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Project Parts Mail Node",
        "recipient_email": recipient,
        "project_id": project_id or None,
        "parts_count": len(parts),
        "result": "sent" if sent else "failed",
        "details": details,
    }


def _execute_person_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    """Loads an employee and re-emits their data so downstream nodes
    (Email, Ticket, ...) can pick up the fields they need."""
    config = _person_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    employee_id = str(config.get("employee_id") or "").strip()
    if not employee_id:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Person Node",
            "result": "skipped",
            "reason": "employee_id missing",
        }

    employee = db.get(Employee, employee_id)
    if employee is None:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Person Node",
            "result": "skipped",
            "reason": "employee not found",
        }

    full_name = f"{employee.first_name} {employee.last_name}".strip()
    emitted_payload = {
        **context,
        "person_id": employee.id,
        "person_name": full_name,
        "person_email": employee.email,
        "person_login": employee.login_name,
        "person_department": employee.department,
        "email": employee.email,
        "recipient_email": employee.email,
    }

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Person Node",
        "result": "resolved",
        "person_id": employee.id,
        "person_name": full_name,
        "person_email": employee.email,
        "person_login": employee.login_name,
        "person_department": employee.department,
        "email": employee.email,
        "recipient_email": employee.email,
        "output_events": [{"port": "execution", "payload": emitted_payload}],
    }


def _execute_customer_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    """Loads a client Organization and re-emits their data so downstream nodes
    can pick up the fields they need (e.g. the customer's contact email)."""
    config = _customer_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    customer_company_id = str(config.get("customer_company_id") or "").strip()
    if not customer_company_id:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Customer Node",
            "result": "skipped",
            "reason": "customer_company_id missing",
        }

    customer = db.get(CustomerCompany, customer_company_id)
    if customer is None:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Customer Node",
            "result": "skipped",
            "reason": "customer not found",
        }

    contact_email = None
    contact = getattr(customer, "contact", None)
    if contact is not None:
        contact_email = getattr(contact, "email", None)

    emitted_payload = {
        **context,
        "customer_company_id": customer.id,
        "customer_name": customer.unique_name,
        "customer_email": contact_email,
        "email": contact_email,
        "recipient_email": contact_email,
    }

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Customer Node",
        "result": "resolved",
        "customer_company_id": customer.id,
        "customer_name": customer.unique_name,
        "customer_email": contact_email,
        "email": contact_email,
        "recipient_email": contact_email,
        "output_events": [{"port": "execution", "payload": emitted_payload}],
    }


def _part_attachments(part: Part) -> list[tuple[str, str]]:
    """Collects (filename, disk_path) pairs for a part's CAD/CNC file and
    drawings, for attaching to an outgoing email."""
    attachments: list[tuple[str, str]] = []
    if part.cad_file_url:
        attachments.append((part.cad_file_name or Path(part.cad_file_url).name, part.cad_file_url))
    if part.instructions_url:
        attachments.append(
            (part.instructions_name or Path(part.instructions_url).name, part.instructions_url)
        )
    drawings = getattr(part, "drawings", None) or []
    for drawing in drawings:
        file_url = getattr(drawing, "file_url", None)
        if file_url:
            file_name = getattr(drawing, "file_name", None) or Path(file_url).name
            attachments.append((file_name, file_url))
    return attachments


def _parts_selection_from_config(config: dict[str, Any]) -> list[dict[str, Any]]:
    items = config.get("items")
    if not isinstance(items, list):
        return []
    result = []
    for item in items:
        if isinstance(item, dict) and str(item.get("part_id") or "").strip():
            result.append(item)
    return result


def _execute_parts_offer_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    """Sends one separate email per selected part (each with that part's
    note, PDF drawings and CNC/CAD file attached) to the configured
    recipient. Falls back to an inherited Person/Customer email if no
    recipient was explicitly configured."""
    config = _parts_offer_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    recipient = (
        str(config.get("recipient_email") or "").strip()
        or str(context.get("person_email") or "").strip()
        or str(context.get("customer_email") or "").strip()
        or str(context.get("email") or "").strip()
    )
    if not recipient:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Parts Offer Node",
            "result": "skipped",
            "reason": "recipient_email missing",
        }

    selection = _parts_selection_from_config(config)
    if not selection:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Parts Offer Node",
            "result": "skipped",
            "reason": "no parts selected",
        }

    sent_count = 0
    failed_count = 0
    details: list[dict[str, Any]] = []

    for entry in selection:
        part = db.get(Part, str(entry.get("part_id")))
        if part is None:
            details.append({"part_id": entry.get("part_id"), "result": "not_found"})
            failed_count += 1
            continue

        note = str(entry.get("note") or "").strip()
        subject = f"Angebot: {part.name}"
        body = (
            f"Angebot fuer: {part.name}\n"
            f"Teile-Nr: {part.id_number or '-'}\n\n"
            f"{note}\n" if note else f"Angebot fuer: {part.name}\nTeile-Nr: {part.id_number or '-'}\n"
        )

        sent, detail_message = _send_smtp_email(
            recipient=recipient,
            subject=subject,
            body=body,
            db=db,
            organization_id=context.get("organization_id"),
            attachments=_part_attachments(part),
        )
        details.append(
            {
                "part_id": part.id,
                "part_name": part.name,
                "result": "sent" if sent else "failed",
                "details": detail_message,
            }
        )
        if sent:
            sent_count += 1
        else:
            failed_count += 1

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Parts Offer Node",
        "recipient_email": recipient,
        "emails_sent": sent_count,
        "emails_failed": failed_count,
        "result": "sent" if failed_count == 0 else ("partial" if sent_count else "failed"),
        "details": details,
    }


def _execute_parts_order_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    """Sends one combined email listing the selected parts plus a free-text
    message to every employee in the configured department."""
    config = _parts_order_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    department = str(config.get("department") or "").strip()
    if not department:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Parts Order Node",
            "result": "skipped",
            "reason": "department missing",
        }

    selection = _parts_selection_from_config(config)
    if not selection:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Parts Order Node",
            "result": "skipped",
            "reason": "no parts selected",
        }

    lines = []
    for entry in selection:
        part = db.get(Part, str(entry.get("part_id")))
        part_name = part.name if part is not None else str(entry.get("part_name") or "Unknown part")
        note = str(entry.get("note") or "").strip()
        lines.append(f"- {part_name}" + (f" ({note})" if note else ""))
    parts_text = "\n".join(lines)

    message_text = str(config.get("text") or "").strip()
    subject = f"Teilebestellung fuer Abteilung: {department}"
    body = (
        f"Neue Teilebestellung fuer die Abteilung: {department}\n\n"
        f"Teile:\n{parts_text}\n\n"
        f"{message_text}\n" if message_text else f"Neue Teilebestellung fuer die Abteilung: {department}\n\nTeile:\n{parts_text}\n"
    )

    recipients = [
        employee.email
        for employee in db.query(Employee)
        .filter(Employee.department == department)
        .all()
        if employee.email
    ]

    if not recipients:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Parts Order Node",
            "department": department,
            "result": "skipped",
            "reason": "no employees with an email address in this department",
        }

    sent_count = 0
    failed_count = 0
    for recipient in recipients:
        sent, _ = _send_smtp_email(
            recipient=recipient,
            subject=subject,
            body=body,
            db=db,
            organization_id=context.get("organization_id"),
        )
        if sent:
            sent_count += 1
        else:
            failed_count += 1

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Parts Order Node",
        "department": department,
        "recipients": recipients,
        "parts_count": len(selection),
        "result": "sent" if failed_count == 0 else ("partial" if sent_count else "failed"),
    }


def _ai_server_by_name(db: Session, organization_id: str | None, server_name: str) -> dict[str, Any] | None:
    if not organization_id or not server_name:
        return None
    row = db.query(OrganizationSettings).filter(OrganizationSettings.organization_id == organization_id).first()
    if row is None:
        return None
    try:
        servers = json.loads(row.ai_servers or "[]")
    except (TypeError, ValueError):
        return None
    if not isinstance(servers, list):
        return None
    for server in servers:
        if isinstance(server, dict) and server.get("name") == server_name:
            return server
    return None


def _call_ai_server(server: dict[str, Any], *, task: str, personality: str) -> tuple[bool, str]:
    """Calls the configured AI server (Ollama, or any OpenAI-compatible
    endpoint such as LM Studio) and returns (success, text_or_error)."""
    base_url = str(server.get("base_url") or "").rstrip("/")
    provider = str(server.get("provider") or "ollama").strip().lower()
    model = str(server.get("model") or "").strip()
    api_key = server.get("api_key")

    if not base_url:
        return False, "AI server base_url is not configured"

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    try:
        if provider == "openai_compatible":
            response = requests.post(
                f"{base_url}/v1/chat/completions",
                headers=headers,
                json={
                    "model": model or "local-model",
                    "messages": [
                        {"role": "system", "content": personality or "You are a helpful assistant."},
                        {"role": "user", "content": task},
                    ],
                    "stream": False,
                },
                timeout=120,
            )
            response.raise_for_status()
            data = response.json()
            text = (
                data.get("choices", [{}])[0]
                .get("message", {})
                .get("content", "")
            )
            return True, text.strip()

        # Default: Ollama's native /api/generate endpoint.
        response = requests.post(
            f"{base_url}/api/generate",
            headers=headers,
            json={
                "model": model or "llama3",
                "prompt": task,
                "system": personality or "",
                "stream": False,
            },
            timeout=120,
        )
        response.raise_for_status()
        data = response.json()
        return True, str(data.get("response") or "").strip()
    except requests.RequestException as exc:
        return False, str(exc)
    except (ValueError, KeyError, IndexError) as exc:
        return False, f"Unexpected AI server response: {exc}"


def _execute_ai_text_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    """Sends a Task + Personality (system prompt) to the selected AI server
    preset (Ollama / LM Studio / any OpenAI-compatible endpoint, configured
    in Admin > Server Settings) and re-emits the generated text so
    downstream nodes (Save Email Draft, Parts Offer note, ...) can use it."""
    config = _ai_text_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    server_name = str(config.get("ai_server_name") or "").strip()
    task = str(config.get("task") or "").strip()
    personality = str(config.get("personality") or "").strip()

    if not server_name:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "AI Text Node",
            "result": "skipped",
            "reason": "ai_server_name missing",
        }
    if not task:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "AI Text Node",
            "result": "skipped",
            "reason": "task missing",
        }

    server = _ai_server_by_name(db, context.get("organization_id"), server_name)
    if server is None:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "AI Text Node",
            "result": "skipped",
            "reason": f"AI server '{server_name}' not found in Server Settings",
        }

    success, text_or_error = _call_ai_server(server, task=task, personality=personality)
    if not success:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "AI Text Node",
            "result": "failed",
            "reason": text_or_error,
        }

    emitted_payload = {
        **context,
        "ai_text": text_or_error,
        "ai_text_output": text_or_error,
    }

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "AI Text Node",
        "result": "generated",
        "ai_server": server_name,
        "ai_text": text_or_error,
        "ai_text_output": text_or_error,
        "output_events": [{"port": "execution", "payload": emitted_payload}],
    }


def _execute_save_email_draft_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
    current_user: Employee,
) -> dict[str, Any]:
    """Files an email (To/Subject/Body) as a draft directly into the
    current user's own mailbox Drafts folder via IMAP. Subject/body fall
    back to an inherited AI Text node output if left blank in the config."""
    config = _save_email_draft_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    recipient = str(config.get("recipient_email") or context.get("email") or "").strip()
    subject = str(config.get("subject") or "").strip() or "Draft"
    body = (
        str(config.get("body") or "").strip()
        or str(context.get("ai_text_output") or context.get("ai_text") or "").strip()
    )

    mail_settings = (
        db.query(EmployeeMailSettings)
        .filter(EmployeeMailSettings.employee_id == current_user.id)
        .first()
    )
    if mail_settings is None or not mail_settings.imap_host or not mail_settings.imap_username:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Save Email Draft Node",
            "result": "skipped",
            "reason": (
                "No personal IMAP mail settings configured for "
                f"{current_user.login_name}. Set them under My Account > Mail Settings."
            ),
        }

    message = EmailMessage()
    message["From"] = mail_settings.imap_username
    if recipient:
        message["To"] = recipient
    message["Subject"] = subject
    message.set_content(body)

    try:
        if mail_settings.imap_use_ssl:
            imap = imaplib.IMAP4_SSL(mail_settings.imap_host, mail_settings.imap_port or 993)
        else:
            imap = imaplib.IMAP4(mail_settings.imap_host, mail_settings.imap_port or 143)
        imap.login(mail_settings.imap_username, mail_settings.imap_password or "")
        imap.append(
            mail_settings.drafts_folder or "Drafts",
            "",
            imaplib.Time2Internaldate(datetime.utcnow().timestamp()),
            message.as_bytes(),
        )
        imap.logout()
    except Exception as exc:  # pragma: no cover - external IMAP behavior
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Save Email Draft Node",
            "result": "failed",
            "reason": str(exc),
        }

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Save Email Draft Node",
        "result": "draft_saved",
        "recipient_email": recipient or None,
        "subject": subject,
        "folder": mail_settings.drafts_folder or "Drafts",
    }


@router.post("/mail/google-test")
def send_google_test_mail(
    payload: GoogleMailTestRequest,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Send a test email through a configured Google test account (Admin only)."""
    if (current_user.role or "").lower() != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admins can send Google test emails",
        )

    project_name = "Unknown Project"
    if payload.project_id:
        project = db.get(Project, payload.project_id)
        if project is not None:
            project_name = project.name

    subject = (payload.subject or "").strip() or "OpenM Google SMTP Test"
    body = (payload.body or "").strip()
    if not body:
        body = (
            "This is an OpenM Google SMTP test email.\n\n"
            f"Triggered by: {current_user.login_name}\n"
            f"Project ID: {payload.project_id or 'n/a'}\n"
            f"Project Name: {project_name}\n"
            f"Timestamp: {datetime.utcnow().isoformat()}Z\n"
        )

    sent, details = _send_google_test_email(
        recipient=str(payload.recipient_email),
        subject=subject,
        body=body,
    )
    if not sent:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Google SMTP test failed: {details}",
        )

    return {
        "status": "sent",
        "recipient_email": str(payload.recipient_email),
        "subject": subject,
        "project_id": payload.project_id,
        "project_name": project_name,
    }


def _execute_ticket_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    config = _ticket_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    name = str(
        config.get("name")
        or config.get("ticket_name")
        or _node_value(node_data, ["name"])
        or "Ticket",
    ).strip()
    text = str(
        config.get("text")
        or config.get("description")
        or config.get("ticket_text")
        or "",
    ).strip()
    department = str(config.get("department") or "").strip()

    if not department:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Ticket Node",
            "result": "skipped",
            "reason": "department missing",
        }

    organization_id = str(config.get("organization_id") or context.get("organization_id") or "").strip() or None
    project_id = str(config.get("project_id") or context.get("project_id") or "").strip() or None
    folder_id = str(config.get("folder_id") or "").strip() or None
    main_employer = (
        str(config.get("main_employer") or "").strip()
        or str(context.get("person_login") or "").strip()
        or None
    )

    todo = Todo(
        name=name,
        organization_id=organization_id,
        project_id=project_id,
        folder_id=folder_id,
        department=department,
        description=text or None,
        project_status=ProjectStatus.IN_WORK,
        sort_order=0,
        main_employer=main_employer,
    )
    db.add(todo)
    db.flush()

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Ticket Node",
        "ticket_id": todo.id,
        "ticket_name": todo.name,
        "department": department,
        "assigned_to": main_employer,
        "result": "created",
    }


def _execute_add_folder_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    config = _add_folder_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    project_id = str(config.get("project_id") or context.get("project_id") or "").strip()
    if not project_id:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Add Folder",
            "result": "skipped",
            "reason": "project_id missing",
            "output_events": [{"port": "execution", "payload": context}],
        }

    project = db.get(Project, project_id)
    if project is None:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Add Folder",
            "result": "skipped",
            "reason": "project not found",
            "output_events": [{"port": "execution", "payload": context}],
        }

    folder_name = str(config.get("folder_name") or config.get("name") or "").strip()
    if not folder_name:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "Add Folder",
            "result": "skipped",
            "reason": "folder_name missing",
            "output_events": [{"port": "execution", "payload": context}],
        }

    folder = (
        db.query(Folder)
        .filter(
            Folder.project_id == project.id,
            Folder.parent_folder_id.is_(None),
            Folder.name.ilike(folder_name),
        )
        .first()
    )
    folder_created = False
    if folder is None:
        folder = Folder(project_id=project.id, name=folder_name, parent_folder_id=None)
        db.add(folder)
        db.flush()
        folder_created = True

    target_dir = ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)

    raw_files = config.get("files")
    files_config = raw_files if isinstance(raw_files, list) else []
    file_results: list[dict[str, Any]] = []
    output_events: list[dict[str, Any]] = [
        {
            "port": "execution",
            "payload": {
                **context,
                "folder_id": folder.id,
                "folder_name": folder.name,
                "folder_created": folder_created,
            },
        },
    ]

    for item in files_config:
        file_content = ""
        file_bytes: bytes | None = None
        mime_type_override: str | None = None
        if isinstance(item, dict):
            file_name_raw = str(item.get("name") or item.get("file_name") or "").strip()
            file_content = str(item.get("content") or "")
            encoded = str(item.get("bytes_base64") or "").strip()
            mime_type_override = str(item.get("mime_type") or "").strip() or None
            if encoded:
                try:
                    file_bytes = base64.b64decode(encoded)
                except Exception:
                    file_bytes = None
        else:
            file_name_raw = str(item).strip()

        file_name = Path(file_name_raw).name
        if not file_name:
            continue

        existing_document = (
            db.query(Document)
            .filter(
                Document.folder_id == folder.id,
                Document.file_name == file_name,
            )
            .first()
        )

        created = False
        document = existing_document
        if document is None:
            disk_path = build_unique_file_path(target_dir, file_name)
            if file_bytes is not None:
                disk_path.write_bytes(file_bytes)
            else:
                disk_path.write_text(file_content, encoding="utf-8")
            mime_type = mime_type_override or mimetypes.guess_type(file_name)[0] or "text/plain"

            document = Document(
                folder_id=folder.id,
                project_id=project.id,
                file_name=file_name,
                file_path=str(disk_path),
                mime_type=mime_type,
                uploaded_by_employee_id=str(context.get("employee_id") or "") or None,
            )
            db.add(document)
            db.flush()
            created = True

        file_payload = {
            **context,
            "folder_id": folder.id,
            "folder_name": folder.name,
            "file_id": document.id if document is not None else None,
            "file_name": file_name,
            "file_created": created,
        }
        output_events.append({"port": _folder_file_port_name(file_name), "payload": file_payload})
        file_results.append(
            {
                "file_name": file_name,
                "file_id": document.id if document is not None else None,
                "created": created,
            },
        )

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Add Folder",
        "result": "created" if folder_created else "exists",
        "folder_id": folder.id,
        "folder_name": folder.name,
        "files": file_results,
        "output_events": output_events,
    }


def _execute_file_to_todo_node(
    node_data: dict[str, Any],
    context: dict[str, Any],
    db: Session,
) -> dict[str, Any]:
    config = _file_to_todo_config(node_data)
    if not config:
        config = _parse_json_object(_node_value(node_data, ["configuration"]))

    department = str(config.get("department") or "").strip()
    if not department:
        return {
            "node_id": node_data.get("id"),
            "node_name": node_data.get("name") or "File To Todo",
            "result": "skipped",
            "reason": "department missing",
            "output_events": [{"port": "execution", "payload": context}],
        }

    file_name = str(context.get("file_name") or "").strip()
    file_id = str(context.get("file_id") or "").strip()
    folder_name = str(context.get("folder_name") or "").strip()
    folder_id = str(context.get("folder_id") or "").strip()

    base_name = str(config.get("name") or "").strip()
    if not base_name:
        base_name = "File Follow-up"
    if file_name:
        todo_name = f"{base_name}: {file_name}"
    else:
        todo_name = base_name

    configured_description = str(config.get("description") or "").strip()
    if configured_description:
        description = configured_description
    else:
        description_lines = ["Generated from file output node."]
        if file_name:
            description_lines.append(f"File: {file_name}")
        if file_id:
            description_lines.append(f"File ID: {file_id}")
        if folder_name:
            description_lines.append(f"Folder: {folder_name}")
        if folder_id:
            description_lines.append(f"Folder ID: {folder_id}")
        description = "\n".join(description_lines)

    organization_id = str(config.get("organization_id") or context.get("organization_id") or "").strip() or None
    project_id = str(config.get("project_id") or context.get("project_id") or "").strip() or None

    todo = Todo(
        name=todo_name,
        organization_id=organization_id,
        project_id=project_id,
        folder_id=folder_id or None,
        department=department,
        description=description,
        project_status=ProjectStatus.IN_WORK,
        sort_order=0,
    )
    db.add(todo)
    db.flush()

    payload = {
        **context,
        "todo_id": todo.id,
        "todo_name": todo.name,
        "todo_department": department,
    }

    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "File To Todo",
        "result": "created",
        "todo_id": todo.id,
        "todo_name": todo.name,
        "output_events": [{"port": "execution", "payload": payload}],
    }


def _pick_value(payload: dict[str, Any], keys: list[str]) -> Any:
    for key in keys:
        if key in payload:
            return payload[key]
    return None


def _node_value(node_data: dict[str, Any], keys: list[str]) -> Any:
    value = _pick_value(node_data, keys)
    if value is not None:
        return value

    runtime_metadata = node_data.get("runtime_metadata")
    if isinstance(runtime_metadata, dict):
        value = _pick_value(runtime_metadata, keys)
        if value is not None:
            return value

    data = node_data.get("data")
    if isinstance(data, dict):
        return _pick_value(data, keys)

    return None


def _extract_graph_nodes(node_graph: str | None) -> list[dict[str, Any]]:
    """Read serialized node graph from ActionButton.node_graph."""
    if not node_graph:
        return []

    try:
        graph = json.loads(node_graph)
    except (TypeError, ValueError):
        return []

    if isinstance(graph, dict):
        graph_nodes = graph.get("nodes", [])
        return graph_nodes if isinstance(graph_nodes, list) else []

    if isinstance(graph, list):
        return [node for node in graph if isinstance(node, dict)]

    return []


def _extract_graph_connections(node_graph: str | None) -> list[dict[str, Any]]:
    """Read serialized connections from ActionButton.node_graph."""
    if not node_graph:
        return []

    try:
        graph = json.loads(node_graph)
    except (TypeError, ValueError):
        return []

    if isinstance(graph, dict):
        graph_connections = (
            graph.get("connections")
            or graph.get("edges")
            or graph.get("links")
            or []
        )
        return graph_connections if isinstance(graph_connections, list) else []

    return []


def _is_action_button_trigger_node(node_data: dict[str, Any]) -> bool:
    candidates = [
        str(_node_value(node_data, ["name"]) or ""),
        str(_node_value(node_data, ["type", "typeName"]) or ""),
        str(_node_value(node_data, ["function"]) or ""),
    ]
    return any("action button trigger" in value.lower() for value in candidates)


def _is_execution_connection(connection_data: dict[str, Any]) -> bool:
    source_output = _normalize_port_name(
        str(
            _pick_value(
                connection_data,
                [
                    "sourceOutputId",
                    "source_output_id",
                    "sourceHandle",
                    "sourcePort",
                    "sourcePortId",
                    "fromPort",
                    "source_port_id",
                ],
            )
            or "",
        ),
    )
    target_input = _normalize_port_name(
        str(
            _pick_value(
                connection_data,
                [
                    "targetInputId",
                    "target_input_id",
                    "targetHandle",
                    "targetPort",
                    "targetPortId",
                    "toPort",
                    "target_port_id",
                ],
            )
            or "",
        ),
    )

    # If ports are not stored, treat as execution edge for backward compatibility.
    if not source_output and not target_input:
        return True

    execution_tokens = ("trigger", "execution")
    return any(token in source_output for token in execution_tokens) or any(
        token in target_input for token in execution_tokens
    )


def _node_id(node_data: dict[str, Any]) -> str | None:
    node_id = _node_value(node_data, ["id", "nodeId", "node_id", "uuid"])
    if node_id is None:
        return None
    node_id_str = str(node_id).strip()
    return node_id_str or None


def _connection_source_node_id(connection_data: dict[str, Any]) -> str | None:
    source_node_id = _pick_value(
        connection_data,
        ["sourceNodeId", "source_node_id", "source", "from", "fromNodeId"],
    )
    if source_node_id is None:
        return None
    source_node_id_str = str(source_node_id).strip()
    return source_node_id_str or None


def _connection_source_port_name(connection_data: dict[str, Any]) -> str:
    value = _pick_value(
        connection_data,
        [
            "sourceOutputId",
            "source_output_id",
            "sourceHandle",
            "sourcePort",
            "sourcePortId",
            "fromPort",
            "source_port_id",
        ],
    )
    return _normalize_port_name(str(value or "execution"))


def _connection_target_node_id(connection_data: dict[str, Any]) -> str | None:
    target_node_id = _pick_value(
        connection_data,
        ["targetNodeId", "target_node_id", "target", "to", "toNodeId"],
    )
    if target_node_id is None:
        return None
    target_node_id_str = str(target_node_id).strip()
    return target_node_id_str or None


def _connection_target_port_name(connection_data: dict[str, Any]) -> str:
    value = _pick_value(
        connection_data,
        [
            "targetInputId",
            "target_input_id",
            "targetHandle",
            "targetPort",
            "targetPortId",
            "toPort",
            "target_port_id",
        ],
    )
    return _normalize_port_name(str(value or "execution"))


def _build_runtime_context(
    project: Project,
    button: ActionButton,
    current_user: Employee,
    execution_input: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Shared execution context for workflow nodes."""
    extra_context = execution_input or {}
    return {
        "project_id": project.id,
        "project_name": project.name,
        "action_button_id": button.id,
        "action_button_name": button.unique_name,
        "trigger": _ACTION_BUTTON_TRIGGER,
        "employee_id": current_user.id,
        "employee_department": current_user.department,
        "organization_id": project.organization_id,
        "company_name": extra_context.get("company_name"),
        "execution_input": extra_context,
    }


def _execute_hello_world_node(node_data: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    """Execute Hello World node: trigger activates execution, data input is ignored."""
    return {
        "node_id": node_data.get("id"),
        "node_name": node_data.get("name") or "Hello World",
        "trigger_input": node_data.get("trigger_input") or _ACTION_BUTTON_TRIGGER,
        "result": "Hello World",
        "trigger_output_fired": True,
        "context": context,
    }


def _execute_triggered_workflow_nodes(
    project: Project,
    button: ActionButton,
    current_user: Employee,
    db: Session,
    execution_input: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Minimal runtime: execute hello-world nodes reachable through trigger edges."""
    runtime_context = _build_runtime_context(
        project=project,
        button=button,
        current_user=current_user,
        execution_input=execution_input,
    )
    executed_nodes: list[dict[str, Any]] = []
    executed_node_ids: set[str] = set()

    graph_nodes = _extract_graph_nodes(button.node_graph)
    graph_connections = _extract_graph_connections(button.node_graph)

    node_by_id: dict[str, dict[str, Any]] = {}
    for graph_node in graph_nodes:
        node_id = _node_id(graph_node)
        if node_id:
            node_by_id[node_id] = graph_node

    trigger_roots = {node_id for node_id, node in node_by_id.items() if _is_action_button_trigger_node(node)}

    adjacency: dict[str, list[dict[str, str]]] = {}
    for connection in graph_connections:
        if not _is_execution_connection(connection):
            continue
        source_node_id = _connection_source_node_id(connection)
        target_node_id = _connection_target_node_id(connection)
        if not source_node_id or not target_node_id:
            continue
        adjacency.setdefault(source_node_id, []).append(
            {
                "target_node_id": target_node_id,
                "source_port": _connection_source_port_name(connection),
                "target_port": _connection_target_port_name(connection),
            },
        )

    queue: list[dict[str, Any]] = [
        {
            "node_id": trigger_node,
            "incoming_port": "execution",
            "payload": runtime_context,
        }
        for trigger_node in trigger_roots
    ]
    traversed_edges: set[tuple[str, str, str, str]] = set()
    hop_count = 0
    max_hops = 800
    while queue and hop_count < max_hops:
        hop_count += 1
        current = queue.pop(0)
        current_node_id = str(current.get("node_id") or "")
        if not current_node_id:
            continue

        incoming_payload = current.get("payload")
        current_payload = incoming_payload if isinstance(incoming_payload, dict) else runtime_context

        emitted_events = [{"port": "execution", "payload": current_payload}]
        target_node = node_by_id.get(current_node_id)
        if target_node is not None and not _is_action_button_trigger_node(target_node):
            node_with_context = {
                **target_node,
                "runtime_metadata": {
                    **(
                        target_node.get("runtime_metadata")
                        if isinstance(target_node.get("runtime_metadata"), dict)
                        else {}
                    ),
                    **runtime_context,
                    **current_payload,
                },
            }
            if _is_hello_world_node(node_with_context):
                node_result = _execute_hello_world_node(node_with_context, node_with_context["runtime_metadata"])
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_ticket_node(node_with_context):
                node_result = _execute_ticket_node(node_with_context, node_with_context["runtime_metadata"], db)
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_project_parts_mail_node(node_with_context):
                node_result = _execute_project_parts_mail_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_add_folder_node(node_with_context):
                node_result = _execute_add_folder_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_file_to_todo_node(node_with_context):
                node_result = _execute_file_to_todo_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_person_node(node_with_context):
                node_result = _execute_person_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_customer_node(node_with_context):
                node_result = _execute_customer_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_parts_offer_node(node_with_context):
                node_result = _execute_parts_offer_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_parts_order_node(node_with_context):
                node_result = _execute_parts_order_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_ai_text_node(node_with_context):
                node_result = _execute_ai_text_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events
            elif _is_save_email_draft_node(node_with_context):
                node_result = _execute_save_email_draft_node(
                    node_with_context,
                    node_with_context["runtime_metadata"],
                    db,
                    current_user,
                )
                executed_nodes.append(node_result)
                node_id = str(node_result.get("node_id") or "").strip()
                if node_id:
                    executed_node_ids.add(node_id)
                emitted_events = node_result.get("output_events") or emitted_events

    # Ensure Add Folder nodes configured with action_button_pressed run from trigger.
    for graph_node in graph_nodes:
        node_id = _node_id(graph_node)
        if not node_id or node_id in executed_node_ids:
            continue
        trigger_input = str(
            _node_value(graph_node, ["trigger_input", "triggerInput", "trigger"])
            or _ACTION_BUTTON_TRIGGER,
        )
        if trigger_input != _ACTION_BUTTON_TRIGGER:
            continue
        if not _is_add_folder_node(graph_node):
            continue

        node_with_context = {
            **graph_node,
            "runtime_metadata": {
                **(
                    graph_node.get("runtime_metadata")
                    if isinstance(graph_node.get("runtime_metadata"), dict)
                    else {}
                ),
                **runtime_context,
            },
        }
        node_result = _execute_add_folder_node(
            node_with_context,
            node_with_context["runtime_metadata"],
            db,
        )
        executed_nodes.append(node_result)
        executed_node_ids.add(node_id)

        for emitted in emitted_events:
            emitted_port = _normalize_port_name(str(emitted.get("port") or "execution"))
            emitted_payload = emitted.get("payload")
            next_payload = emitted_payload if isinstance(emitted_payload, dict) else current_payload
            for edge in adjacency.get(current_node_id, []):
                source_port = _normalize_port_name(edge.get("source_port"))
                if source_port and emitted_port and source_port != emitted_port:
                    continue
                next_node_id = edge.get("target_node_id") or ""
                target_port = _normalize_port_name(edge.get("target_port"))
                edge_key = (current_node_id, next_node_id, emitted_port, target_port)
                if edge_key in traversed_edges:
                    continue
                traversed_edges.add(edge_key)
                queue.append(
                    {
                        "node_id": next_node_id,
                        "incoming_port": target_port,
                        "payload": next_payload,
                    },
                )

    # Backward-compatible fallback for older graphs without explicit connections.
    if not executed_nodes and graph_nodes:
        for graph_node in graph_nodes:
            node_with_context = {
                **graph_node,
                "runtime_metadata": {
                    **(graph_node.get("runtime_metadata") if isinstance(graph_node.get("runtime_metadata"), dict) else {}),
                    **runtime_context,
                },
            }
            trigger_input = str(
                _node_value(node_with_context, ["trigger_input", "triggerInput", "trigger"])
                or _ACTION_BUTTON_TRIGGER,
            )
            if trigger_input != _ACTION_BUTTON_TRIGGER:
                continue
            if _is_hello_world_node(node_with_context):
                executed_nodes.append(_execute_hello_world_node(node_with_context, runtime_context))
            elif _is_ticket_node(node_with_context):
                executed_nodes.append(_execute_ticket_node(node_with_context, runtime_context, db))
            elif _is_project_parts_mail_node(node_with_context):
                executed_nodes.append(
                    _execute_project_parts_mail_node(node_with_context, runtime_context, db),
                )
            elif _is_add_folder_node(node_with_context):
                executed_nodes.append(_execute_add_folder_node(node_with_context, runtime_context, db))
            elif _is_file_to_todo_node(node_with_context):
                executed_nodes.append(_execute_file_to_todo_node(node_with_context, runtime_context, db))
            elif _is_person_node(node_with_context):
                executed_nodes.append(_execute_person_node(node_with_context, runtime_context, db))
            elif _is_customer_node(node_with_context):
                executed_nodes.append(_execute_customer_node(node_with_context, runtime_context, db))
            elif _is_parts_offer_node(node_with_context):
                executed_nodes.append(_execute_parts_offer_node(node_with_context, runtime_context, db))
            elif _is_parts_order_node(node_with_context):
                executed_nodes.append(_execute_parts_order_node(node_with_context, runtime_context, db))
            elif _is_ai_text_node(node_with_context):
                executed_nodes.append(_execute_ai_text_node(node_with_context, runtime_context, db))
            elif _is_save_email_draft_node(node_with_context):
                executed_nodes.append(
                    _execute_save_email_draft_node(node_with_context, runtime_context, db, current_user)
                )

    # Fallback to reusable workflow-node definitions if button graph has no executable hello-world node.
    if not executed_nodes:
        workflow_nodes = (
            db.query(WorkflowNode)
            .filter(
                WorkflowNode.is_active == True,
                WorkflowNode.organization_id == current_user.organization_id,
                WorkflowNode.trigger_input == _ACTION_BUTTON_TRIGGER,
            )
            .all()
        )
        for workflow_node in workflow_nodes:
            if "hello world" in (workflow_node.name or "").lower():
                executed_nodes.append(
                    _execute_hello_world_node(
                        {
                            "id": workflow_node.id,
                            "name": workflow_node.name,
                            "trigger_input": workflow_node.trigger_input,
                            "function": workflow_node.function,
                        },
                        runtime_context,
                    ),
                )
            elif (workflow_node.function or "").strip().lower() == "create_ticket":
                executed_nodes.append(
                    _execute_ticket_node(
                        {
                            "id": workflow_node.id,
                            "name": workflow_node.name,
                            "function": workflow_node.function,
                            "configuration": workflow_node.configuration,
                        },
                        runtime_context,
                        db,
                    ),
                )
            elif (workflow_node.function or "").strip().lower() == "send_project_parts_email":
                executed_nodes.append(
                    _execute_project_parts_mail_node(
                        {
                            "id": workflow_node.id,
                            "name": workflow_node.name,
                            "function": workflow_node.function,
                            "configuration": workflow_node.configuration,
                        },
                        runtime_context,
                        db,
                    ),
                )
            elif (workflow_node.function or "").strip().lower() in {"add_folder", "create_folder"}:
                executed_nodes.append(
                    _execute_add_folder_node(
                        {
                            "id": workflow_node.id,
                            "name": workflow_node.name,
                            "function": workflow_node.function,
                            "configuration": workflow_node.configuration,
                        },
                        runtime_context,
                        db,
                    ),
                )
            elif (workflow_node.function or "").strip().lower() in {"file_to_todo", "file_consumer"}:
                executed_nodes.append(
                    _execute_file_to_todo_node(
                        {
                            "id": workflow_node.id,
                            "name": workflow_node.name,
                            "function": workflow_node.function,
                            "configuration": workflow_node.configuration,
                        },
                        runtime_context,
                        db,
                    ),
                )

    if executed_nodes:
        db.commit()

    return {
        "trigger": _ACTION_BUTTON_TRIGGER,
        "executed_node_count": len(executed_nodes),
        "executed_nodes": executed_nodes,
    }


# ==================== Workflow Nodes ====================


@router.get("/nodes", response_model=list[WorkflowNodeOut])
def get_workflow_nodes(
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Get all workflow nodes."""
    nodes = db.query(WorkflowNode).filter(
        WorkflowNode.is_active == True,
    ).all()
    return nodes


@router.get("/nodes/{node_id}", response_model=WorkflowNodeOut)
def get_workflow_node(
    node_id: str,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Get a specific workflow node."""
    node = db.query(WorkflowNode).filter(
        WorkflowNode.id == node_id,
    ).first()
    
    if not node:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Workflow node not found")
    
    return node


@router.post("/nodes", response_model=WorkflowNodeOut)
def create_workflow_node(
    node_data: WorkflowNodeCreate,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Create a new workflow node (Admin only)."""
    if (current_user.role or "").lower() != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can create workflow nodes")

    new_node = WorkflowNode(
        organization_id=current_user.organization_id,
        name=node_data.name,
        category=node_data.category,
        function=node_data.function,
        endpoint=node_data.endpoint,
        trigger_input=node_data.trigger_input,
        configuration=node_data.configuration,
        description=node_data.description,
        is_active=node_data.is_active,
    )
    
    db.add(new_node)
    db.commit()
    db.refresh(new_node)
    
    return new_node


@router.put("/nodes/{node_id}", response_model=WorkflowNodeOut)
def update_workflow_node(
    node_id: str,
    node_data: WorkflowNodeUpdate,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Update a workflow node (Admin only)."""
    if (current_user.role or "").lower() != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can update workflow nodes")
    
    node = db.query(WorkflowNode).filter(
        WorkflowNode.id == node_id,
    ).first()
    
    if not node:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Workflow node not found")
    
    update_data = node_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(node, field, value)
    
    db.commit()
    db.refresh(node)
    
    return node


@router.delete("/nodes/{node_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_workflow_node(
    node_id: str,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Delete a workflow node (Admin only)."""
    if (current_user.role or "").lower() != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can delete workflow nodes")
    
    node = db.query(WorkflowNode).filter(
        WorkflowNode.id == node_id,
    ).first()
    
    if not node:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Workflow node not found")
    
    db.delete(node)
    db.commit()


# ==================== Action Buttons ====================


@router.get("/buttons", response_model=list[ActionButtonOut])
def get_action_buttons(
    organization_id: str | None = Query(default=None),
    workflow_stage: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Get all active action buttons available to the user."""
    query = db.query(ActionButton).filter(
        ActionButton.is_active == True,
    )
    if organization_id:
        query = query.filter(
            or_(
                ActionButton.organization_id == organization_id,
                ActionButton.organization_id.is_(None),
            ),
        )
    if workflow_stage:
        query = query.filter(
            or_(
                ActionButton.workflow_stage == workflow_stage,
                ActionButton.workflow_stage.is_(None),
            ),
        )

    buttons = query.order_by(ActionButton.sort_order.asc(), ActionButton.unique_name.asc()).all()
    
    # Filter by department access (user must be admin or in one of the assigned departments)
    filtered_buttons = []
    for button in buttons:
        if (current_user.role or "").lower() == "admin":
            filtered_buttons.append(button)
        elif not button.departments:  # If no departments assigned, everyone can see it
            filtered_buttons.append(button)
        else:
            # Check if user's department is in the assigned departments
            dept_ids = [d.department_id for d in button.departments]
            if any(dept.id in dept_ids for dept in db.query(Department).all() if dept.name == current_user.department):
                filtered_buttons.append(button)
    
    return filtered_buttons


@router.get("/buttons/{button_id}", response_model=ActionButtonOut)
def get_action_button(
    button_id: str,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Get a specific action button."""
    button = db.query(ActionButton).filter(
        ActionButton.id == button_id,
    ).first()
    
    if not button:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Action button not found")
    
    return button


@router.post("/buttons", response_model=ActionButtonOut)
def create_action_button(
    button_data: ActionButtonCreate,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Create a new action button (Admin only)."""
    if (current_user.role or "").lower() != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can create action buttons")

    organization_id = current_user.organization_id

    # Check duplicate unique name globally for action buttons
    existing = db.query(ActionButton).filter(
        ActionButton.unique_name == button_data.unique_name,
    ).first()
    
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Action button with this name already exists")
    
    new_button = ActionButton(
        organization_id=organization_id,
        unique_name=button_data.unique_name,
        description=button_data.description,
        node_graph=button_data.node_graph,
        workflow_stage=button_data.workflow_stage,
        is_active=button_data.is_active,
    )
    
    db.add(new_button)
    db.flush()
    
    # Add department links
    for dept_id in button_data.department_ids:
        dept = db.query(Department).filter(
            Department.id == dept_id,
        ).first()
        
        if dept:
            dept_link = ActionButtonDepartment(
                action_button_id=new_button.id,
                department_id=dept_id,
            )
            db.add(dept_link)
    
    db.commit()
    db.refresh(new_button)
    
    return new_button


@router.put("/buttons/{button_id}", response_model=ActionButtonOut)
def update_action_button(
    button_id: str,
    button_data: ActionButtonUpdate,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Update an action button (Admin only)."""
    if (current_user.role or "").lower() != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can update action buttons")
    
    button = db.query(ActionButton).filter(
        ActionButton.id == button_id,
    ).first()
    
    if not button:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Action button not found")
    
    # Ignore omitted/null fields so partial updates cannot wipe required columns.
    update_data = button_data.model_dump(exclude_unset=True, exclude_none=True)
    
    # Handle department_ids separately
    department_ids = update_data.pop("department_ids", None)
    
    for field, value in update_data.items():
        setattr(button, field, value)
    
    # Update department links
    if department_ids is not None:
        # Remove old links
        db.query(ActionButtonDepartment).filter(
            ActionButtonDepartment.action_button_id == button_id
        ).delete()
        
        # Add new links
        for dept_id in department_ids:
            dept = db.query(Department).filter(
                Department.id == dept_id,
                Department.organization_id == current_user.organization_id,
            ).first()
            
            if dept:
                dept_link = ActionButtonDepartment(
                    action_button_id=button_id,
                    department_id=dept_id,
                )
                db.add(dept_link)

    # Safety net for legacy rows that may contain nulls from older bugs/migrations.
    if not button.unique_name:
        button.unique_name = f"action_{button.id[:8]}"
    if button.is_active is None:
        button.is_active = True
    if button.sort_order is None:
        button.sort_order = 0
    
    db.commit()
    db.refresh(button)
    
    return button


@router.delete("/buttons/{button_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_action_button(
    button_id: str,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Delete an action button (Admin only)."""
    if (current_user.role or "").lower() != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can delete action buttons")
    
    button = db.query(ActionButton).filter(
        ActionButton.id == button_id,
    ).first()
    
    if not button:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Action button not found")
    
    db.delete(button)
    db.commit()


# ==================== Action Executions ====================


@router.get("/projects/{project_id}/executions", response_model=list[ActionExecutionOut])
def get_project_action_executions(
    project_id: str,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Get all action executions for a project."""
    executions = db.query(ActionExecution).filter(
        ActionExecution.project_id == project_id,
    ).all()
    
    return executions


@router.post("/projects/{project_id}/execute", response_model=ActionExecutionOut)
def execute_action_button(
    project_id: str,
    execution_data: ActionExecutionCreate,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Execute an action button on a project."""

    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")

    if (current_user.role or "").lower() != "admin" and current_user.organization_id != project.organization_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only execute project actions for your own Organization",
        )

    execution_input: dict[str, Any] = {}
    if execution_data.execution_input:
        parsed_input = _parse_json_object(execution_data.execution_input)
        if parsed_input:
            execution_input = parsed_input
    execution_input.setdefault("project_id", project.id)
    execution_input.setdefault("project_name", project.name)
    execution_input.setdefault("organization_id", project.organization_id)

    organization = db.get(Organization, project.organization_id)
    if organization is not None:
        execution_input.setdefault("company_name", organization.unique_name)

    # Verify action button exists and user has access
    button = db.query(ActionButton).filter(
        ActionButton.id == execution_data.action_button_id,
        ActionButton.is_active == True,
    ).first()
    
    if not button:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Action button not found")
    
    # Create execution record
    execution = ActionExecution(
        project_id=project_id,
        action_button_id=execution_data.action_button_id,
        executed_by_employee_id=current_user.id,
        execution_status=ActionExecutionStatus.PENDING,
        started_at=datetime.utcnow(),
    )
    
    db.add(execution)
    db.commit()
    db.refresh(execution)

    try:
        execution.execution_status = ActionExecutionStatus.RUNNING
        db.commit()

        execution_result = _execute_triggered_workflow_nodes(
            project=project,
            button=button,
            current_user=current_user,
            db=db,
            execution_input=execution_input,
        )

        execution.execution_status = ActionExecutionStatus.SUCCESS
        execution.execution_result = json.dumps(execution_result)
        execution.error_message = None
        execution.completed_at = datetime.utcnow()
        db.commit()
        db.refresh(execution)
    except Exception as exc:
        execution.execution_status = ActionExecutionStatus.FAILED
        execution.error_message = str(exc)
        execution.completed_at = datetime.utcnow()
        db.commit()
        db.refresh(execution)

    return execution


@router.get("/executions/{execution_id}", response_model=ActionExecutionOut)
def get_action_execution(
    execution_id: str,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Get a specific action execution."""
    execution = db.query(ActionExecution).filter(
        ActionExecution.id == execution_id,
    ).first()
    
    if not execution:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Action execution not found")
    
    return execution


@router.put("/executions/{execution_id}", response_model=ActionExecutionOut)
def update_action_execution(
    execution_id: str,
    execution_data: ActionExecutionUpdate,
    db: Session = Depends(get_db),
    current_user: Employee = Depends(get_current_employee),
):
    """Update an action execution status (Admin only)."""
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can update executions")
    
    execution = db.query(ActionExecution).filter(
        ActionExecution.id == execution_id,
    ).first()
    
    if not execution:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Action execution not found")
    
    update_data = execution_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(execution, field, value)
    
    db.commit()
    db.refresh(execution)
    
    return execution
