import enum
import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Enum, Float, ForeignKey, String, Text, UniqueConstraint, select
from sqlalchemy.types import TypeDecorator
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.ext.hybrid import hybrid_property

from .database import Base


class Gender(str, enum.Enum):
    HERR = "Herr"
    FRAU = "Frau"
    DIV = "Div"
    NOT_SPECIFIED = "not_specified"


class BaseModelType(str, enum.Enum):
    NORMAL = "Normal"
    DUBLE = "Duble"
    EXTRA = "Extra"


class PartOrderStatus(str, enum.Enum):
    IN_PROGRESS = "In Progress"
    QUOTATION = "Quotation"
    PURCHASING = "Purchasing"
    ORDERED = "Ordered"
    DELIVERY = "Delivery"
    IN_STOCK = "In Stock"
    LOADED = "Loaded"
    INSTALLED = "Installed"


class ProjectStatus(str, enum.Enum):
    QUOTE = "Quote"
    SALE = "Sale"
    CONSTRUCTION = "Construction"
    PROCUREMENT = "Procurement"
    INSTALLATION = "Installation"
    PROGRAMMING = "Programming"
    DELIVERY = "Delivery"
    COMMISSIONING = "Commissioning"
    FINAL_ACCEPTANCE = "Final Acceptance"
    COMPLETED = "Completed"
    IN_WORK = "inWork"
    IN_WORK_LEGACY = "In Work"
    DONE = "Done"
    DONE_LEGACY = "DONE"
    OVERDUE = "Overdue"
    OVERDUE_LEGACY = "OVERDUE"


class WorkflowNodeCategory(str, enum.Enum):
    ADD_FUNCTIONS = "AddFunctions"
    INFORMATION = "Information"
    TODOS = "Todos"
    AI_ENTRY_POINT = "AIEntryPoint"


class ActionExecutionStatus(str, enum.Enum):
    PENDING = "Pending"
    RUNNING = "Running"
    SUCCESS = "Success"
    FAILED = "Failed"
    CANCELLED = "Cancelled"


class PartCategoryScope(str, enum.Enum):
    MAIN = "main"
    SUB = "sub"


class ProjectStatusType(TypeDecorator):
    """Compatibility mapper that accepts both enum names and values in DB.

    Historical rows contain value strings like "Quote", while some newer rows
    can contain enum names like "QUOTE". This mapper normalizes both forms.
    """

    impl = String(40)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if isinstance(value, ProjectStatus):
            return value.value
        if isinstance(value, str):
            # Accept incoming enum names and normalize to enum value.
            member = ProjectStatus.__members__.get(value)
            if member is not None:
                return member.value
            return value
        return str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        # Preferred: stored as enum value.
        member = ProjectStatus._value2member_map_.get(value)
        if member is not None:
            return member
        # Compatibility: stored as enum name.
        member = ProjectStatus.__members__.get(value)
        if member is not None:
            return member
        # Last resort for unknown legacy values: keep app alive.
        return ProjectStatus.QUOTE


class Organization(Base):
    """The internal tenant company whose employees log in. Its business
    customers (client companies) are tracked separately as CustomerCompany
    rows; Organization itself never holds direct customer/person data."""
    __tablename__ = "organizations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    unique_name: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    unique_code: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    logo_url: Mapped[str | None] = mapped_column(String(500), nullable=True)

    contact: Mapped["Contact"] = relationship(back_populates="organization", uselist=False, cascade="all, delete-orphan")
    employees: Mapped[list["Employee"]] = relationship(back_populates="organization", cascade="all, delete-orphan")
    customer_companies: Mapped[list["CustomerCompany"]] = relationship(
        back_populates="organization",
        cascade="all, delete-orphan",
    )
    roles: Mapped[list["OrganizationRole"]] = relationship(back_populates="organization", cascade="all, delete-orphan")
    departments: Mapped[list["Department"]] = relationship(
        back_populates="organization",
        cascade="all, delete-orphan",
    )
    project_folder_templates: Mapped[list["ProjectFolderTemplate"]] = relationship(
        back_populates="organization",
        cascade="all, delete-orphan",
        order_by="ProjectFolderTemplate.sort_order",
    )
    gantt_step_templates: Mapped[list["ProjectGanttStepTemplate"]] = relationship(
        back_populates="organization",
        cascade="all, delete-orphan",
        order_by="ProjectGanttStepTemplate.sort_order",
    )


class Contact(Base):
    __tablename__ = "contacts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str | None] = mapped_column(ForeignKey("organizations.id"), nullable=True, unique=True)
    customer_company_id: Mapped[str | None] = mapped_column(ForeignKey("customer_companies.id"), nullable=True, unique=True)
    street: Mapped[str | None] = mapped_column(String(255), nullable=True)
    house_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
    head_of_company: Mapped[str | None] = mapped_column(String(255), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    phone_number: Mapped[str | None] = mapped_column(String(50), nullable=True)

    organization: Mapped["Organization"] = relationship(back_populates="contact")
    customer_company: Mapped["CustomerCompany"] = relationship(back_populates="contact")


class Employee(Base):
    __tablename__ = "employees"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str | None] = mapped_column(ForeignKey("organizations.id"), nullable=True)
    last_name: Mapped[str] = mapped_column(String(255))
    first_name: Mapped[str] = mapped_column(String(255))
    job_description: Mapped[str | None] = mapped_column(String(255), nullable=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    login_name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    role: Mapped[str | None] = mapped_column(String(100), nullable=True)
    department: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Super admins are regular Admins of their own organization who may
    # additionally create and manage other organizations.
    is_super_admin: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0")

    organization: Mapped["Organization | None"] = relationship(back_populates="employees")


class OrganizationRole(Base):
    __tablename__ = "organization_roles"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), index=True)
    name: Mapped[str] = mapped_column(String(100), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    organization: Mapped["Organization"] = relationship(back_populates="roles")
    permissions: Mapped[list["OrganizationRolePermission"]] = relationship(
        back_populates="role",
        cascade="all, delete-orphan",
    )
    department_links: Mapped[list["DepartmentRole"]] = relationship(
        back_populates="role",
        cascade="all, delete-orphan",
    )


class OrganizationRolePermission(Base):
    __tablename__ = "organization_role_permissions"
    __table_args__ = (UniqueConstraint("role_id", "permission_key", name="uq_role_permission_key"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    role_id: Mapped[str] = mapped_column(ForeignKey("organization_roles.id"), index=True)
    permission_key: Mapped[str] = mapped_column(String(100), index=True)

    role: Mapped["OrganizationRole"] = relationship(back_populates="permissions")


class Department(Base):
    __tablename__ = "departments"
    __table_args__ = (UniqueConstraint("organization_id", "name", name="uq_department_organization_name"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), index=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    organization: Mapped["Organization"] = relationship(back_populates="departments")
    role_links: Mapped[list["DepartmentRole"]] = relationship(
        back_populates="department",
        cascade="all, delete-orphan",
    )
    folder_templates: Mapped[list["DepartmentFolderTemplate"]] = relationship(
        back_populates="department",
        cascade="all, delete-orphan",
    )
    project_actions: Mapped[list["DepartmentProjectAction"]] = relationship(
        back_populates="department",
        cascade="all, delete-orphan",
    )


class DepartmentRole(Base):
    __tablename__ = "department_roles"
    __table_args__ = (
        UniqueConstraint("department_id", "role_id", name="uq_department_role"),
        UniqueConstraint("role_id", name="uq_role_single_department"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    department_id: Mapped[str] = mapped_column(ForeignKey("departments.id"), index=True)
    role_id: Mapped[str] = mapped_column(ForeignKey("organization_roles.id"), index=True)

    department: Mapped["Department"] = relationship(back_populates="role_links")
    role: Mapped["OrganizationRole"] = relationship(back_populates="department_links")


class DepartmentFolderTemplate(Base):
    __tablename__ = "department_folder_templates"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    department_id: Mapped[str] = mapped_column(ForeignKey("departments.id"), index=True)
    name: Mapped[str] = mapped_column(String(255))
    sort_order: Mapped[int] = mapped_column(default=0)

    department: Mapped["Department"] = relationship(back_populates="folder_templates")


class DepartmentProjectAction(Base):
    __tablename__ = "department_project_actions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    department_id: Mapped[str] = mapped_column(ForeignKey("departments.id"), index=True)
    action_key: Mapped[str] = mapped_column(String(120))
    sort_order: Mapped[int] = mapped_column(default=0)

    department: Mapped["Department"] = relationship(back_populates="project_actions")


class Customer(Base):
    """A person belonging to a client's business. Customers never have
    login credentials and always belong to exactly one CustomerCompany;
    they are never linked to an Organization directly."""
    __tablename__ = "customers"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    customer_company_id: Mapped[str] = mapped_column(ForeignKey("customer_companies.id"), index=True)
    last_name: Mapped[str] = mapped_column(String(255))
    first_name: Mapped[str] = mapped_column(String(255))
    gender: Mapped[Gender] = mapped_column(Enum(Gender), default=Gender.NOT_SPECIFIED)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    role: Mapped[str | None] = mapped_column(String(100), nullable=True)
    phone_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
    mobile_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)

    customer_company: Mapped["CustomerCompany"] = relationship(
        back_populates="customers",
        foreign_keys=[customer_company_id],
    )


class Project(Base):
    """A project always belongs to exactly one CustomerCompany; the owning
    Organization is reached indirectly via customer_company.organization_id
    (see the organization_id hybrid property below) rather than a
    duplicated direct foreign key."""
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    customer_company_id: Mapped[str] = mapped_column(ForeignKey("customer_companies.id"), index=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    base_model: Mapped[BaseModelType] = mapped_column(Enum(BaseModelType), default=BaseModelType.NORMAL)
    main_customer_id: Mapped[str | None] = mapped_column(ForeignKey("customers.id"), nullable=True)
    start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[ProjectStatus] = mapped_column(ProjectStatusType(), default=ProjectStatus.QUOTE)
    workflow_stage: Mapped[str] = mapped_column(String(80), default="project")
    gantt_started: Mapped[bool] = mapped_column(default=False)
    gantt_started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    order_top_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    order_bottom_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    customer_company: Mapped["CustomerCompany"] = relationship(back_populates="projects")
    folders: Mapped[list["Folder"]] = relationship(back_populates="project", cascade="all, delete-orphan")
    order_items: Mapped[list["ProjectOrderItem"]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
        order_by="ProjectOrderItem.created_at.asc()",
    )
    action_executions: Mapped[list["ActionExecution"]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
    )
    gantt_steps: Mapped[list["ProjectGanttStep"]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
        order_by="ProjectGanttStep.sort_order.asc()",
    )
    gantt_sub_steps: Mapped[list["ProjectGanttSubStep"]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
        order_by="ProjectGanttSubStep.sort_order.asc()",
    )

    @hybrid_property
    def organization_id(self) -> str | None:
        return self.customer_company.organization_id if self.customer_company else None

    @organization_id.expression
    def organization_id(cls):
        return (
            select(CustomerCompany.organization_id)
            .where(CustomerCompany.id == cls.customer_company_id)
            .correlate(cls)
            .scalar_subquery()
        )


class Part(Base):
    __tablename__ = "parts_catalog"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    parent_part_id: Mapped[str | None] = mapped_column(ForeignKey("parts_catalog.id"), nullable=True)
    category_id: Mapped[str | None] = mapped_column(ForeignKey("part_categories.id"), nullable=True, index=True)
    rival_part_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    part_source: Mapped[str | None] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="active", index=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    part_role: Mapped[str] = mapped_column(String(20), default="main", index=True)
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    id_number: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    sell_price: Mapped[float] = mapped_column(Float, default=0)
    buy_price: Mapped[float] = mapped_column(Float, default=0)
    cad_file_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    cad_file_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    instructions_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    instructions_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    drawings: Mapped[list["PartDrawing"]] = relationship(
        back_populates="part",
        cascade="all, delete-orphan",
        order_by="PartDrawing.created_at.asc()",
    )
    category: Mapped["PartCategory | None"] = relationship(back_populates="parts")

    @property
    def category_name(self) -> str | None:
        return self.category.name if self.category else None

    @property
    def category_scope(self) -> PartCategoryScope | None:
        return self.category.scope if self.category else None


class PartCategory(Base):
    __tablename__ = "part_categories"
    __table_args__ = (UniqueConstraint("scope", "name", name="uq_part_categories_scope_name"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    scope: Mapped[PartCategoryScope] = mapped_column(Enum(PartCategoryScope), index=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    parts: Mapped[list["Part"]] = relationship(back_populates="category")


class ProjectOrderItem(Base):
    __tablename__ = "project_order_items"
    __table_args__ = (UniqueConstraint("project_id", "part_id", name="uq_project_order_items_project_part"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    part_id: Mapped[str] = mapped_column(ForeignKey("parts_catalog.id"), index=True)
    quantity: Mapped[int] = mapped_column(default=0)
    selected: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # Procurement / part-management tracking, shown on the project's Parts
    # Status screen so delayed or never-ordered parts are visible early.
    order_status: Mapped[PartOrderStatus] = mapped_column(
        Enum(PartOrderStatus), default=PartOrderStatus.IN_PROGRESS
    )
    order_number: Mapped[str | None] = mapped_column(String(120), nullable=True)
    quotation_number: Mapped[str | None] = mapped_column(String(120), nullable=True)
    shipping_number: Mapped[str | None] = mapped_column(String(120), nullable=True)
    supplier: Mapped[str | None] = mapped_column(String(255), nullable=True)
    ordered_at: Mapped[date | None] = mapped_column(Date, nullable=True)
    expected_delivery_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    actual_delivery_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status_notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    project: Mapped["Project"] = relationship(back_populates="order_items")
    part: Mapped["Part"] = relationship()


class PartDrawing(Base):
    __tablename__ = "part_drawings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    part_id: Mapped[str] = mapped_column(ForeignKey("parts_catalog.id"), nullable=False, index=True)
    file_url: Mapped[str] = mapped_column(String(500))
    file_name: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    part: Mapped["Part"] = relationship(back_populates="drawings")


class CustomerCompany(Base):
    """A client company belonging to exactly one Organization. Holds its
    own Customers (persons) and Projects; never has login credentials of
    its own - only the Organization's Employees log in."""
    __tablename__ = "customer_companies"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), index=True)
    unique_name: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    unique_code: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    logo_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    organization: Mapped["Organization"] = relationship(back_populates="customer_companies")
    contact: Mapped["Contact"] = relationship(back_populates="customer_company", uselist=False, cascade="all, delete-orphan")
    images: Mapped[list["CustomerCompanyImage"]] = relationship(
        back_populates="customer_company",
        cascade="all, delete-orphan",
    )
    customers: Mapped[list["Customer"]] = relationship(
        back_populates="customer_company",
        cascade="all, delete-orphan",
        foreign_keys="Customer.customer_company_id",
    )
    projects: Mapped[list["Project"]] = relationship(back_populates="customer_company", cascade="all, delete-orphan")
    main_customer_id: Mapped[str | None] = mapped_column(
        ForeignKey("customers.id", use_alter=True, name="fk_customer_companies_main_customer_id"),
        nullable=True,
    )


class CustomerCompanyImage(Base):
    __tablename__ = "customer_company_images"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    customer_company_id: Mapped[str] = mapped_column(ForeignKey("customer_companies.id"), index=True)
    file_url: Mapped[str] = mapped_column(String(500))
    file_name: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    customer_company: Mapped["CustomerCompany"] = relationship(back_populates="images")


class Folder(Base):
    __tablename__ = "folders"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    parent_folder_id: Mapped[str | None] = mapped_column(ForeignKey("folders.id"), nullable=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    department: Mapped[str | None] = mapped_column(String(100), nullable=True)

    project: Mapped["Project"] = relationship(back_populates="folders")
    department_access: Mapped[list["FolderDepartmentAccess"]] = relationship(
        back_populates="folder",
        cascade="all, delete-orphan",
    )
    user_access: Mapped[list["FolderUserAccess"]] = relationship(
        back_populates="folder",
        cascade="all, delete-orphan",
    )


class ProjectFolderTemplate(Base):
    """Default folders created automatically when a new project is created.

    If no rows exist for the organization the hardcoded defaults are used instead.
    """
    __tablename__ = "project_folder_templates"
    __table_args__ = (UniqueConstraint("organization_id", "name", name="uq_project_folder_template"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), index=True)
    parent_template_id: Mapped[str | None] = mapped_column(ForeignKey("project_folder_templates.id"), nullable=True)
    name: Mapped[str] = mapped_column(String(255))
    sort_order: Mapped[int] = mapped_column(default=0)

    organization: Mapped["Organization"] = relationship(back_populates="project_folder_templates")
    parent_template: Mapped["ProjectFolderTemplate | None"] = relationship(
        remote_side="ProjectFolderTemplate.id",
        back_populates="children",
    )
    children: Mapped[list["ProjectFolderTemplate"]] = relationship(
        back_populates="parent_template",
        cascade="all, delete-orphan",
        order_by="ProjectFolderTemplate.sort_order",
    )
    demo_files: Mapped[list["ProjectFolderTemplateDemoFile"]] = relationship(
        back_populates="folder_template",
        cascade="all, delete-orphan",
        order_by="ProjectFolderTemplateDemoFile.sort_order",
    )


class ProjectFolderTemplateDemoFile(Base):
    """Demo files that should be copied when a project folder is created from template."""
    __tablename__ = "project_folder_template_demo_files"
    __table_args__ = (
        UniqueConstraint("folder_template_id", "demo_template_id", name="uq_folder_template_demo_file"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    folder_template_id: Mapped[str] = mapped_column(ForeignKey("project_folder_templates.id"), index=True)
    demo_template_id: Mapped[str] = mapped_column(String(512))
    target_file_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    sort_order: Mapped[int] = mapped_column(default=0)

    folder_template: Mapped["ProjectFolderTemplate"] = relationship(back_populates="demo_files")


class FolderDepartmentAccess(Base):
    """Restricts folder visibility to specific departments.

    When a folder has NO rows here it is visible to everyone.
    When it has one or more rows only those departments can see it
    (plus any users with a personal FolderUserAccess grant).
    """
    __tablename__ = "folder_department_access"
    __table_args__ = (UniqueConstraint("folder_id", "department_id", name="uq_folder_dept_access"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    folder_id: Mapped[str] = mapped_column(ForeignKey("folders.id"), index=True)
    department_id: Mapped[str] = mapped_column(ForeignKey("departments.id"), index=True)

    folder: Mapped["Folder"] = relationship(back_populates="department_access")
    department: Mapped["Department"] = relationship()


class FolderUserAccess(Base):
    """Per-user folder access grant. Overrides department restrictions for that user."""
    __tablename__ = "folder_user_access"
    __table_args__ = (UniqueConstraint("folder_id", "employee_id", name="uq_folder_user_access"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    folder_id: Mapped[str] = mapped_column(ForeignKey("folders.id"), index=True)
    employee_id: Mapped[str] = mapped_column(ForeignKey("employees.id"), index=True)

    folder: Mapped["Folder"] = relationship(back_populates="user_access")
    employee: Mapped["Employee"] = relationship()


class Document(Base):
    __tablename__ = "documents"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    folder_id: Mapped[str] = mapped_column(ForeignKey("folders.id"), index=True)
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    file_name: Mapped[str] = mapped_column(String(255), index=True)
    file_path: Mapped[str] = mapped_column(String(1024), unique=True)
    mime_type: Mapped[str | None] = mapped_column(String(255), nullable=True)
    uploaded_by_employee_id: Mapped[str | None] = mapped_column(ForeignKey("employees.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Todo(Base):
    __tablename__ = "todos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str | None] = mapped_column(ForeignKey("organizations.id"), nullable=True, index=True)
    project_id: Mapped[str | None] = mapped_column(ForeignKey("projects.id"), nullable=True, index=True)
    gantt_sub_step_id: Mapped[str | None] = mapped_column(ForeignKey("project_gantt_sub_steps.id"), nullable=True, index=True)
    gantt_assignee_login: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    folder_id: Mapped[str | None] = mapped_column(ForeignKey("folders.id"), nullable=True, index=True)
    department: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    main_employer: Mapped[str | None] = mapped_column(String(255), nullable=True)
    coworker_logins: Mapped[str | None] = mapped_column(Text, nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    project_status: Mapped[ProjectStatus] = mapped_column(ProjectStatusType(), default=ProjectStatus.IN_WORK)
    sort_order: Mapped[int] = mapped_column(default=0, index=True)
    representation_delegate_login: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    representation_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    representation_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    representation_original_main_employer: Mapped[str | None] = mapped_column(String(255), nullable=True)
    representation_active: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class ProjectGanttStep(Base):
    __tablename__ = "project_gantt_steps"
    __table_args__ = (
        UniqueConstraint("project_id", "sort_order", name="uq_project_gantt_steps_project_sort"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    status_key: Mapped[str] = mapped_column(String(80), index=True)
    title: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    planned_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    planned_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    is_completed: Mapped[bool] = mapped_column(default=False)
    is_current: Mapped[bool] = mapped_column(default=False)
    sort_order: Mapped[int] = mapped_column(default=0, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    project: Mapped["Project"] = relationship(back_populates="gantt_steps")
    sub_steps: Mapped[list["ProjectGanttSubStep"]] = relationship(
        back_populates="parent_step",
        cascade="all, delete-orphan",
        order_by="ProjectGanttSubStep.sort_order.asc()",
    )


class ProjectGanttSubStep(Base):
    __tablename__ = "project_gantt_sub_steps"
    __table_args__ = (
        UniqueConstraint("parent_step_id", "sort_order", name="uq_project_gantt_sub_steps_parent_sort"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    parent_step_id: Mapped[str] = mapped_column(ForeignKey("project_gantt_steps.id"), index=True)
    title: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    planned_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    planned_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    assignee_login: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    is_completed: Mapped[bool] = mapped_column(default=False)
    sort_order: Mapped[int] = mapped_column(default=0, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    project: Mapped["Project"] = relationship(back_populates="gantt_sub_steps")
    parent_step: Mapped["ProjectGanttStep"] = relationship(back_populates="sub_steps")
    assignees: Mapped[list["ProjectGanttSubStepAssignee"]] = relationship(
        back_populates="sub_step",
        cascade="all, delete-orphan",
    )

    @property
    def assignee_logins(self) -> list[str]:
        result: list[str] = []
        for link in self.assignees:
            if link.employee and link.employee.login_name:
                result.append(link.employee.login_name)
        return result


class ProjectGanttSubStepAssignee(Base):
    __tablename__ = "project_gantt_sub_step_assignees"
    __table_args__ = (
        UniqueConstraint("sub_step_id", "employee_id", name="uq_gantt_sub_step_assignee"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    sub_step_id: Mapped[str] = mapped_column(ForeignKey("project_gantt_sub_steps.id"), index=True)
    employee_id: Mapped[str] = mapped_column(ForeignKey("employees.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    sub_step: Mapped["ProjectGanttSubStep"] = relationship(back_populates="assignees")
    employee: Mapped["Employee"] = relationship()


class ProjectGanttStepTemplate(Base):
    __tablename__ = "project_gantt_step_templates"
    __table_args__ = (
        UniqueConstraint("organization_id", "sort_order", name="uq_project_gantt_step_templates_organization_sort"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), index=True)
    status_key: Mapped[str] = mapped_column(String(80), index=True)
    title: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    duration_days: Mapped[int] = mapped_column(default=7)
    sort_order: Mapped[int] = mapped_column(default=0, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    organization: Mapped["Organization"] = relationship(back_populates="gantt_step_templates")
    sub_step_templates: Mapped[list["ProjectGanttSubStepTemplate"]] = relationship(
        back_populates="parent_template",
        cascade="all, delete-orphan",
        order_by="ProjectGanttSubStepTemplate.sort_order.asc()",
    )


class ProjectGanttSubStepTemplate(Base):
    """Admin-defined default sub-step (deep step) under a Gantt step
    template. When a new project's gantt is initialized, if a step's
    template has sub-step templates, they're used to create the step's
    real sub-steps instead of the generic auto-split "Detail 1/2/3"
    fallback."""
    __tablename__ = "project_gantt_sub_step_templates"
    __table_args__ = (
        UniqueConstraint(
            "parent_template_id", "sort_order", name="uq_project_gantt_sub_step_templates_parent_sort"
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    parent_template_id: Mapped[str] = mapped_column(
        ForeignKey("project_gantt_step_templates.id"), index=True
    )
    title: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    duration_days: Mapped[int] = mapped_column(default=1)
    sort_order: Mapped[int] = mapped_column(default=0, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    parent_template: Mapped["ProjectGanttStepTemplate"] = relationship(
        back_populates="sub_step_templates"
    )


class ActionButton(Base):
    """Project Action Button - represents a workflow step in a project."""
    __tablename__ = "action_buttons"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str | None] = mapped_column(ForeignKey("organizations.id"), nullable=True, index=True)
    unique_name: Mapped[str] = mapped_column(String(255), index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    node_graph: Mapped[str] = mapped_column(Text, default="{}")  # JSON serialized node graph
    workflow_stage: Mapped[str | None] = mapped_column(String(80), nullable=True)  # Next workflow stage
    is_active: Mapped[bool] = mapped_column(default=True)
    sort_order: Mapped[int] = mapped_column(default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    organization: Mapped["Organization"] = relationship()
    departments: Mapped[list["ActionButtonDepartment"]] = relationship(
        back_populates="action_button",
        cascade="all, delete-orphan",
    )
    executions: Mapped[list["ActionExecution"]] = relationship(
        back_populates="action_button",
        cascade="all, delete-orphan",
    )


class ActionButtonDepartment(Base):
    """Links ActionButtons to Departments - only users in these departments can see the button."""
    __tablename__ = "action_button_departments"
    __table_args__ = (UniqueConstraint("action_button_id", "department_id", name="uq_action_button_dept"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    action_button_id: Mapped[str] = mapped_column(ForeignKey("action_buttons.id"), index=True)
    department_id: Mapped[str] = mapped_column(ForeignKey("departments.id"), index=True)

    action_button: Mapped["ActionButton"] = relationship(back_populates="departments")
    department: Mapped["Department"] = relationship()


class WorkflowNode(Base):
    """Workflow Node - represents a node in the action workflow."""
    __tablename__ = "workflow_nodes"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str | None] = mapped_column(ForeignKey("organizations.id"), nullable=True, index=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    category: Mapped[WorkflowNodeCategory] = mapped_column(Enum(WorkflowNodeCategory), index=True)
    function: Mapped[str | None] = mapped_column(String(255), nullable=True)
    endpoint: Mapped[str | None] = mapped_column(String(500), nullable=True)
    trigger_input: Mapped[str | None] = mapped_column(String(255), nullable=True)
    configuration: Mapped[str] = mapped_column(Text, default="{}")  # JSON configuration
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    organization: Mapped["Organization"] = relationship()


class ActionExecution(Base):
    """Execution record of an Action Button in a Project."""
    __tablename__ = "action_executions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    action_button_id: Mapped[str] = mapped_column(ForeignKey("action_buttons.id"), index=True)
    executed_by_employee_id: Mapped[str] = mapped_column(ForeignKey("employees.id"), index=True)
    execution_status: Mapped[ActionExecutionStatus] = mapped_column(
        Enum(ActionExecutionStatus), default=ActionExecutionStatus.PENDING, index=True
    )
    execution_result: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON result data
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    project: Mapped["Project"] = relationship()
    action_button: Mapped["ActionButton"] = relationship(back_populates="executions")
    executed_by_employee: Mapped["Employee"] = relationship()


class OrganizationSettings(Base):
    """Per-organization server settings: outgoing SMTP relay + saved AI server
    presets (Ollama, LM Studio, or any OpenAI-compatible endpoint), edited
    from the admin "Server Settings" screen."""
    __tablename__ = "organization_settings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), unique=True, index=True)

    smtp_host: Mapped[str | None] = mapped_column(String(255), nullable=True)
    smtp_port: Mapped[int | None] = mapped_column(nullable=True)
    smtp_username: Mapped[str | None] = mapped_column(String(255), nullable=True)
    smtp_password: Mapped[str | None] = mapped_column(String(500), nullable=True)
    smtp_use_tls: Mapped[bool] = mapped_column(default=True)
    mail_from: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # JSON-encoded list of {name, provider, base_url, api_key, model}
    ai_servers: Mapped[str] = mapped_column(Text, default="[]")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    organization: Mapped["Organization"] = relationship()


class EmployeeMailSettings(Base):
    """Personal IMAP credentials for an employee's own mailbox, used by the
    'Save Email Draft' workflow node to file a draft directly into that
    employee's Drafts folder."""
    __tablename__ = "employee_mail_settings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    employee_id: Mapped[str] = mapped_column(ForeignKey("employees.id"), unique=True, index=True)

    imap_host: Mapped[str | None] = mapped_column(String(255), nullable=True)
    imap_port: Mapped[int | None] = mapped_column(default=993)
    imap_username: Mapped[str | None] = mapped_column(String(255), nullable=True)
    imap_password: Mapped[str | None] = mapped_column(String(500), nullable=True)
    imap_use_ssl: Mapped[bool] = mapped_column(default=True)
    drafts_folder: Mapped[str] = mapped_column(String(255), default="Drafts")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    employee: Mapped["Employee"] = relationship()


class Manufacturer(Base):
    """Admin-managed manufacturer/supplier a part can be ordered from. Its
    own dedicated table, scoped per organization, separate from the parts
    catalog itself."""
    __tablename__ = "manufacturers"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), index=True)
    name: Mapped[str] = mapped_column(String(255))
    website: Mapped[str | None] = mapped_column(String(500), nullable=True)
    contact_email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    phone_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    organization: Mapped["Organization"] = relationship()


class PartDecisionType(str, enum.Enum):
    STORAGE = "Storage"
    SELF_MANUFACTURE = "Self Manufacture"
    ORDER = "Order"


class PartOrderDecision(Base):
    """Records how a project is sourcing a specific part once the project
    has moved past the Sale status: pull it from Storage, make it
    in-house (Self Manufacture), or Order it from a manufacturer. A new
    row (with its own order_id and placed_at date) is created every time
    a decision is saved for a part, so the history of sourcing decisions
    for a project is preserved rather than overwritten. Its own dedicated
    table, separate from ProjectOrderItem (which tracks the project's
    order *form*, not how each part gets sourced)."""
    __tablename__ = "part_order_decisions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id"), index=True)
    part_id: Mapped[str] = mapped_column(ForeignKey("parts_catalog.id"), index=True)
    decision: Mapped[PartDecisionType] = mapped_column(Enum(PartDecisionType))
    order_id: Mapped[str] = mapped_column(String(36), unique=True, index=True)
    manufacturer_id: Mapped[str | None] = mapped_column(
        ForeignKey("manufacturers.id"), nullable=True
    )
    quantity: Mapped[int] = mapped_column(default=1)
    placed_at: Mapped[date] = mapped_column(Date, default=date.today)
    placed_by_employee_id: Mapped[str | None] = mapped_column(
        ForeignKey("employees.id"), nullable=True
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    project: Mapped["Project"] = relationship()
    part: Mapped["Part"] = relationship()
    manufacturer: Mapped["Manufacturer | None"] = relationship()
