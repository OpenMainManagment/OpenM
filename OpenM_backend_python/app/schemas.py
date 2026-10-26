from datetime import date, datetime

from pydantic import AliasChoices, BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

from .models import (
    ActionExecutionStatus,
    BaseModelType,
    PartCategoryScope,
    PartDecisionType,
    PartOrderStatus,
    ProjectStatus,
    WorkflowNodeCategory,
)


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class EmployeeLogin(BaseModel):
    username: str
    password: str


class InitialSetupRequest(BaseModel):
    organization_name: str = Field(min_length=1, max_length=255)
    first_name: str = Field(min_length=1, max_length=255)
    last_name: str = Field(min_length=1, max_length=255)
    email: EmailStr
    login_name: str = Field(min_length=3, max_length=100)
    password: str = Field(min_length=12, max_length=128)

    @field_validator("organization_name", "first_name", "last_name", "login_name")
    @classmethod
    def strip_required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field cannot be empty")
        return value


class EmployeeOut(BaseModel):
    id: str
    organization_id: str | None
    first_name: str
    last_name: str
    job_description: str | None = None
    email: str
    login_name: str
    image_url: str | None = None
    role: str | None
    department: str | None
    is_super_admin: bool = False

    model_config = ConfigDict(from_attributes=True)


class EmployeeCreate(BaseModel):
    first_name: str
    last_name: str
    email: str
    login_name: str
    password: str
    role: str | None = None
    department: str | None = None
    organization_id: str | None = None


class EmployeeUpdate(BaseModel):
    first_name: str | None = None
    last_name: str | None = None
    email: str | None = None
    role: str | None = None
    department: str | None = None
    organization_id: str | None = None


class EmployeeProfileUpdate(BaseModel):
    """Self-service profile fields an employee may edit for themselves.
    Deliberately excludes role/department/organization_id/login_name,
    which stay admin-only via EmployeeUpdate."""

    first_name: str | None = None
    last_name: str | None = None
    email: str | None = None
    job_description: str | None = None


class EmployeePasswordChange(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8)


class OrganizationRoleCreate(BaseModel):
    organization_id: str
    name: str
    permissions: list[str] = Field(default_factory=list)


class OrganizationRoleUpdate(BaseModel):
    name: str | None = None
    permissions: list[str] | None = None


class OrganizationRoleOut(BaseModel):
    id: str
    name: str
    permissions: list[str] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class DepartmentCreate(BaseModel):
    organization_id: str
    name: str
    role_ids: list[str] = Field(default_factory=list)
    folder_templates: list[str] = Field(default_factory=list)
    project_actions: list[str] = Field(default_factory=list)


class DepartmentUpdate(BaseModel):
    name: str | None = None
    role_ids: list[str] | None = None
    folder_templates: list[str] | None = None
    project_actions: list[str] | None = None


class DepartmentOut(BaseModel):
    id: str
    name: str
    role_ids: list[str] = Field(default_factory=list)
    role_names: list[str] = Field(default_factory=list)
    folder_templates: list[str] = Field(default_factory=list)
    project_actions: list[str] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class ContactBase(BaseModel):
    street: str | None = None
    house_number: str | None = None
    head_of_company: str | None = None
    email: str | None = None
    phone_number: str | None = None


class ContactCreate(ContactBase):
    pass


class ContactUpdate(ContactBase):
    pass


class ContactOut(ContactBase):
    id: str

    model_config = ConfigDict(from_attributes=True)


class CompanyCustomerIn(BaseModel):
    first_name: str | None = None
    last_name: str | None = None
    gender: str | None = None
    email: str | None = None
    role: str | None = None
    phone_number: str | None = None
    mobile_number: str | None = None
    image_url: str | None = None


class CompanyCustomerOut(BaseModel):
    id: str
    first_name: str
    last_name: str
    gender: str
    email: str | None
    role: str | None
    phone_number: str | None
    mobile_number: str | None
    image_url: str | None = None

    model_config = ConfigDict(from_attributes=True)


class OrganizationAdminCreate(BaseModel):
    first_name: str = Field(min_length=1, max_length=255)
    last_name: str = Field(min_length=1, max_length=255)
    email: EmailStr
    login_name: str = Field(min_length=3, max_length=100)
    password: str = Field(min_length=12, max_length=128)


class OrganizationCreate(BaseModel):
    unique_name: str
    unique_code: str | None = None
    logo_url: str | None = None
    contact: ContactCreate | None = None
    initial_admin: OrganizationAdminCreate | None = None


class OrganizationUpdate(BaseModel):
    unique_name: str | None = None
    logo_url: str | None = None
    contact: ContactUpdate | None = None


class OrganizationOut(BaseModel):
    id: str
    unique_name: str
    unique_code: str
    logo_url: str | None
    contact: ContactOut | None = None

    model_config = ConfigDict(from_attributes=True)


class ProjectCreate(BaseModel):
    client_company_id: str = Field(
        validation_alias=AliasChoices("client_company_id", "customer_company_id"),
    )
    name: str
    base_model: BaseModelType = BaseModelType.NORMAL
    start_date: date | None = None


class CustomerCompanyCreate(BaseModel):
    unique_name: str
    unique_code: str | None = None
    logo_url: str | None = None
    contact: ContactCreate | None = None
    customers: list[CompanyCustomerIn] = Field(default_factory=list, max_length=3)
    head_customer_index: int | None = None

    @model_validator(mode="after")
    def validate_head_customer(self):
        if self.head_customer_index is None:
            return self
        if not self.customers:
            raise ValueError("head_customer_index requires customers")
        if self.head_customer_index < 0 or self.head_customer_index >= len(self.customers):
            raise ValueError("head_customer_index out of range")
        return self


class CustomerCompanyUpdate(BaseModel):
    unique_name: str | None = None
    logo_url: str | None = None
    contact: ContactUpdate | None = None
    customers: list[CompanyCustomerIn] | None = Field(default=None, max_length=3)
    head_customer_index: int | None = None

    @model_validator(mode="after")
    def validate_head_customer(self):
        if self.head_customer_index is None:
            return self
        if self.customers is None:
            raise ValueError("head_customer_index requires customers")
        if not self.customers:
            raise ValueError("head_customer_index requires at least one customer")
        if self.head_customer_index < 0 or self.head_customer_index >= len(self.customers):
            raise ValueError("head_customer_index out of range")
        return self


class CustomerCompanyOut(BaseModel):
    id: str
    unique_name: str
    unique_code: str
    logo_url: str | None
    contact: ContactOut | None = None
    customers: list[CompanyCustomerOut] = Field(default_factory=list)
    main_customer_id: str | None = None
    # Nullable: the auto-migration that adds this column to existing
    # databases (see _sync_missing_columns in main.py) can't backfill a
    # default for rows that already exist, since datetime.utcnow is a
    # callable default, not a scalar one — those rows get NULL here.
    created_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)


MainCompanyContactOut = ContactOut
ClientCompanyContactOut = ContactOut
ClientContactIn = CompanyCustomerIn
ClientContactOut = CompanyCustomerOut
MainCompanyCreate = OrganizationCreate
MainCompanyUpdate = OrganizationUpdate
MainCompanyOut = OrganizationOut
ClientCompanyCreate = CustomerCompanyCreate
ClientCompanyUpdate = CustomerCompanyUpdate
ClientCompanyOut = CustomerCompanyOut


class ProjectOut(BaseModel):
    id: str
    customer_company_id: str
    name: str
    base_model: BaseModelType
    start_date: date | None
    status: ProjectStatus
    workflow_stage: str
    gantt_started: bool = False
    gantt_started_at: datetime | None = None
    order_top_note: str | None = None
    order_bottom_note: str | None = None

    model_config = ConfigDict(from_attributes=True)


class ProjectGanttStepOut(BaseModel):
    id: str
    project_id: str
    status_key: str
    title: str
    description: str | None
    planned_start_date: date | None
    planned_end_date: date | None
    is_completed: bool
    is_current: bool
    sort_order: int

    model_config = ConfigDict(from_attributes=True)


class ProjectGanttSubStepOut(BaseModel):
    id: str
    project_id: str
    parent_step_id: str
    title: str
    description: str | None
    planned_start_date: date | None
    planned_end_date: date | None
    assignee_login: str | None
    assignee_logins: list[str] = Field(default_factory=list)
    is_completed: bool
    sort_order: int

    model_config = ConfigDict(from_attributes=True)


class ProjectGanttStepTreeOut(ProjectGanttStepOut):
    sub_steps: list[ProjectGanttSubStepOut] = Field(default_factory=list)


class ProjectGanttSubStepTemplateOut(BaseModel):
    id: str
    parent_template_id: str
    title: str
    description: str | None
    duration_days: int
    sort_order: int

    model_config = ConfigDict(from_attributes=True)


class ProjectGanttSubStepTemplateCreate(BaseModel):
    title: str
    description: str | None = None
    duration_days: int = 1


class ProjectGanttSubStepTemplateUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    duration_days: int | None = None


class ProjectGanttStepTemplateOut(BaseModel):
    id: str
    organization_id: str
    status_key: str
    title: str
    description: str | None
    duration_days: int
    sort_order: int
    sub_step_templates: list[ProjectGanttSubStepTemplateOut] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class ProjectGanttStepTemplateCreate(BaseModel):
    status_key: str
    title: str
    description: str | None = None
    duration_days: int = 7


class ProjectGanttStepTemplateUpdate(BaseModel):
    status_key: str | None = None
    title: str | None = None
    description: str | None = None
    duration_days: int | None = None


class ProjectWorkflowStageUpdate(BaseModel):
    workflow_stage: str


class ProjectGanttStartResponse(BaseModel):
    project: ProjectOut
    gantt_steps: list[ProjectGanttStepOut]


class ProjectGanttTreeResponse(BaseModel):
    project: ProjectOut
    gantt_steps: list[ProjectGanttStepTreeOut]


class ProjectGanttStepDurationUpdate(BaseModel):
    duration_days: int = Field(ge=1)


class ProjectGanttSubStepDurationUpdate(BaseModel):
    duration_days: int = Field(ge=1)


class ProjectGanttSubStepAssigneeUpdate(BaseModel):
    assignee_login: str | None = None


class ProjectGanttSubStepAssigneesUpdate(BaseModel):
    assignee_logins: list[str] = Field(default_factory=list)


class ProjectGanttSubStepCreate(BaseModel):
    title: str
    description: str | None = None
    duration_days: int = Field(default=1, ge=1)


class ProjectBaseModelUpdate(BaseModel):
    base_model: BaseModelType


class ProjectOrderItemOut(BaseModel):
    id: str
    project_id: str
    part_id: str
    part_name: str
    part_number: str | None = None
    quantity: int
    selected: bool
    order_status: PartOrderStatus = PartOrderStatus.IN_PROGRESS
    order_number: str | None = None
    quotation_number: str | None = None
    shipping_number: str | None = None
    supplier: str | None = None
    ordered_at: date | None = None
    expected_delivery_date: date | None = None
    actual_delivery_date: date | None = None
    status_notes: str | None = None

    model_config = ConfigDict(from_attributes=True)


class ProjectOrderItemUpdate(BaseModel):
    quantity: int = 0
    selected: bool = False


class ProjectPartStatusUpdate(BaseModel):
    order_status: PartOrderStatus | None = None
    order_number: str | None = None
    quotation_number: str | None = None
    shipping_number: str | None = None
    supplier: str | None = None
    ordered_at: date | None = None
    expected_delivery_date: date | None = None
    actual_delivery_date: date | None = None
    status_notes: str | None = None


class ProjectOrderNotesUpdate(BaseModel):
    top_note: str | None = None
    bottom_note: str | None = None


class PartDrawingOut(BaseModel):
    id: str
    part_id: str
    file_url: str
    file_name: str

    model_config = ConfigDict(from_attributes=True)


class PartOut(BaseModel):
    id: str
    parent_part_id: str | None
    category_id: str | None = None
    category_name: str | None = None
    category_scope: PartCategoryScope | None = None
    rival_part_id: str | None = None
    name: str
    description: str | None = None
    part_source: str | None = None
    status: str
    notes: str | None = None
    part_role: str
    image_url: str | None
    id_number: str | None
    sell_price: float
    buy_price: float
    cad_file_url: str | None = None
    cad_file_name: str | None = None
    instructions_url: str | None = None
    instructions_name: str | None = None
    drawings: list[PartDrawingOut] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class PartLinkChildrenRequest(BaseModel):
    child_part_ids: list[str]


class PartCategoryCreate(BaseModel):
    name: str
    scope: PartCategoryScope


class PartCategoryOut(BaseModel):
    id: str
    name: str
    scope: PartCategoryScope

    model_config = ConfigDict(from_attributes=True)


class FolderCreate(BaseModel):
    project_id: str
    parent_folder_id: str | None = None
    name: str
    department: str | None = None


class FolderOut(BaseModel):
    id: str
    project_id: str
    parent_folder_id: str | None
    name: str
    department: str | None

    model_config = ConfigDict(from_attributes=True)


# ── Folder access schemas ─────────────────────────────────────────────────────

class FolderDepartmentAccessOut(BaseModel):
    id: str
    department_id: str
    department_name: str

    model_config = ConfigDict(from_attributes=True)


class FolderUserAccessOut(BaseModel):
    id: str
    employee_id: str
    employee_name: str

    model_config = ConfigDict(from_attributes=True)


class FolderAccessOut(BaseModel):
    """Full access snapshot for a folder, used by the admin screen."""
    folder_id: str
    folder_name: str
    project_id: str
    department_access: list[FolderDepartmentAccessOut] = Field(default_factory=list)
    user_access: list[FolderUserAccessOut] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class FolderSetDepartmentAccess(BaseModel):
    department_ids: list[str]


class FolderAddUserAccess(BaseModel):
    employee_id: str


class ProjectStatusUpdate(BaseModel):
    status: ProjectStatus


class FolderRemoveUserAccess(BaseModel):
    employee_id: str


class ProjectFolderTemplateOut(BaseModel):
    id: str
    parent_template_id: str | None
    name: str
    sort_order: int

    model_config = ConfigDict(from_attributes=True)


# Action System Schemas

class WorkflowNodeOut(BaseModel):
    id: str
    name: str
    category: WorkflowNodeCategory
    function: str | None
    endpoint: str | None
    trigger_input: str | None
    configuration: str
    description: str | None
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class WorkflowNodeCreate(BaseModel):
    name: str
    category: WorkflowNodeCategory
    function: str | None = None
    endpoint: str | None = None
    trigger_input: str | None = None
    configuration: str = "{}"
    description: str | None = None
    is_active: bool = True


class WorkflowNodeUpdate(BaseModel):
    name: str | None = None
    category: WorkflowNodeCategory | None = None
    function: str | None = None
    endpoint: str | None = None
    trigger_input: str | None = None
    configuration: str | None = None
    description: str | None = None
    is_active: bool | None = None


class ActionButtonDepartmentOut(BaseModel):
    id: str
    action_button_id: str
    department_id: str

    model_config = ConfigDict(from_attributes=True)


class ActionButtonOut(BaseModel):
    id: str
    organization_id: str | None
    unique_name: str
    description: str | None
    node_graph: str
    workflow_stage: str | None
    is_active: bool
    sort_order: int
    created_at: datetime
    updated_at: datetime
    departments: list[ActionButtonDepartmentOut] = []

    model_config = ConfigDict(from_attributes=True)


class ActionButtonCreate(BaseModel):
    unique_name: str
    description: str | None = None
    node_graph: str = "{}"
    workflow_stage: str | None = None
    is_active: bool = True
    department_ids: list[str] = []


class ActionButtonUpdate(BaseModel):
    unique_name: str | None = None
    description: str | None = None
    node_graph: str | None = None
    workflow_stage: str | None = None
    is_active: bool | None = None
    sort_order: int | None = None
    department_ids: list[str] | None = None


class ActionExecutionOut(BaseModel):
    id: str
    project_id: str
    action_button_id: str
    executed_by_employee_id: str
    execution_status: ActionExecutionStatus
    execution_result: str | None
    error_message: str | None
    started_at: datetime | None
    completed_at: datetime | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ActionExecutionCreate(BaseModel):
    action_button_id: str
    execution_input: str | None = None  # JSON input for execution


class ActionExecutionUpdate(BaseModel):
    execution_status: ActionExecutionStatus | None = None
    execution_result: str | None = None
    error_message: str | None = None


class GoogleMailTestRequest(BaseModel):
    recipient_email: EmailStr
    subject: str | None = None
    body: str | None = None
    project_id: str | None = None


class ProjectFolderTemplateCreate(BaseModel):
    name: str
    parent_template_id: str | None = None


class ProjectFolderTemplateDemoFileOut(BaseModel):
    id: str
    folder_template_id: str
    demo_template_id: str
    target_file_name: str | None
    sort_order: int

    model_config = ConfigDict(from_attributes=True)


class ProjectFolderTemplateDemoFileCreate(BaseModel):
    demo_template_id: str
    target_file_name: str | None = None


class TodoCreate(BaseModel):
    name: str
    organization_id: str | None = None
    project_id: str | None = None
    folder_id: str | None = None
    department: str | None = None
    main_employer: str | None = None
    coworker_logins: list[str] = Field(default_factory=list)
    description: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    project_status: str | ProjectStatus = ProjectStatus.IN_WORK
    sort_order: int | None = None


class TodoUpdate(BaseModel):
    name: str | None = None
    organization_id: str | None = None
    project_id: str | None = None
    folder_id: str | None = None
    department: str | None = None
    main_employer: str | None = None
    coworker_logins: list[str] | None = None
    description: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    project_status: str | ProjectStatus | None = None
    sort_order: int | None = None


class TodoReorderRequest(BaseModel):
    project_status: ProjectStatus
    ordered_todo_ids: list[str]


class TodoRepresentationRequest(BaseModel):
    delegate_login: str
    start_date: date
    end_date: date


class TodoOut(BaseModel):
    id: str
    name: str
    organization_id: str | None
    project_id: str | None
    folder_id: str | None
    department: str | None
    main_employer: str | None
    coworker_logins: list[str] = Field(default_factory=list)
    description: str | None
    start_date: date | None
    end_date: date | None
    project_status: ProjectStatus
    sort_order: int

    model_config = ConfigDict(from_attributes=True)


class DocumentOut(BaseModel):
    id: str
    folder_id: str
    project_id: str
    file_name: str
    mime_type: str | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class FileRenameRequest(BaseModel):
    file_name: str


class FileMoveRequest(BaseModel):
    folder_id: str


class DemoTemplateOut(BaseModel):
    id: str
    file_name: str
    category: str


class CreateFromDemoRequest(BaseModel):
    folder_id: str
    template_id: str
    file_name: str | None = None


class AiSummaryRequest(BaseModel):
    folder_id: str
    project_context: str | None = None


class AiSummaryResponse(BaseModel):
    summary: str
    suggestions: list[str]
    extracted_text_preview: str | None = None


class BusinessCardScanResponse(BaseModel):
    extracted_text: str


class ChatMessageResponse(BaseModel):
    response: str
    error: bool = False


class ProjectAiContextResponse(BaseModel):
    context: str


class ProjectOfferRecipientOut(BaseModel):
    customer_id: str
    name: str
    job_title: str | None = None
    email: str | None = None
    is_project_leader: bool = False


class ProjectOfferSendRequest(BaseModel):
    document_id: str
    customer_ids: list[str]


class ProjectOfferSendResult(BaseModel):
    customer_id: str
    name: str
    email: str | None
    sent: bool
    detail: str


class AiServerConfig(BaseModel):
    name: str
    provider: str = "ollama"  # "ollama" | "openai_compatible" (LM Studio, etc.)
    base_url: str
    api_key: str | None = None
    model: str | None = None


class CompanySettingsOut(BaseModel):
    smtp_host: str | None = None
    smtp_port: int | None = None
    smtp_username: str | None = None
    smtp_use_tls: bool = True
    mail_from: str | None = None
    has_smtp_password: bool = False
    ai_servers: list[AiServerConfig] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class CompanyEmailSettingsUpdate(BaseModel):
    smtp_host: str | None = None
    smtp_port: int | None = None
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_use_tls: bool = True
    mail_from: str | None = None


class AiServersUpdate(BaseModel):
    ai_servers: list[AiServerConfig] = Field(default_factory=list)


class EmployeeMailSettingsOut(BaseModel):
    imap_host: str | None = None
    imap_port: int = 993
    imap_username: str | None = None
    imap_use_ssl: bool = True
    drafts_folder: str = "Drafts"
    has_password: bool = False

    model_config = ConfigDict(from_attributes=True)


class EmployeeMailSettingsUpdate(BaseModel):
    imap_host: str | None = None
    imap_port: int = 993
    imap_username: str | None = None
    imap_password: str | None = None
    imap_use_ssl: bool = True
    drafts_folder: str = "Drafts"


class ManufacturerOut(BaseModel):
    id: str
    organization_id: str
    name: str
    website: str | None = None
    contact_email: str | None = None
    phone_number: str | None = None
    notes: str | None = None

    model_config = ConfigDict(from_attributes=True)


class ManufacturerCreate(BaseModel):
    name: str
    website: str | None = None
    contact_email: str | None = None
    phone_number: str | None = None
    notes: str | None = None


class ManufacturerUpdate(BaseModel):
    name: str | None = None
    website: str | None = None
    contact_email: str | None = None
    phone_number: str | None = None
    notes: str | None = None


class PartOrderDecisionOut(BaseModel):
    id: str
    project_id: str
    part_id: str
    part_name: str
    part_number: str | None = None
    decision: PartDecisionType
    order_id: str
    manufacturer_id: str | None = None
    manufacturer_name: str | None = None
    quantity: int
    placed_at: date
    notes: str | None = None

    model_config = ConfigDict(from_attributes=True)


class PartOrderDecisionEntry(BaseModel):
    part_id: str
    decision: PartDecisionType
    manufacturer_id: str | None = None
    quantity: int = 1
    notes: str | None = None


class PartOrderDecisionBatchCreate(BaseModel):
    entries: list[PartOrderDecisionEntry]
