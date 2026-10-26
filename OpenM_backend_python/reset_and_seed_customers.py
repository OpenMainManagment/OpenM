#!/usr/bin/env python3
"""Full demo reset: wipes the entire database and storage, then seeds a
complete demo dataset from scratch.

This script is meant purely to restart the demo process. It does NOT try
to preserve anything - every table is dropped and recreated, and all
project storage on disk is removed.

Seeds:
    - 1 organization ("OpenM Demo GmbH")
    - Departments + organization roles (one role per department)
    - Organization settings (empty SMTP / AI server config)
    - Project folder templates (Angebot, Auftrag, Nacharbeit)
    - Project gantt step templates (Sale .. Completed)
    - Admin employee (password is entered interactively) + 6 other
      employees with generated passwords
    - A part category with a handful of demo parts
    - 2 demo manufacturers
    - 3 demo customer companies, each with 3 customer contacts and a
      freshly created project (with default folders)

Usage:
    python reset_and_seed_customers.py
    python reset_and_seed_customers.py --force
"""

import argparse
import getpass
import secrets
import shutil
import sys
from datetime import date

from app.auth import get_password_hash
from app.database import Base, SessionLocal, engine
from app.models import (
    BaseModelType,
    Contact,
    Customer,
    CustomerCompany,
    Department,
    DepartmentRole,
    Employee,
    Folder,
    Gender,
    Manufacturer,
    Organization,
    OrganizationRole,
    OrganizationSettings,
    Part,
    PartCategory,
    PartCategoryScope,
    Project,
    ProjectFolderTemplate,
    ProjectGanttStepTemplate,
    ProjectStatus,
)
from app.services.storage_paths import ensure_folder_storage_dir, resolve_storage_root

STORAGE_ROOT = resolve_storage_root()

# Every non-admin employee gets its own department; the admin sits in
# "Management" alongside them.
DEMO_DEPARTMENTS_AND_EMPLOYEES = [
    ("Management", "admin", "System", "Admin", "Admin", "admin@openm.local"),
    ("Verkauf", "manager", "Sabine", "Verkauf", "Manager", "manager@openm.local"),
    ("Verkauf", "sales1", "Peter", "Kaufmann", "Employee", "sales1@openm.local"),
    ("Technik", "technik1", "Laura", "Techniker", "Employee", "technik1@openm.local"),
    ("Einkauf", "einkauf1", "Julia", "Einkaeufer", "Employee", "einkauf1@openm.local"),
    ("Lager", "lager1", "Max", "Lagerist", "Employee", "lager1@openm.local"),
    ("Buchhaltung", "buchhaltung1", "Nina", "Buchhalter", "Employee", "buchhaltung1@openm.local"),
    ("Support", "support1", "Tom", "Support", "Employee", "support1@openm.local"),
]

DEFAULT_FOLDER_NAMES = ["Angebot", "Auftrag", "Nacharbeit"]
DEFAULT_GANTT_TEMPLATE_STATUS_KEYS = [
    "Sale",
    "Construction",
    "Procurement",
    "Installation",
    "Programming",
    "Delivery",
    "Commissioning",
    "Final Acceptance",
    "Completed",
]

DEMO_PARTS = [
    ("Steuerungsmodul A", "STM-A-100", 249.00, 149.00),
    ("Sensor-Kit B", "SNS-B-200", 89.50, 45.00),
    ("Gehaeuse C", "GHS-C-300", 39.90, 18.00),
    ("Antrieb D", "ANT-D-400", 599.00, 380.00),
]

DEMO_MANUFACTURERS = ["Siemens", "Festo"]

DEMO_CUSTOMER_COMPANIES = [
    {
        "unique_name": "Muster GmbH",
        "unique_code": "CUST-001",
        "customers": [
            ("Anna", "Muster", "Geschaeftsfuehrung"),
            ("Peter", "Bauer", "Einkauf"),
            ("Laura", "Fischer", "Technik"),
        ],
    },
    {
        "unique_name": "Beispiel AG",
        "unique_code": "CUST-002",
        "customers": [
            ("Markus", "Weber", "Geschaeftsfuehrung"),
            ("Julia", "Hofmann", "Einkauf"),
            ("Stefan", "Keller", "Technik"),
        ],
    },
    {
        "unique_name": "Test Solutions KG",
        "unique_code": "CUST-003",
        "customers": [
            ("Sabine", "Schmidt", "Geschaeftsfuehrung"),
            ("Thomas", "Wagner", "Einkauf"),
            ("Nina", "Schulz", "Technik"),
        ],
    },
]


def wipe_database_and_storage() -> None:
    print("Dropping all tables...")
    Base.metadata.drop_all(bind=engine)
    print("Recreating schema...")
    Base.metadata.create_all(bind=engine)

    print("Clearing storage directory...")
    for child in STORAGE_ROOT.iterdir():
        if child.is_dir():
            shutil.rmtree(child, ignore_errors=True)
            child.mkdir(parents=True, exist_ok=True)
        else:
            child.unlink(missing_ok=True)


def seed_organization_structure(db) -> Organization:
    print("Seeding organization...")
    organization = Organization(unique_name="OpenM Demo GmbH", unique_code="ORG-DEMO")
    db.add(organization)
    db.flush()

    organization.contact = Contact(organization_id=organization.id, email="info@openm-demo.example")

    db.add(OrganizationSettings(organization_id=organization.id, ai_servers="[]"))

    department_by_name: dict[str, Department] = {}
    for department_name, *_rest in DEMO_DEPARTMENTS_AND_EMPLOYEES:
        if department_name in department_by_name:
            continue
        department = Department(organization_id=organization.id, name=department_name)
        db.add(department)
        db.flush()

        role = OrganizationRole(organization_id=organization.id, name=f"{department_name} Team")
        db.add(role)
        db.flush()
        db.add(DepartmentRole(department_id=department.id, role_id=role.id))

        department_by_name[department_name] = department

    for index, name in enumerate(DEFAULT_FOLDER_NAMES):
        db.add(
            ProjectFolderTemplate(
                organization_id=organization.id,
                name=name,
                sort_order=index,
            )
        )

    for index, status_key in enumerate(DEFAULT_GANTT_TEMPLATE_STATUS_KEYS):
        db.add(
            ProjectGanttStepTemplate(
                organization_id=organization.id,
                status_key=status_key,
                title=status_key,
                duration_days=7,
                sort_order=index,
            )
        )

    for name in DEMO_MANUFACTURERS:
        db.add(Manufacturer(organization_id=organization.id, name=name))

    part_category = PartCategory(scope=PartCategoryScope.MAIN, name="Standard")
    db.add(part_category)
    db.flush()

    for name, id_number, sell_price, buy_price in DEMO_PARTS:
        db.add(
            Part(
                category_id=part_category.id,
                name=name,
                id_number=id_number,
                sell_price=sell_price,
                buy_price=buy_price,
                part_role="main",
                status="active",
            )
        )

    db.commit()
    print(f"  Organization: {organization.unique_name}")
    print(f"  Departments: {len(department_by_name)}")
    print(f"  Parts: {len(DEMO_PARTS)}")
    print(f"  Manufacturers: {len(DEMO_MANUFACTURERS)}")
    return organization


def seed_employees(db, organization: Organization, admin_password: str) -> None:
    print("Seeding admin + 6 other employees...")
    for department_name, login_name, first_name, last_name, role, email in DEMO_DEPARTMENTS_AND_EMPLOYEES:
        password = (
            admin_password
            if role.lower() == "admin"
            else secrets.token_urlsafe(24)
        )
        db.add(
            Employee(
                organization_id=organization.id,
                first_name=first_name,
                last_name=last_name,
                email=email,
                login_name=login_name,
                hashed_password=get_password_hash(password),
                role=role,
                department=department_name,
            )
        )
    db.commit()
    print(f"  Employees: {len(DEMO_DEPARTMENTS_AND_EMPLOYEES)}")


def seed_demo_customer_companies(db, organization: Organization) -> None:
    print("Seeding 3 demo customer companies with projects...")

    for entry in DEMO_CUSTOMER_COMPANIES:
        customer_company = CustomerCompany(
            unique_name=entry["unique_name"],
            unique_code=entry["unique_code"],
            organization_id=organization.id,
        )
        db.add(customer_company)
        db.flush()

        customers = []
        for first_name, last_name, role in entry["customers"]:
            customer = Customer(
                customer_company_id=customer_company.id,
                first_name=first_name,
                last_name=last_name,
                gender=Gender.NOT_SPECIFIED,
                role=role,
                email=(
                    f"{first_name}.{last_name}"
                    f"@{entry['unique_code'].lower()}.example"
                ).replace(" ", ""),
            )
            db.add(customer)
            customers.append(customer)
        db.flush()

        customer_company.main_customer_id = customers[0].id
        head_name = f"{customers[0].first_name} {customers[0].last_name}".strip()
        customer_company.contact = Contact(customer_company_id=customer_company.id, head_of_company=head_name)

        project = Project(
            customer_company_id=customer_company.id,
            name=f"{entry['unique_name']} Projekt 1",
            base_model=BaseModelType.NORMAL,
            start_date=date.today(),
            status=ProjectStatus.QUOTE,
            workflow_stage="project",
            gantt_started=False,
        )
        db.add(project)
        db.flush()

        for folder_name in DEFAULT_FOLDER_NAMES:
            folder = Folder(project_id=project.id, name=folder_name, parent_folder_id=None)
            db.add(folder)
            db.flush()
            ensure_folder_storage_dir(db, folder, STORAGE_ROOT)

    db.commit()

    print(f"  Customer companies: {len(DEMO_CUSTOMER_COMPANIES)}")
    print(f"  Projects: {len(DEMO_CUSTOMER_COMPANIES)}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__
    )

    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip confirmation prompt.",
    )

    args = parser.parse_args()

    if not args.force:
        answer = input(
            "This will DELETE THE ENTIRE DATABASE and all project storage, "
            "then seed a fresh demo dataset. "
            "Continue? [y/N] "
        )

        if answer.strip().lower() not in ("y", "yes"):
            print("Aborted.")
            sys.exit(1)

    admin_password = getpass.getpass(
        "Set the demo administrator password (at least 12 characters): "
    )
    if len(admin_password) < 12:
        parser.error("The administrator password must be at least 12 characters")
    if admin_password != getpass.getpass("Confirm administrator password: "):
        parser.error("Administrator passwords do not match")

    db = SessionLocal()

    try:
        print()
        print("========================================")
        print(" FULL DEMO RESET")
        print("========================================")

        wipe_database_and_storage()

        organization = seed_organization_structure(db)
        seed_employees(db, organization, admin_password)
        seed_demo_customer_companies(db, organization)

        print()
        print("========================================")
        print(" DONE")
        print("========================================")
        print("Login name: admin (password was entered interactively)")
        print("========================================")

    except Exception:
        db.rollback()
        raise

    finally:
        db.close()


if __name__ == "__main__":
    main()