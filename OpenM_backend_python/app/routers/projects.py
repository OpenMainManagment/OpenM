import mimetypes
import shutil
import uuid
from datetime import date, datetime, timedelta
from io import BytesIO
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from sqlalchemy.orm import Session
from sqlalchemy.orm import selectinload

from ..auth import get_current_employee, get_current_manager_or_admin
from ..database import get_db
from ..models import Customer, CustomerCompany, Document, Employee, Folder, Manufacturer, Part, PartDecisionType, PartOrderDecision, PartOrderStatus, Project, ProjectFolderTemplate, ProjectGanttStep, ProjectGanttStepTemplate, ProjectGanttSubStep, ProjectGanttSubStepAssignee, ProjectGanttSubStepTemplate, ProjectOrderItem, ProjectStatus, Todo
from .actions import _send_smtp_email
from ..schemas import (
    DocumentOut,
    ProjectAiContextResponse,
    ProjectBaseModelUpdate,
    ProjectCreate,
    ProjectGanttStartResponse,
    ProjectGanttStepDurationUpdate,
    ProjectGanttStepOut,
    ProjectGanttSubStepAssigneesUpdate,
    ProjectGanttSubStepCreate,
    ProjectGanttSubStepAssigneeUpdate,
    ProjectGanttSubStepDurationUpdate,
    ProjectGanttTreeResponse,
    ProjectOrderItemOut,
    ProjectOrderItemUpdate,
    ProjectPartStatusUpdate,
    ProjectOrderNotesUpdate,
    ProjectOfferRecipientOut,
    ProjectOfferSendRequest,
    ProjectOfferSendResult,
    ProjectOut,
    ProjectWorkflowStageUpdate,
    PartOrderDecisionBatchCreate,
    PartOrderDecisionOut,
)
from ..services.storage_paths import (
    build_unique_file_path,
    ensure_folder_storage_dir,
    resolve_demo_files_root,
    resolve_storage_root,
)


router = APIRouter(prefix="/projects", tags=["projects"])

_STORAGE_ROOT = resolve_storage_root()
_DEMO_FILES_ROOT = resolve_demo_files_root()

_WORKFLOW_STAGES = [
    "project",
    "development",
    "order",
    "assembly",
    "shipping",
    "after_sales",
]

# Define the workflow order for status navigation
PROJECT_STATUS_ORDER = [
    ProjectStatus.QUOTE,
    ProjectStatus.SALE,
    ProjectStatus.CONSTRUCTION,
    ProjectStatus.PROCUREMENT,
    ProjectStatus.INSTALLATION,
    ProjectStatus.PROGRAMMING,
    ProjectStatus.DELIVERY,
    ProjectStatus.COMMISSIONING,
    ProjectStatus.FINAL_ACCEPTANCE,
    ProjectStatus.COMPLETED,
]

_DEFAULT_GANTT_STEP_DURATION_DAYS = 7
_GANTT_START_STATUS = ProjectStatus.SALE
_DEFAULT_SUB_STEP_COUNT = 3


def _normalize_workflow_stage(value: str | None) -> str:
    stage = (value or "project").strip().lower()
    if stage not in _WORKFLOW_STAGES:
        raise HTTPException(status_code=400, detail="Invalid workflow stage")
    return stage


def _get_next_status(current_status: ProjectStatus) -> ProjectStatus | None:
    """Get the next status in the workflow order."""
    try:
        current_index = PROJECT_STATUS_ORDER.index(current_status)
        if current_index < len(PROJECT_STATUS_ORDER) - 1:
            return PROJECT_STATUS_ORDER[current_index + 1]
        return None  # Already at the end
    except ValueError:
        return None  # Status not found in workflow order


def _get_previous_status(current_status: ProjectStatus) -> ProjectStatus | None:
    """Get the previous status in the workflow order."""
    try:
        current_index = PROJECT_STATUS_ORDER.index(current_status)
        if current_index > 0:
            return PROJECT_STATUS_ORDER[current_index - 1]
        return None  # Already at the beginning
    except ValueError:
        return None  # Status not found in workflow order


def _status_sort_index(status: ProjectStatus | str) -> int:
    status_value = status.value if isinstance(status, ProjectStatus) else str(status)
    for index, candidate in enumerate(PROJECT_STATUS_ORDER):
        if candidate.value == status_value:
            return index
    return -1


def _can_start_project_gantt(status: ProjectStatus | str) -> bool:
    return _status_sort_index(status) >= _status_sort_index(_GANTT_START_STATUS)


def _sync_project_gantt_step_states(db: Session, project: Project) -> None:
    current_index = _status_sort_index(project.status)
    steps = (
        db.query(ProjectGanttStep)
        .filter(ProjectGanttStep.project_id == project.id)
        .order_by(ProjectGanttStep.sort_order.asc())
        .all()
    )
    for step in steps:
        step_index = _status_sort_index(step.status_key)
        step.is_current = step_index == current_index
        step.is_completed = step_index != -1 and step_index < current_index


def _project_timeline_anchor(project: Project) -> date:
    if project.gantt_started_at is not None:
        return project.gantt_started_at.date()
    return project.start_date or date.today()


def _safe_duration_days(start_value: date | None, end_value: date | None) -> int:
    if start_value is None or end_value is None:
        return 1
    return max(1, (end_value - start_value).days + 1)


def _split_duration(total_days: int, parts: int) -> list[int]:
    part_count = max(1, min(parts, total_days))
    base = total_days // part_count
    remainder = total_days % part_count
    return [base + (1 if index < remainder else 0) for index in range(part_count)]


def _proportional_durations(current_durations: list[int], total_days: int) -> list[int]:
    if total_days <= 0:
        return [1 for _ in current_durations] or [1]
    if not current_durations:
        return _split_duration(total_days, _DEFAULT_SUB_STEP_COUNT)

    current_total = sum(max(1, value) for value in current_durations)
    if current_total <= 0:
        return _split_duration(total_days, len(current_durations))

    scaled = [max(1, round((value / current_total) * total_days)) for value in current_durations]
    diff = total_days - sum(scaled)

    index = 0
    while diff != 0 and scaled:
        cursor = index % len(scaled)
        if diff > 0:
            scaled[cursor] += 1
            diff -= 1
        elif scaled[cursor] > 1:
            scaled[cursor] -= 1
            diff += 1
        index += 1

    return scaled


def _ordered_sub_steps(step: ProjectGanttStep) -> list[ProjectGanttSubStep]:
    return sorted(step.sub_steps, key=lambda item: item.sort_order)


def _matching_sub_step_templates(
    db: Session, step: ProjectGanttStep
) -> list[ProjectGanttSubStepTemplate]:
    """Finds the Gantt step template that generated this real project step
    (matched by company + status_key, since ProjectGanttStep doesn't store
    a direct FK to the template it came from) and returns its configured
    sub-step templates, if any."""
    project = db.get(Project, step.project_id)
    if project is None:
        return []
    template = (
        db.query(ProjectGanttStepTemplate)
        .filter(
            ProjectGanttStepTemplate.organization_id == project.organization_id,
            ProjectGanttStepTemplate.status_key == step.status_key,
        )
        .first()
    )
    if template is None:
        return []
    return sorted(template.sub_step_templates, key=lambda item: item.sort_order)


def _ensure_step_sub_steps(db: Session, step: ProjectGanttStep) -> None:
    if step.sub_steps:
        return

    step_start = step.planned_start_date or date.today()
    total_days = _safe_duration_days(step.planned_start_date, step.planned_end_date)

    sub_templates = _matching_sub_step_templates(db, step)
    if sub_templates:
        # Use the admin-defined sub-step templates, scaling their relative
        # durations proportionally to fit however long this step actually
        # ended up being (its duration may have been edited per-project).
        template_durations = [max(1, int(item.duration_days)) for item in sub_templates]
        durations = _proportional_durations(template_durations, total_days)
        titles = [item.title for item in sub_templates]
        descriptions = [item.description for item in sub_templates]
    else:
        durations = _split_duration(total_days, _DEFAULT_SUB_STEP_COUNT)
        titles = [f"{step.title} Detail {index + 1}" for index in range(len(durations))]
        descriptions = [None for _ in durations]

    cursor = step_start

    for index, duration_days in enumerate(durations):
        step_end = cursor + timedelta(days=duration_days - 1)
        step.sub_steps.append(
            ProjectGanttSubStep(
                project_id=step.project_id,
                title=titles[index],
                description=descriptions[index],
                planned_start_date=cursor,
                planned_end_date=step_end,
                sort_order=index,
            )
        )
        cursor = step_end + timedelta(days=1)


def _shift_step_and_sub_steps(step: ProjectGanttStep, delta_days: int) -> None:
    if delta_days == 0:
        return

    if step.planned_start_date is not None:
        step.planned_start_date = step.planned_start_date + timedelta(days=delta_days)
    if step.planned_end_date is not None:
        step.planned_end_date = step.planned_end_date + timedelta(days=delta_days)

    for sub_step in _ordered_sub_steps(step):
        if sub_step.planned_start_date is not None:
            sub_step.planned_start_date = sub_step.planned_start_date + timedelta(days=delta_days)
        if sub_step.planned_end_date is not None:
            sub_step.planned_end_date = sub_step.planned_end_date + timedelta(days=delta_days)


def _sync_sub_steps_to_parent_duration(db: Session, step: ProjectGanttStep) -> None:
    _ensure_step_sub_steps(db, step)
    sub_steps = _ordered_sub_steps(step)
    if not sub_steps:
        return

    parent_start = step.planned_start_date or date.today()
    parent_duration = _safe_duration_days(step.planned_start_date, step.planned_end_date)
    current_durations = [
        _safe_duration_days(item.planned_start_date, item.planned_end_date)
        for item in sub_steps
    ]
    new_durations = _proportional_durations(current_durations, parent_duration)

    cursor = parent_start
    for index, sub_step in enumerate(sub_steps):
        duration_days = new_durations[index]
        sub_step.planned_start_date = cursor
        sub_step.planned_end_date = cursor + timedelta(days=duration_days - 1)
        cursor = sub_step.planned_end_date + timedelta(days=1)


def _sync_parent_from_sub_steps(db: Session, step: ProjectGanttStep) -> int:
    sub_steps = _ordered_sub_steps(step)
    if not sub_steps:
        _ensure_step_sub_steps(db, step)
        sub_steps = _ordered_sub_steps(step)
    if not sub_steps:
        return 0

    old_end = step.planned_end_date
    step.planned_start_date = sub_steps[0].planned_start_date
    step.planned_end_date = sub_steps[-1].planned_end_date

    if old_end is None or step.planned_end_date is None:
        return 0
    return (step.planned_end_date - old_end).days


def _shift_following_steps(steps: list[ProjectGanttStep], from_sort_order: int, delta_days: int) -> None:
    if delta_days == 0:
        return
    for item in steps:
        if item.sort_order > from_sort_order:
            _shift_step_and_sub_steps(item, delta_days)


def _project_gantt_steps_with_sub_steps(db: Session, project_id: str) -> list[ProjectGanttStep]:
    return (
        db.query(ProjectGanttStep)
        .options(
            selectinload(ProjectGanttStep.sub_steps)
            .selectinload(ProjectGanttSubStep.assignees)
            .selectinload(ProjectGanttSubStepAssignee.employee)
        )
        .filter(ProjectGanttStep.project_id == project_id)
        .order_by(ProjectGanttStep.sort_order.asc())
        .all()
    )


def _sync_sub_step_assignment_todos(
    db: Session,
    project: Project,
    sub_step: ProjectGanttSubStep,
    assignee_logins: list[str],
) -> None:
    (
        db.query(Todo)
        .filter(Todo.project_id == project.id)
        .filter(Todo.gantt_sub_step_id == sub_step.id)
        .delete(synchronize_session=False)
    )

    if not assignee_logins:
        return

    task_start = sub_step.planned_start_date or project.start_date or date.today()
    task_end = sub_step.planned_end_date or task_start
    task_name = f"Gantt: {sub_step.title}"
    task_description = (
        f"Auto-created from Gantt assignment\n"
        f"Project: {project.name}\n"
        f"Step: {sub_step.title}"
    )

    for sort_order, login in enumerate(assignee_logins):
        db.add(
            Todo(
                organization_id=project.organization_id,
                project_id=project.id,
                gantt_sub_step_id=sub_step.id,
                gantt_assignee_login=login,
                name=task_name,
                description=task_description,
                main_employer=login,
                coworker_logins=None,
                start_date=task_start,
                end_date=task_end,
                project_status=ProjectStatus.IN_WORK,
                sort_order=sort_order,
            )
        )


def _sync_assignment_todo_dates_for_steps(db: Session, steps: list[ProjectGanttStep]) -> None:
    for step in steps:
        for sub_step in _ordered_sub_steps(step):
            start_date = sub_step.planned_start_date
            end_date = sub_step.planned_end_date
            (
                db.query(Todo)
                .filter(Todo.gantt_sub_step_id == sub_step.id)
                .update(
                    {
                        Todo.start_date: start_date,
                        Todo.end_date: end_date,
                    },
                    synchronize_session=False,
                )
            )


def _find_parent_and_sub_step(
    steps: list[ProjectGanttStep],
    sub_step_id: str,
) -> tuple[ProjectGanttStep | None, ProjectGanttSubStep | None]:
    for step in steps:
        for sub_step in _ordered_sub_steps(step):
            if sub_step.id == sub_step_id:
                return step, sub_step
    return None, None


def _resequence_sub_steps(step: ProjectGanttStep) -> None:
    for index, sub_step in enumerate(_ordered_sub_steps(step)):
        sub_step.sort_order = index


def _read_company_gantt_templates(db: Session, organization_id: str) -> list[ProjectGanttStepTemplate]:
    return (
        db.query(ProjectGanttStepTemplate)
        .filter(ProjectGanttStepTemplate.organization_id == organization_id)
        .order_by(ProjectGanttStepTemplate.sort_order.asc(), ProjectGanttStepTemplate.created_at.asc())
        .all()
    )


def _ensure_project_gantt_steps(db: Session, project: Project) -> None:
    if not project.gantt_started:
        return

    existing_steps = (
        db.query(ProjectGanttStep)
        .filter(ProjectGanttStep.project_id == project.id)
        .order_by(ProjectGanttStep.sort_order.asc())
        .all()
    )
    if existing_steps:
        for step in existing_steps:
            _ensure_step_sub_steps(db, step)
        _sync_project_gantt_step_states(db, project)
        return

    templates = _read_company_gantt_templates(db, project.organization_id)
    if templates:
        step_specs = [
            (template.status_key, template.title, template.description, max(1, int(template.duration_days)))
            for template in templates
        ]
    else:
        step_specs = [
            (status.value, status.value, None, _DEFAULT_GANTT_STEP_DURATION_DAYS)
            for status in PROJECT_STATUS_ORDER
            if _status_sort_index(status) >= _status_sort_index(_GANTT_START_STATUS)
        ]

    timeline_cursor = _project_timeline_anchor(project)

    for index, (status_key, title, description, duration_days) in enumerate(step_specs):
        step_start = timeline_cursor
        step_end = step_start + timedelta(days=duration_days - 1)

        db.add(
            ProjectGanttStep(
                project_id=project.id,
                status_key=status_key,
                title=title,
                description=description,
                planned_start_date=step_start,
                planned_end_date=step_end,
                sort_order=index,
            )
        )

        timeline_cursor = step_end + timedelta(days=1)

    db.flush()
    for step in project.gantt_steps:
        _ensure_step_sub_steps(db, step)
    _sync_project_gantt_step_states(db, project)


def _resolve_demo_template(template_id: str) -> Path:
    candidate = (_DEMO_FILES_ROOT / template_id).resolve()
    root = _DEMO_FILES_ROOT.resolve()
    if root not in candidate.parents:
        raise ValueError("Invalid demo template id")
    if not candidate.is_file():
        raise FileNotFoundError("Demo template not found")
    return candidate


def _ensure_project_order_items(db: Session, project: Project) -> None:
    selectable_parts = (
        db.query(Part)
        .filter(Part.part_role.in_(["base_case", "main"]))
        .order_by(Part.part_role.asc(), Part.name.asc())
        .all()
    )
    existing_part_ids = {
        item.part_id for item in db.query(ProjectOrderItem.part_id).filter(ProjectOrderItem.project_id == project.id).all()
    }
    for part in selectable_parts:
        if part.id in existing_part_ids:
            continue
        db.add(ProjectOrderItem(project_id=project.id, part_id=part.id, quantity=0, selected=False))


def _project_order_item_out(item: ProjectOrderItem) -> ProjectOrderItemOut:
    return ProjectOrderItemOut(
        id=item.id,
        project_id=item.project_id,
        part_id=item.part_id,
        part_name=item.part.name,
        part_number=item.part.id_number,
        quantity=item.quantity,
        selected=item.selected,
        order_status=item.order_status,
        order_number=item.order_number,
        quotation_number=item.quotation_number,
        shipping_number=item.shipping_number,
        supplier=item.supplier,
        ordered_at=item.ordered_at,
        expected_delivery_date=item.expected_delivery_date,
        actual_delivery_date=item.actual_delivery_date,
        status_notes=item.status_notes,
    )


def update_project_order_notes(db: Session, project_id: str, payload: ProjectOrderNotesUpdate) -> Project:
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    project.order_top_note = (payload.top_note or "").strip() or None
    project.order_bottom_note = (payload.bottom_note or "").strip() or None
    db.commit()
    db.refresh(project)
    return project


@router.get("", response_model=list[ProjectOut])
def list_projects(
    organization_id: str | None = None,
    client_company_id: str | None = None,
    customer_company_id: str | None = None,
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    employee_organization_id = getattr(current_employee, "organization_id", None)
    if employee_organization_id is None:
        return []

    resolved_client_company_id = client_company_id or customer_company_id

    if resolved_client_company_id:
        client_company = db.get(CustomerCompany, resolved_client_company_id)
        if client_company is None:
            return []
        is_admin = (getattr(current_employee, "role", "") or "").lower() == "admin"
        if not is_admin and client_company.organization_id != employee_organization_id:
            return []

        query = db.query(Project).filter(Project.customer_company_id == resolved_client_company_id)
    elif organization_id:
        is_admin = (getattr(current_employee, "role", "") or "").lower() == "admin"
        if not is_admin and organization_id != employee_organization_id:
            return []

        query = db.query(Project).join(
            CustomerCompany, Project.customer_company_id == CustomerCompany.id
        ).filter(CustomerCompany.organization_id == organization_id)
    else:
        raise HTTPException(
            status_code=400,
            detail="organization_id or client_company_id is required",
        )

    if search:
        query = query.filter(Project.name.ilike(f"%{search}%"))
    return query.order_by(Project.name.asc()).all()


@router.get("/{project_id}", response_model=ProjectOut)
def get_project(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return project


@router.get("/{project_id}/ai-context", response_model=ProjectAiContextResponse)
def get_project_ai_context(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    """A plain-text dump of everything known about a project (status,
    parts/order items, sourcing decisions, gantt progress, folders, todos),
    meant to be handed to the AI chat assistant as context so it can answer
    questions without needing to make its own authenticated API calls."""
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    lines: list[str] = []
    lines.append(f"Project: {project.name} (id={project.id})")
    lines.append(f"Status: {project.status.value if hasattr(project.status, 'value') else project.status}")
    lines.append(f"Workflow stage: {project.workflow_stage}")
    lines.append(f"Base model: {project.base_model.value if hasattr(project.base_model, 'value') else project.base_model}")
    lines.append(f"Start date: {project.start_date.isoformat() if project.start_date else 'not set'}")
    if project.order_top_note:
        lines.append(f"Order note (top): {project.order_top_note}")
    if project.order_bottom_note:
        lines.append(f"Order note (bottom): {project.order_bottom_note}")

    folders = db.query(Folder).filter(Folder.project_id == project.id).order_by(Folder.name.asc()).all()
    if folders:
        lines.append("\nFolders:")
        for folder in folders:
            lines.append(f"- {folder.name}")

    order_items = (
        db.query(ProjectOrderItem)
        .options(selectinload(ProjectOrderItem.part))
        .filter(ProjectOrderItem.project_id == project.id)
        .filter(ProjectOrderItem.selected.is_(True))
        .order_by(ProjectOrderItem.created_at.asc())
        .all()
    )
    if order_items:
        lines.append("\nParts on this project:")
        for item in order_items:
            status_value = item.order_status.value if hasattr(item.order_status, "value") else item.order_status
            details = [f"qty {item.quantity}", f"status {status_value}"]
            if item.order_number:
                details.append(f"order # {item.order_number}")
            if item.quotation_number:
                details.append(f"quotation # {item.quotation_number}")
            if item.shipping_number:
                details.append(f"shipping # {item.shipping_number}")
            if item.supplier:
                details.append(f"supplier {item.supplier}")
            if item.expected_delivery_date:
                details.append(f"expected delivery {item.expected_delivery_date.isoformat()}")
            if item.actual_delivery_date:
                details.append(f"actual delivery {item.actual_delivery_date.isoformat()}")
            lines.append(f"- {item.part.name} ({', '.join(details)})")

    decisions = (
        db.query(PartOrderDecision)
        .options(selectinload(PartOrderDecision.part), selectinload(PartOrderDecision.manufacturer))
        .filter(PartOrderDecision.project_id == project.id)
        .order_by(PartOrderDecision.created_at.desc())
        .all()
    )
    if decisions:
        seen_parts: set[str] = set()
        lines.append("\nSourcing decisions (most recent per part):")
        for decision in decisions:
            if decision.part_id in seen_parts:
                continue
            seen_parts.add(decision.part_id)
            manufacturer = f" via {decision.manufacturer.name}" if decision.manufacturer else ""
            lines.append(f"- {decision.part.name}: {decision.decision.value}{manufacturer}")

    if project.gantt_started:
        gantt_steps = _project_gantt_steps_with_sub_steps(db, project.id)
        if gantt_steps:
            lines.append("\nGantt progress:")
            for step in gantt_steps:
                marker = "current" if step.is_current else ("done" if step.is_completed else "upcoming")
                lines.append(
                    f"- {step.title} [{marker}]: "
                    f"{step.planned_start_date} to {step.planned_end_date}"
                )

    todos = db.query(Todo).filter(Todo.project_id == project.id).order_by(Todo.sort_order.asc()).all()
    if todos:
        lines.append("\nOpen todos:")
        for todo in todos:
            owner = todo.main_employer or (f"department:{todo.department}" if todo.department else "unassigned")
            lines.append(f"- {todo.name} (owner: {owner}, due {todo.end_date or 'no date'})")

    return ProjectAiContextResponse(context="\n".join(lines))


_OFFER_FOLDER_NAME = "Angebote"


def _build_offer_pdf_bytes(
    project: Project, order_items: list[ProjectOrderItem], prepared_by: str | None = None
) -> bytes:
    """Renders a classic German business-letter style PDF quote: small
    return-address line, recipient (customer company) address block,
    sender (organization) address block, date/offer number, greeting,
    item table, net/VAT/total breakdown, closing and signature."""
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=25 * mm,
        rightMargin=20 * mm,
        topMargin=20 * mm,
        bottomMargin=20 * mm,
    )

    dark = colors.HexColor("#111827")
    light_row = colors.HexColor("#e5e7eb")
    muted = colors.HexColor("#6b7280")

    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle("ReturnAddress", parent=styles["Normal"], textColor=muted, fontSize=8))
    styles.add(ParagraphStyle("AddressBlock", parent=styles["Normal"], fontSize=10, leading=13))
    styles.add(ParagraphStyle("AddressBlockRight", parent=styles["AddressBlock"], alignment=2))
    styles.add(ParagraphStyle("MetaRight", parent=styles["Normal"], fontSize=10, alignment=2, leading=13))
    styles.add(ParagraphStyle("OfferTitle", parent=styles["Title"], fontSize=26, spaceBefore=0))
    styles.add(ParagraphStyle("OfferBody", parent=styles["Normal"], fontSize=10, leading=14))
    styles.add(ParagraphStyle("OfferFooter", parent=styles["Normal"], textColor=muted, fontSize=7.5, leading=10))

    customer_company = project.customer_company
    organization = customer_company.organization if customer_company else None
    contact = customer_company.contact if customer_company else None
    org_contact = organization.contact if organization else None
    offer_number = f"{date.today().year}-{project.id[:4].upper()}"

    def _street_line(contact_obj) -> str | None:
        if contact_obj is None:
            return None
        return " ".join(filter(None, [contact_obj.street, contact_obj.house_number])) or None

    def _address_paragraph(name: str, contact_obj, style, bold_name: bool = True) -> Paragraph:
        lines = [f"<b>{name}</b>" if bold_name else name]
        street = _street_line(contact_obj)
        if street:
            lines.append(street)
        return Paragraph("<br/>".join(lines), style)

    org_name = organization.unique_name if organization else "-"
    recipient_name = contact.head_of_company if contact and contact.head_of_company else customer_company.unique_name if customer_company else "-"

    elements: list = []

    return_address_parts = [org_name]
    org_street = _street_line(org_contact)
    if org_street:
        return_address_parts.append(org_street)
    elements.append(Paragraph(" \u2013 ".join(return_address_parts), styles["ReturnAddress"]))
    elements.append(Spacer(1, 10 * mm))

    header_table = Table(
        [
            [
                _address_paragraph(recipient_name, contact, styles["AddressBlock"], bold_name=True),
                _address_paragraph(org_name, org_contact, styles["AddressBlockRight"], bold_name=True),
            ],
        ],
        colWidths=[85 * mm, 85 * mm],
    )
    header_table.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
    elements.append(header_table)
    elements.append(Spacer(1, 10 * mm))

    elements.append(
        Paragraph(
            f"Datum: {date.today().strftime('%d.%m.%Y')}<br/>Angebotsnummer: {offer_number}",
            styles["MetaRight"],
        )
    )
    elements.append(Spacer(1, 14 * mm))

    elements.append(Paragraph("Angebot", styles["OfferTitle"]))
    elements.append(Spacer(1, 8 * mm))

    salutation = (
        f"Sehr geehrte(r) {recipient_name},"
        if contact and contact.head_of_company
        else "Sehr geehrte Damen und Herren,"
    )
    elements.append(Paragraph(salutation, styles["OfferBody"]))
    elements.append(Spacer(1, 3 * mm))
    elements.append(
        Paragraph(
            f"vielen Dank fuer Ihre Anfrage. Wir unterbreiten Ihnen hiermit folgendes Angebot "
            f"fuer das Projekt \"{project.name}\":",
            styles["OfferBody"],
        )
    )
    elements.append(Spacer(1, 8 * mm))

    table_data = [["Beschreibung", "Menge", "Einzelpreis", "Gesamtpreis"]]
    net_total = 0.0
    for item in order_items:
        unit_price = item.part.sell_price or 0.0
        line_total = unit_price * item.quantity
        net_total += line_total
        table_data.append(
            [
                item.part.name,
                str(item.quantity),
                f"{unit_price:,.2f} \u20ac",
                f"{line_total:,.2f} \u20ac",
            ]
        )

    vat_amount = net_total * 0.19
    gross_total = net_total + vat_amount
    table_data.append(["", "", "Nettopreis", f"{net_total:,.2f} \u20ac"])
    table_data.append(["", "", "Zzgl. 19% USt.", f"{vat_amount:,.2f} \u20ac"])
    table_data.append(["", "", "Angebotsbetrag", f"{gross_total:,.2f} \u20ac"])

    item_row_count = len(order_items)
    total_row_index = 1 + item_row_count + 2

    table = Table(table_data, colWidths=[80 * mm, 20 * mm, 30 * mm, 30 * mm])
    table.setStyle(
        TableStyle(
            [
                ("LINEBELOW", (0, 0), (-1, 0), 0.75, dark),
                ("LINEBELOW", (0, item_row_count), (-1, item_row_count), 0.5, colors.HexColor("#d1d5db")),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("BACKGROUND", (0, total_row_index), (-1, total_row_index), light_row),
                ("FONTNAME", (0, total_row_index), (-1, total_row_index), "Helvetica-Bold"),
                ("LINEABOVE", (2, total_row_index), (-1, total_row_index), 0.75, dark),
            ]
        )
    )
    elements.append(table)
    elements.append(Spacer(1, 12 * mm))

    if project.order_bottom_note:
        elements.append(Paragraph(project.order_bottom_note, styles["OfferBody"]))
        elements.append(Spacer(1, 6 * mm))

    elements.append(
        Paragraph(
            "Wir hoffen, dass unser Angebot bei Ihnen Anklang findet. "
            "Fuer weitere Fragen stehen wir Ihnen sehr gerne zur Verfuegung.",
            styles["OfferBody"],
        )
    )
    elements.append(Spacer(1, 10 * mm))
    elements.append(Paragraph("Mit freundlichen Gruessen", styles["OfferBody"]))
    if prepared_by:
        elements.append(Paragraph(prepared_by, styles["OfferBody"]))

    def _footer(canvas_obj, doc_obj):
        canvas_obj.saveState()
        page_width = doc_obj.pagesize[0]
        footer_lines = [org_name]
        if org_street:
            footer_lines.append(org_street)
        if org_contact and org_contact.phone_number:
            footer_lines.append(f"Tel: {org_contact.phone_number}")
        if org_contact and org_contact.email:
            footer_lines.append(f"E-Mail: {org_contact.email}")

        canvas_obj.setFont("Helvetica", 7.5)
        canvas_obj.setFillColor(muted)
        canvas_obj.line(25 * mm, 18 * mm, page_width - 20 * mm, 18 * mm)
        text_obj = canvas_obj.beginText(25 * mm, 15 * mm)
        text_obj.setFont("Helvetica", 7.5)
        for line in footer_lines:
            text_obj.textLine(line)
        canvas_obj.drawText(text_obj)
        canvas_obj.restoreState()

    doc.build(elements, onFirstPage=_footer, onLaterPages=_footer)
    return buffer.getvalue()


def _get_or_create_offer_folder(db: Session, project: Project) -> Folder:
    folder = (
        db.query(Folder)
        .filter(Folder.project_id == project.id)
        .filter(Folder.parent_folder_id.is_(None))
        .filter(Folder.name.ilike(_OFFER_FOLDER_NAME))
        .first()
    )
    if folder is not None:
        return folder

    folder = Folder(project_id=project.id, name=_OFFER_FOLDER_NAME, parent_folder_id=None)
    db.add(folder)
    db.commit()
    db.refresh(folder)
    return folder


@router.post("/{project_id}/offer/pdf", response_model=DocumentOut)
def generate_project_offer_pdf(
    project_id: str,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    """Generates a PDF quote for the project's selected parts and saves it
    into the project's "Angebote" folder (creating the folder if needed),
    so it can be opened straight from there."""
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    order_items = (
        db.query(ProjectOrderItem)
        .options(selectinload(ProjectOrderItem.part))
        .filter(ProjectOrderItem.project_id == project.id)
        .filter(ProjectOrderItem.selected.is_(True))
        .order_by(ProjectOrderItem.created_at.asc())
        .all()
    )
    if not order_items:
        raise HTTPException(status_code=400, detail="No selected parts to include in the offer")

    pdf_bytes = _build_offer_pdf_bytes(
        project, order_items, prepared_by=f"{current_employee.first_name} {current_employee.last_name}".strip()
    )

    folder = _get_or_create_offer_folder(db, project)
    storage_root = resolve_storage_root()
    target_dir = ensure_folder_storage_dir(db, folder, storage_root)

    safe_project_name = "".join(c for c in project.name if c.isalnum() or c in " -_").strip() or "Projekt"
    file_name = f"Angebot_{safe_project_name}_{date.today().isoformat()}.pdf"
    disk_path = build_unique_file_path(target_dir, file_name)
    disk_path.write_bytes(pdf_bytes)

    document = Document(
        folder_id=folder.id,
        project_id=project.id,
        file_name=disk_path.name,
        file_path=str(disk_path),
        mime_type="application/pdf",
        uploaded_by_employee_id=current_employee.id,
    )
    db.add(document)
    db.commit()
    db.refresh(document)
    return document


@router.get("/{project_id}/offer/recipients", response_model=list[ProjectOfferRecipientOut])
def list_project_offer_recipients(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    """Customer-company employees who could receive the offer email, with
    the project leader (the company's main contact) listed first."""
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    customer_company = project.customer_company
    if customer_company is None:
        return []

    customers = (
        db.query(Customer)
        .filter(Customer.customer_company_id == customer_company.id)
        .order_by(Customer.last_name.asc(), Customer.first_name.asc())
        .all()
    )

    recipients = [
        ProjectOfferRecipientOut(
            customer_id=customer.id,
            name=f"{customer.first_name} {customer.last_name}".strip(),
            job_title=customer.role,
            email=customer.email,
            is_project_leader=customer.id == customer_company.main_customer_id,
        )
        for customer in customers
    ]
    recipients.sort(key=lambda item: (not item.is_project_leader, item.name.lower()))
    return recipients


@router.post("/{project_id}/offer/send", response_model=list[ProjectOfferSendResult])
def send_project_offer_email(
    project_id: str,
    payload: ProjectOfferSendRequest,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    document = db.get(Document, payload.document_id)
    if document is None or document.project_id != project.id:
        raise HTTPException(status_code=404, detail="Offer document not found")

    if not payload.customer_ids:
        raise HTTPException(status_code=400, detail="customer_ids is required")

    customers = (
        db.query(Customer)
        .filter(Customer.id.in_(payload.customer_ids))
        .filter(Customer.customer_company_id == project.customer_company_id)
        .all()
    )
    customers_by_id = {customer.id: customer for customer in customers}

    subject = f"Angebot: {project.name}"
    body = (
        f"Sehr geehrte Damen und Herren,\n\n"
        f"anbei erhalten Sie das Angebot fuer das Projekt \"{project.name}\".\n\n"
        f"Mit freundlichen Gruessen"
    )

    results: list[ProjectOfferSendResult] = []
    for customer_id in payload.customer_ids:
        customer = customers_by_id.get(customer_id)
        if customer is None:
            results.append(
                ProjectOfferSendResult(
                    customer_id=customer_id, name="", email=None, sent=False, detail="Customer not found"
                )
            )
            continue

        name = f"{customer.first_name} {customer.last_name}".strip()
        if not customer.email:
            results.append(
                ProjectOfferSendResult(
                    customer_id=customer_id, name=name, email=None, sent=False, detail="No email on file"
                )
            )
            continue

        sent, detail = _send_smtp_email(
            recipient=customer.email,
            subject=subject,
            body=body,
            db=db,
            organization_id=project.organization_id,
            attachments=[(document.file_name, document.file_path)],
        )
        results.append(
            ProjectOfferSendResult(
                customer_id=customer_id, name=name, email=customer.email, sent=sent, detail=detail
            )
        )

    return results


@router.post("", response_model=ProjectOut)
def create_project(
    payload: ProjectCreate,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    resolved_client_company_id = payload.client_company_id

    client_company = db.get(CustomerCompany, resolved_client_company_id)
    if client_company is None:
        raise HTTPException(status_code=404, detail="Client company not found")

    resolved_organization_id = client_company.organization_id

    employee_organization_id = getattr(current_employee, "organization_id", None)
    is_admin = (getattr(current_employee, "role", "") or "").lower() == "admin"
    if not is_admin and employee_organization_id != resolved_organization_id:
        raise HTTPException(status_code=403, detail="You can only create projects for your own company")

    project = Project(
        customer_company_id=resolved_client_company_id,
        name=payload.name,
        base_model=payload.base_model,
        start_date=payload.start_date,
        status=ProjectStatus.QUOTE,
        gantt_started=False,
    )
    project.workflow_stage = "project"
    db.add(project)
    db.commit()
    db.refresh(project)
    _ensure_project_order_items(db, project)
    db.commit()

    next_sort_order_row = (
        db.query(Todo.sort_order)
        .filter(Todo.project_status == ProjectStatus.IN_WORK)
        .order_by(Todo.sort_order.desc())
        .first()
    )
    next_sort_order = (next_sort_order_row[0] + 1) if next_sort_order_row else 0

    customer_company_name = client_company.unique_name if client_company is not None else "Not set"
    project_leader = None
    if client_company is not None and client_company.contact is not None:
        project_leader = (client_company.contact.head_of_company or "").strip() or None

    if project_leader is None and client_company is not None:
        if client_company.main_customer_id:
            main_customer = db.get(Customer, client_company.main_customer_id)
            if main_customer is not None:
                project_leader = f"{main_customer.first_name} {main_customer.last_name}".strip()

    if project_leader is None and client_company is not None:
        first_customer = (
            db.query(Customer)
            .filter(Customer.customer_company_id == client_company.id)
            .order_by(Customer.last_name.asc(), Customer.first_name.asc())
            .first()
        )
        if first_customer is not None:
            project_leader = f"{first_customer.first_name} {first_customer.last_name}".strip()

    task_description = (
        f"Client company: {customer_company_name}\n"
        f"Project leader: {project_leader or 'Not set'}"
    )

    default_task = Todo(
        name=f"{project.name} next contact",
        organization_id=project.organization_id,
        project_id=project.id,
        description=task_description,
        start_date=date.today(),
        end_date=date.today() + timedelta(days=5),
        sort_order=next_sort_order,
    )
    db.add(default_task)

    templates = (
        db.query(ProjectFolderTemplate)
        .options(selectinload(ProjectFolderTemplate.demo_files))
        .filter(ProjectFolderTemplate.organization_id == resolved_organization_id)
        .order_by(ProjectFolderTemplate.sort_order.asc(), ProjectFolderTemplate.name.asc())
        .all()
    )

    created_folders: list[Folder] = []
    if templates:
        template_map = {t.id: t for t in templates}
        created_by_template_id: dict[str, Folder] = {}
        pending_ids = {t.id for t in templates}

        while pending_ids:
            progressed = False
            for template_id in list(pending_ids):
                template = template_map[template_id]
                parent_id = template.parent_template_id
                if parent_id and parent_id not in created_by_template_id:
                    continue

                folder = Folder(
                    project_id=project.id,
                    name=template.name,
                    parent_folder_id=created_by_template_id[parent_id].id if parent_id else None,
                )
                db.add(folder)
                db.flush()

                created_by_template_id[template_id] = folder
                created_folders.append(folder)
                pending_ids.remove(template_id)
                progressed = True

            if not progressed:
                # Invalid parent references in template data: create remaining as roots.
                for template_id in list(pending_ids):
                    template = template_map[template_id]
                    folder = Folder(project_id=project.id, name=template.name, parent_folder_id=None)
                    db.add(folder)
                    db.flush()
                    created_by_template_id[template_id] = folder
                    created_folders.append(folder)
                    pending_ids.remove(template_id)

        for template in templates:
            folder = created_by_template_id.get(template.id)
            if folder is None:
                continue
            target_dir = ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)

            for demo_file in template.demo_files:
                try:
                    source_path = _resolve_demo_template(demo_file.demo_template_id)
                except (ValueError, FileNotFoundError):
                    continue

                target_name = (demo_file.target_file_name or "").strip() or source_path.name
                target_name = Path(target_name).name
                if not target_name:
                    continue

                disk_path = build_unique_file_path(target_dir, target_name)
                shutil.copyfile(source_path, disk_path)
                mime_type = mimetypes.guess_type(target_name)[0]

                db.add(
                    Document(
                        folder_id=folder.id,
                        project_id=project.id,
                        file_name=target_name,
                        file_path=str(disk_path),
                        mime_type=mime_type,
                        uploaded_by_employee_id=current_employee.id,
                    )
                )
    else:
        folder_names = ["Angebot", "Auftrag", "Nacharbeit"]
        for folder_name in folder_names:
            folder = Folder(project_id=project.id, name=folder_name, parent_folder_id=None)
            db.add(folder)
            created_folders.append(folder)
        db.flush()
        for folder in created_folders:
            ensure_folder_storage_dir(db, folder, _STORAGE_ROOT)

    db.commit()

    return project


@router.patch("/{project_id}/base-model", response_model=ProjectOut)
def update_project_base_model(
    project_id: str,
    payload: ProjectBaseModelUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    project.base_model = payload.base_model
    db.commit()
    db.refresh(project)
    return project


@router.get("/{project_id}/order-items", response_model=list[ProjectOrderItemOut])
def list_project_order_items(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    _ensure_project_order_items(db, project)
    db.commit()

    items = (
        db.query(ProjectOrderItem)
        .options(selectinload(ProjectOrderItem.part))
        .filter(ProjectOrderItem.project_id == project.id)
        .order_by(ProjectOrderItem.selected.desc(), ProjectOrderItem.quantity.desc(), ProjectOrderItem.created_at.asc())
        .all()
    )
    return [_project_order_item_out(item) for item in items]


@router.patch("/{project_id}/order-items/{item_id}", response_model=ProjectOrderItemOut)
def update_project_order_item(
    project_id: str,
    item_id: str,
    payload: ProjectOrderItemUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    item = (
        db.query(ProjectOrderItem)
        .options(selectinload(ProjectOrderItem.part))
        .filter(ProjectOrderItem.project_id == project_id)
        .filter(ProjectOrderItem.id == item_id)
        .first()
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Order item not found")

    item.quantity = max(0, payload.quantity)
    item.selected = payload.selected
    db.commit()
    db.refresh(item)
    return _project_order_item_out(item)


@router.get("/{project_id}/parts-status", response_model=list[ProjectOrderItemOut])
def list_project_parts_status(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    """Same underlying data as /order-items, but this is the endpoint the
    per-project Parts Status screen uses — every base-case/main part for
    the project with its current procurement tracking info, so delayed or
    never-ordered parts are visible at a glance."""
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    _ensure_project_order_items(db, project)
    db.commit()

    items = (
        db.query(ProjectOrderItem)
        .options(selectinload(ProjectOrderItem.part))
        .filter(ProjectOrderItem.project_id == project.id)
        .order_by(
            ProjectOrderItem.order_status.asc(),
            ProjectOrderItem.expected_delivery_date.asc(),
            ProjectOrderItem.created_at.asc(),
        )
        .all()
    )
    return [_project_order_item_out(item) for item in items]


@router.patch("/{project_id}/order-items/{item_id}/status", response_model=ProjectOrderItemOut)
def update_project_part_status(
    project_id: str,
    item_id: str,
    payload: ProjectPartStatusUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    item = (
        db.query(ProjectOrderItem)
        .options(selectinload(ProjectOrderItem.part))
        .filter(ProjectOrderItem.project_id == project_id)
        .filter(ProjectOrderItem.id == item_id)
        .first()
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Order item not found")

    if payload.order_status is not None:
        item.order_status = payload.order_status
        # Convenience: marking a part Ordered/In Stock without an explicit
        # date fills today's date in, since that's almost always what's meant.
        if payload.order_status == PartOrderStatus.ORDERED and item.ordered_at is None and payload.ordered_at is None:
            item.ordered_at = date.today()
        if payload.order_status == PartOrderStatus.IN_STOCK and item.actual_delivery_date is None and payload.actual_delivery_date is None:
            item.actual_delivery_date = date.today()
    if payload.order_number is not None:
        item.order_number = payload.order_number.strip() or None
    if payload.quotation_number is not None:
        item.quotation_number = payload.quotation_number.strip() or None
    if payload.shipping_number is not None:
        item.shipping_number = payload.shipping_number.strip() or None
    if payload.supplier is not None:
        item.supplier = payload.supplier.strip() or None
    if payload.ordered_at is not None:
        item.ordered_at = payload.ordered_at
    if payload.expected_delivery_date is not None:
        item.expected_delivery_date = payload.expected_delivery_date
    if payload.actual_delivery_date is not None:
        item.actual_delivery_date = payload.actual_delivery_date
    if payload.status_notes is not None:
        item.status_notes = payload.status_notes.strip() or None

    db.commit()
    db.refresh(item)
    return _project_order_item_out(item)


@router.post("/{project_id}/request-quotation", response_model=list[ProjectOrderItemOut])
def request_project_quotation(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    """Requests quotations for all selected parts on a project: gives every
    part a quotation number (an extension of the project id), pushes its due
    date out 4 weeks, and marks parts sourced from Storage as already
    In Stock instead of Quotation."""
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    _ensure_project_order_items(db, project)

    items = (
        db.query(ProjectOrderItem)
        .options(selectinload(ProjectOrderItem.part))
        .filter(ProjectOrderItem.project_id == project_id)
        .filter(ProjectOrderItem.selected.is_(True))
        .order_by(ProjectOrderItem.created_at.asc())
        .all()
    )

    decisions = (
        db.query(PartOrderDecision)
        .filter(PartOrderDecision.project_id == project_id)
        .order_by(PartOrderDecision.created_at.desc())
        .all()
    )
    latest_decision_by_part: dict[str, PartOrderDecision] = {}
    for decision in decisions:
        latest_decision_by_part.setdefault(decision.part_id, decision)

    due_date = date.today() + timedelta(weeks=4)
    project_prefix = project_id[:8].upper()

    for index, item in enumerate(items, start=1):
        decision = latest_decision_by_part.get(item.part_id)
        is_storage = decision is not None and decision.decision == PartDecisionType.STORAGE

        if not item.quotation_number:
            item.quotation_number = f"{project_prefix}-{index:03d}"

        if is_storage:
            item.order_status = PartOrderStatus.IN_STOCK
            item.actual_delivery_date = item.actual_delivery_date or date.today()
        else:
            item.order_status = PartOrderStatus.QUOTATION
            item.expected_delivery_date = due_date

    _create_quotation_gantt_todo(db, project, due_date)

    db.commit()
    for item in items:
        db.refresh(item)
    return [_project_order_item_out(item) for item in items]


def _create_quotation_gantt_todo(db: Session, project: Project, due_date: date) -> None:
    """Adds a "Quotation Request" point to the project's Procurement sub
    gantt (due in 4 weeks) and hands the follow-up todo to the Einkauf
    (purchasing) department."""
    if not project.gantt_started:
        return

    _ensure_project_gantt_steps(db, project)

    procurement_step = (
        db.query(ProjectGanttStep)
        .filter(ProjectGanttStep.project_id == project.id)
        .filter(ProjectGanttStep.status_key == ProjectStatus.PROCUREMENT.value)
        .first()
    )
    if procurement_step is None:
        return

    _ensure_step_sub_steps(db, procurement_step)
    sub_steps = _ordered_sub_steps(procurement_step)
    next_sort_order = sub_steps[-1].sort_order + 1 if sub_steps else 0

    sub_step = ProjectGanttSubStep(
        project_id=project.id,
        parent_step_id=procurement_step.id,
        title="Quotation Request",
        description="Parts quotation requested — follow up with the Einkauf department.",
        planned_start_date=date.today(),
        planned_end_date=due_date,
        sort_order=next_sort_order,
    )
    db.add(sub_step)
    db.flush()

    db.add(
        Todo(
            organization_id=project.organization_id,
            project_id=project.id,
            gantt_sub_step_id=sub_step.id,
            department="Einkauf",
            name=f"Quotation request — {project.name}",
            description=(
                f"Parts quotation requested for project {project.name}.\n"
                f"Due date: {due_date.isoformat()}"
            ),
            start_date=date.today(),
            end_date=due_date,
            project_status=ProjectStatus.IN_WORK,
            sort_order=0,
        )
    )


def _part_order_decision_out(decision: PartOrderDecision) -> PartOrderDecisionOut:
    return PartOrderDecisionOut(
        id=decision.id,
        project_id=decision.project_id,
        part_id=decision.part_id,
        part_name=decision.part.name,
        part_number=decision.part.id_number,
        decision=decision.decision,
        order_id=decision.order_id,
        manufacturer_id=decision.manufacturer_id,
        manufacturer_name=decision.manufacturer.name if decision.manufacturer else None,
        quantity=decision.quantity,
        placed_at=decision.placed_at,
        notes=decision.notes,
    )


@router.get("/{project_id}/part-decisions", response_model=list[PartOrderDecisionOut])
def list_project_part_decisions(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    """The current sourcing decision (Storage / Self Manufacture / Order)
    for each part in the project, most recent per part first. Used to
    pre-fill the Order Parts screen when it's reopened."""
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    decisions = (
        db.query(PartOrderDecision)
        .options(
            selectinload(PartOrderDecision.part),
            selectinload(PartOrderDecision.manufacturer),
        )
        .filter(PartOrderDecision.project_id == project_id)
        .order_by(PartOrderDecision.created_at.desc())
        .all()
    )
    return [_part_order_decision_out(item) for item in decisions]


@router.post("/{project_id}/part-decisions", response_model=list[PartOrderDecisionOut])
def save_project_part_decisions(
    project_id: str,
    payload: PartOrderDecisionBatchCreate,
    db: Session = Depends(get_db),
    current_employee: Employee = Depends(get_current_employee),
):
    """Saves how each part is being sourced. Every entry gets its own new
    row with a fresh order_id and today's date, regardless of whether the
    part had a prior decision — this preserves the sourcing history for a
    project instead of overwriting it."""
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    if not payload.entries:
        raise HTTPException(status_code=400, detail="entries is required")

    created: list[PartOrderDecision] = []
    for entry in payload.entries:
        part = db.get(Part, entry.part_id)
        if part is None:
            raise HTTPException(status_code=404, detail=f"Part {entry.part_id} not found")

        manufacturer_id = entry.manufacturer_id
        if manufacturer_id:
            manufacturer = db.get(Manufacturer, manufacturer_id)
            if manufacturer is None or manufacturer.organization_id != project.organization_id:
                raise HTTPException(status_code=404, detail="Manufacturer not found")
        if entry.decision != PartDecisionType.ORDER:
            manufacturer_id = None

        decision = PartOrderDecision(
            project_id=project_id,
            part_id=entry.part_id,
            decision=entry.decision,
            order_id=str(uuid.uuid4()),
            manufacturer_id=manufacturer_id,
            quantity=max(1, entry.quantity),
            placed_at=date.today(),
            placed_by_employee_id=current_employee.id,
            notes=(entry.notes or "").strip() or None,
        )
        db.add(decision)
        created.append(decision)

    db.commit()
    for decision in created:
        db.refresh(decision)
    return [_part_order_decision_out(item) for item in created]


@router.patch("/{project_id}/order-notes", response_model=ProjectOut)
def update_project_order_notes_endpoint(
    project_id: str,
    payload: ProjectOrderNotesUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    return update_project_order_notes(db, project_id, payload)


@router.patch("/{project_id}/workflow-stage", response_model=ProjectOut)
def update_project_workflow_stage(
    project_id: str,
    payload: ProjectWorkflowStageUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    project.workflow_stage = _normalize_workflow_stage(payload.workflow_stage)
    db.commit()
    db.refresh(project)
    return project


@router.get("/{project_id}/gantt-steps", response_model=list[ProjectGanttStepOut])
def list_project_gantt_steps(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    if not project.gantt_started:
        return []

    _ensure_project_gantt_steps(db, project)
    db.commit()

    return (
        db.query(ProjectGanttStep)
        .filter(ProjectGanttStep.project_id == project.id)
        .order_by(ProjectGanttStep.sort_order.asc())
        .all()
    )


@router.get("/{project_id}/gantt-tree", response_model=ProjectGanttTreeResponse)
def get_project_gantt_tree(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_employee),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    if not project.gantt_started:
        return ProjectGanttTreeResponse(project=project, gantt_steps=[])

    _ensure_project_gantt_steps(db, project)
    db.commit()
    db.refresh(project)

    steps = _project_gantt_steps_with_sub_steps(db, project.id)
    return ProjectGanttTreeResponse(project=project, gantt_steps=steps)


@router.patch("/{project_id}/gantt/steps/{step_id}/duration", response_model=ProjectGanttTreeResponse)
def update_project_gantt_step_duration(
    project_id: str,
    step_id: str,
    payload: ProjectGanttStepDurationUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    if not project.gantt_started:
        raise HTTPException(status_code=400, detail="Gantt has not started")

    _ensure_project_gantt_steps(db, project)
    steps = _project_gantt_steps_with_sub_steps(db, project.id)
    step = next((item for item in steps if item.id == step_id), None)
    if step is None:
        raise HTTPException(status_code=404, detail="Gantt step not found")

    if step.planned_start_date is None:
        step.planned_start_date = project.start_date or date.today()

    old_end = step.planned_end_date or step.planned_start_date
    step.planned_end_date = step.planned_start_date + timedelta(days=payload.duration_days - 1)
    _sync_sub_steps_to_parent_duration(db, step)

    delta_days = (step.planned_end_date - old_end).days
    _shift_following_steps(steps, step.sort_order, delta_days)

    _sync_assignment_todo_dates_for_steps(db, steps)
    db.commit()
    db.refresh(project)
    updated_steps = _project_gantt_steps_with_sub_steps(db, project.id)
    return ProjectGanttTreeResponse(project=project, gantt_steps=updated_steps)


@router.patch("/{project_id}/gantt/sub-steps/{sub_step_id}/duration", response_model=ProjectGanttTreeResponse)
def update_project_gantt_sub_step_duration(
    project_id: str,
    sub_step_id: str,
    payload: ProjectGanttSubStepDurationUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    if not project.gantt_started:
        raise HTTPException(status_code=400, detail="Gantt has not started")

    _ensure_project_gantt_steps(db, project)
    steps = _project_gantt_steps_with_sub_steps(db, project.id)

    parent_step, target_sub_step = _find_parent_and_sub_step(steps, sub_step_id)

    if parent_step is None or target_sub_step is None:
        raise HTTPException(status_code=404, detail="Gantt sub-step not found")

    sub_steps = _ordered_sub_steps(parent_step)
    if parent_step.planned_start_date is None:
        parent_step.planned_start_date = project.start_date or date.today()

    durations = [
        _safe_duration_days(item.planned_start_date, item.planned_end_date)
        for item in sub_steps
    ]
    target_index = sub_steps.index(target_sub_step)
    durations[target_index] = payload.duration_days

    cursor = parent_step.planned_start_date
    for index, sub_step in enumerate(sub_steps):
        duration_days = max(1, durations[index])
        sub_step.planned_start_date = cursor
        sub_step.planned_end_date = cursor + timedelta(days=duration_days - 1)
        cursor = sub_step.planned_end_date + timedelta(days=1)

    delta_days = _sync_parent_from_sub_steps(db, parent_step)
    _shift_following_steps(steps, parent_step.sort_order, delta_days)

    _sync_assignment_todo_dates_for_steps(db, steps)
    db.commit()
    db.refresh(project)
    updated_steps = _project_gantt_steps_with_sub_steps(db, project.id)
    return ProjectGanttTreeResponse(project=project, gantt_steps=updated_steps)


@router.post("/{project_id}/gantt/steps/{step_id}/sub-steps", response_model=ProjectGanttTreeResponse)
def create_project_gantt_sub_step(
    project_id: str,
    step_id: str,
    payload: ProjectGanttSubStepCreate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    if not project.gantt_started:
        raise HTTPException(status_code=400, detail="Gantt has not started")

    _ensure_project_gantt_steps(db, project)
    steps = _project_gantt_steps_with_sub_steps(db, project.id)
    step = next((item for item in steps if item.id == step_id), None)
    if step is None:
        raise HTTPException(status_code=404, detail="Gantt step not found")

    _ensure_step_sub_steps(db, step)
    sub_steps = _ordered_sub_steps(step)
    anchor_start = (
        (sub_steps[-1].planned_end_date + timedelta(days=1))
        if sub_steps and sub_steps[-1].planned_end_date is not None
        else (step.planned_start_date or project.start_date or date.today())
    )
    anchor_end = anchor_start + timedelta(days=payload.duration_days - 1)

    new_sub_step = ProjectGanttSubStep(
        project_id=project.id,
        parent_step_id=step.id,
        parent_step=step,
        title=payload.title.strip() or "Detail Step",
        description=(payload.description or "").strip() or None,
        planned_start_date=anchor_start,
        planned_end_date=anchor_end,
        sort_order=len(sub_steps),
    )
    db.add(new_sub_step)
    db.flush()

    delta_days = _sync_parent_from_sub_steps(db, step)
    _shift_following_steps(steps, step.sort_order, delta_days)
    _sync_assignment_todo_dates_for_steps(db, steps)

    db.commit()
    db.refresh(project)
    updated_steps = _project_gantt_steps_with_sub_steps(db, project.id)
    return ProjectGanttTreeResponse(project=project, gantt_steps=updated_steps)


@router.delete("/{project_id}/gantt/sub-steps/{sub_step_id}", response_model=ProjectGanttTreeResponse)
def delete_project_gantt_sub_step(
    project_id: str,
    sub_step_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    if not project.gantt_started:
        raise HTTPException(status_code=400, detail="Gantt has not started")

    _ensure_project_gantt_steps(db, project)
    steps = _project_gantt_steps_with_sub_steps(db, project.id)
    parent_step, target_sub_step = _find_parent_and_sub_step(steps, sub_step_id)
    if parent_step is None or target_sub_step is None:
        raise HTTPException(status_code=404, detail="Gantt sub-step not found")

    sub_steps = _ordered_sub_steps(parent_step)
    if len(sub_steps) <= 1:
        raise HTTPException(status_code=400, detail="At least one deep step is required")

    (
        db.query(Todo)
        .filter(Todo.project_id == project.id)
        .filter(Todo.gantt_sub_step_id == target_sub_step.id)
        .delete(synchronize_session=False)
    )
    db.delete(target_sub_step)
    db.flush()

    _resequence_sub_steps(parent_step)
    delta_days = _sync_parent_from_sub_steps(db, parent_step)
    _shift_following_steps(steps, parent_step.sort_order, delta_days)
    _sync_assignment_todo_dates_for_steps(db, steps)

    db.commit()
    db.refresh(project)
    updated_steps = _project_gantt_steps_with_sub_steps(db, project.id)
    return ProjectGanttTreeResponse(project=project, gantt_steps=updated_steps)


@router.patch("/{project_id}/gantt/sub-steps/{sub_step_id}/assignees", response_model=ProjectGanttTreeResponse)
def update_project_gantt_sub_step_assignees(
    project_id: str,
    sub_step_id: str,
    payload: ProjectGanttSubStepAssigneesUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    if not project.gantt_started:
        raise HTTPException(status_code=400, detail="Gantt has not started")

    _ensure_project_gantt_steps(db, project)
    steps = _project_gantt_steps_with_sub_steps(db, project.id)
    parent_step, target_sub_step = _find_parent_and_sub_step(steps, sub_step_id)
    if parent_step is None or target_sub_step is None:
        raise HTTPException(status_code=404, detail="Gantt sub-step not found")

    cleaned_logins = [
        login.strip()
        for login in payload.assignee_logins
        if (login or "").strip()
    ]
    unique_logins: list[str] = []
    for login in cleaned_logins:
        if login not in unique_logins:
            unique_logins.append(login)

    employees_by_login: dict[str, Employee] = {}
    for login in unique_logins:
        employee = (
            db.query(Employee)
            .filter(Employee.login_name == login)
            .filter(Employee.organization_id == project.organization_id)
            .first()
        )
        if employee is None:
            raise HTTPException(
                status_code=400,
                detail="Assignee must be an employee of the project company",
            )
        employees_by_login[login] = employee

    target_sub_step.assignees.clear()
    for login in unique_logins:
        target_sub_step.assignees.append(
            ProjectGanttSubStepAssignee(employee_id=employees_by_login[login].id)
        )

    target_sub_step.assignee_login = unique_logins[0] if unique_logins else None
    _sync_sub_step_assignment_todos(db, project, target_sub_step, unique_logins)

    db.commit()
    db.refresh(project)
    updated_steps = _project_gantt_steps_with_sub_steps(db, project.id)
    return ProjectGanttTreeResponse(project=project, gantt_steps=updated_steps)


@router.patch("/{project_id}/gantt/sub-steps/{sub_step_id}/assignee", response_model=ProjectGanttTreeResponse)
def update_project_gantt_sub_step_assignee(
    project_id: str,
    sub_step_id: str,
    payload: ProjectGanttSubStepAssigneeUpdate,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    assignee_logins = []
    assignee_login = (payload.assignee_login or "").strip()
    if assignee_login:
        assignee_logins = [assignee_login]

    return update_project_gantt_sub_step_assignees(
        project_id=project_id,
        sub_step_id=sub_step_id,
        payload=ProjectGanttSubStepAssigneesUpdate(assignee_logins=assignee_logins),
        db=db,
        _current_employee=_current_employee,
    )


@router.post("/{project_id}/gantt/start", response_model=ProjectGanttStartResponse)
def start_project_gantt(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    if project.gantt_started:
        _ensure_project_gantt_steps(db, project)
        db.commit()
        db.refresh(project)
        steps = (
            db.query(ProjectGanttStep)
            .filter(ProjectGanttStep.project_id == project.id)
            .order_by(ProjectGanttStep.sort_order.asc())
            .all()
        )
        return ProjectGanttStartResponse(project=project, gantt_steps=steps)

    if not _can_start_project_gantt(project.status):
        raise HTTPException(
            status_code=400,
            detail="Gantt can only start when project status is Sale or later",
        )

    project.gantt_started = True
    project.gantt_started_at = project.gantt_started_at or datetime.utcnow()
    _ensure_project_gantt_steps(db, project)
    db.commit()
    db.refresh(project)

    steps = (
        db.query(ProjectGanttStep)
        .filter(ProjectGanttStep.project_id == project.id)
        .order_by(ProjectGanttStep.sort_order.asc())
        .all()
    )
    return ProjectGanttStartResponse(project=project, gantt_steps=steps)


@router.post("/{project_id}/status/next", response_model=ProjectOut)
def next_project_status(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    
    next_status = _get_next_status(project.status)
    if next_status is None:
        raise HTTPException(status_code=400, detail="Already at the final status")
    
    project.status = next_status
    _sync_project_gantt_step_states(db, project)
    db.commit()
    db.refresh(project)
    return project


@router.patch("/{project_id}/next-status", response_model=ProjectOut)
def next_project_status_legacy_path(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    next_status = _get_next_status(project.status)
    if next_status is None:
        raise HTTPException(status_code=400, detail="Already at the final status")

    project.status = next_status
    _sync_project_gantt_step_states(db, project)
    db.commit()
    db.refresh(project)
    return project


@router.post("/{project_id}/status/previous", response_model=ProjectOut)
def previous_project_status(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    
    previous_status = _get_previous_status(project.status)
    if previous_status is None:
        raise HTTPException(status_code=400, detail="Already at the initial status")
    
    project.status = previous_status
    _sync_project_gantt_step_states(db, project)
    db.commit()
    db.refresh(project)
    return project


@router.patch("/{project_id}/previous-status", response_model=ProjectOut)
def previous_project_status_legacy_path(
    project_id: str,
    db: Session = Depends(get_db),
    _current_employee=Depends(get_current_manager_or_admin),
):
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")

    previous_status = _get_previous_status(project.status)
    if previous_status is None:
        raise HTTPException(status_code=400, detail="Already at the initial status")

    project.status = previous_status
    _sync_project_gantt_step_states(db, project)
    db.commit()
    db.refresh(project)
    return project
