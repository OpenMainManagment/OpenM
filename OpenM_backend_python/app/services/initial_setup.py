from sqlalchemy.orm import Session

from ..models import Employee


def is_initial_setup_required(db: Session) -> bool:
    return db.query(Employee.id).first() is None
