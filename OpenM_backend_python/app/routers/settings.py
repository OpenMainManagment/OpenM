"""Router for admin-editable server settings: the outgoing email (SMTP)
relay and saved AI server presets (Ollama, LM Studio, or any
OpenAI-compatible endpoint), plus each employee's personal IMAP settings
used to file "Save Email Draft" workflow nodes into their own mailbox."""

import json
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..auth import get_current_admin, get_current_employee
from ..database import get_db
from ..models import OrganizationSettings, Employee, EmployeeMailSettings
from ..schemas import (
    AiServerConfig,
    AiServersUpdate,
    CompanyEmailSettingsUpdate,
    CompanySettingsOut,
    EmployeeMailSettingsOut,
    EmployeeMailSettingsUpdate,
)

router = APIRouter(prefix="/admin/settings", tags=["settings"])
mail_settings_router = APIRouter(prefix="/auth/employees/me", tags=["settings"])


def _get_or_create_company_settings(db: Session, organization_id: str) -> OrganizationSettings:
    settings_row = (
        db.query(OrganizationSettings)
        .filter(OrganizationSettings.organization_id == organization_id)
        .first()
    )
    if settings_row is None:
        settings_row = OrganizationSettings(organization_id=organization_id, ai_servers="[]")
        db.add(settings_row)
        db.flush()
    return settings_row


def _ai_servers_from_json(raw: str | None) -> list[AiServerConfig]:
    if not raw:
        return []
    try:
        decoded = json.loads(raw)
    except (TypeError, ValueError):
        return []
    if not isinstance(decoded, list):
        return []
    servers: list[AiServerConfig] = []
    for item in decoded:
        if isinstance(item, dict):
            try:
                servers.append(AiServerConfig(**item))
            except Exception:  # pragma: no cover - skip malformed entries
                continue
    return servers


def _settings_to_out(settings_row: OrganizationSettings) -> CompanySettingsOut:
    return CompanySettingsOut(
        smtp_host=settings_row.smtp_host,
        smtp_port=settings_row.smtp_port,
        smtp_username=settings_row.smtp_username,
        smtp_use_tls=settings_row.smtp_use_tls,
        mail_from=settings_row.mail_from,
        has_smtp_password=bool(settings_row.smtp_password),
        ai_servers=_ai_servers_from_json(settings_row.ai_servers),
    )


@router.get("", response_model=CompanySettingsOut)
def get_settings(
    db: Session = Depends(get_db),
    current_admin: Employee = Depends(get_current_admin),
):
    settings_row = _get_or_create_company_settings(db, current_admin.organization_id)
    db.commit()
    return _settings_to_out(settings_row)


@router.put("/email", response_model=CompanySettingsOut)
def update_email_settings(
    payload: CompanyEmailSettingsUpdate,
    db: Session = Depends(get_db),
    current_admin: Employee = Depends(get_current_admin),
):
    settings_row = _get_or_create_company_settings(db, current_admin.organization_id)
    settings_row.smtp_host = payload.smtp_host
    settings_row.smtp_port = payload.smtp_port
    settings_row.smtp_username = payload.smtp_username
    if payload.smtp_password:
        # Only overwrite the stored password if a new one was actually
        # provided, so re-saving the form without retyping it doesn't wipe it.
        settings_row.smtp_password = payload.smtp_password
    settings_row.smtp_use_tls = payload.smtp_use_tls
    settings_row.mail_from = payload.mail_from
    db.commit()
    db.refresh(settings_row)
    return _settings_to_out(settings_row)


@router.put("/ai-servers", response_model=CompanySettingsOut)
def update_ai_servers(
    payload: AiServersUpdate,
    db: Session = Depends(get_db),
    current_admin: Employee = Depends(get_current_admin),
):
    settings_row = _get_or_create_company_settings(db, current_admin.organization_id)
    settings_row.ai_servers = json.dumps(
        [server.model_dump() for server in payload.ai_servers]
    )
    db.commit()
    db.refresh(settings_row)
    return _settings_to_out(settings_row)


@mail_settings_router.get("/mail-settings", response_model=EmployeeMailSettingsOut)
def get_my_mail_settings(
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    row = (
        db.query(EmployeeMailSettings)
        .filter(EmployeeMailSettings.employee_id == current_employee.id)
        .first()
    )
    if row is None:
        return EmployeeMailSettingsOut()
    return EmployeeMailSettingsOut(
        imap_host=row.imap_host,
        imap_port=row.imap_port or 993,
        imap_username=row.imap_username,
        imap_use_ssl=row.imap_use_ssl,
        drafts_folder=row.drafts_folder or "Drafts",
        has_password=bool(row.imap_password),
    )


@mail_settings_router.put("/mail-settings", response_model=EmployeeMailSettingsOut)
def update_my_mail_settings(
    payload: EmployeeMailSettingsUpdate,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    row = (
        db.query(EmployeeMailSettings)
        .filter(EmployeeMailSettings.employee_id == current_employee.id)
        .first()
    )
    if row is None:
        row = EmployeeMailSettings(employee_id=current_employee.id)
        db.add(row)

    row.imap_host = payload.imap_host
    row.imap_port = payload.imap_port
    row.imap_username = payload.imap_username
    if payload.imap_password:
        row.imap_password = payload.imap_password
    row.imap_use_ssl = payload.imap_use_ssl
    row.drafts_folder = payload.drafts_folder or "Drafts"
    db.commit()
    db.refresh(row)
    return EmployeeMailSettingsOut(
        imap_host=row.imap_host,
        imap_port=row.imap_port or 993,
        imap_username=row.imap_username,
        imap_use_ssl=row.imap_use_ssl,
        drafts_folder=row.drafts_folder or "Drafts",
        has_password=bool(row.imap_password),
    )
