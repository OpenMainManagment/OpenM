import os
from datetime import datetime, timedelta, timezone
import base64
import hashlib
import hmac
import secrets

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from .database import DATABASE_DIR, get_db
from .models import Employee


def _load_secret_key() -> str:
    configured_key = os.getenv("OPENM_SECRET_KEY")
    if configured_key:
        if len(configured_key) < 32:
            raise RuntimeError("OPENM_SECRET_KEY must be at least 32 characters long")
        return configured_key

    key_path = DATABASE_DIR / ".openm_jwt_secret"
    if key_path.exists():
        secret_key = key_path.read_text(encoding="utf-8").strip()
    else:
        secret_key = secrets.token_urlsafe(64)
        try:
            with key_path.open("x", encoding="utf-8") as secret_file:
                secret_file.write(secret_key)
        except FileExistsError:
            secret_key = key_path.read_text(encoding="utf-8").strip()

    if len(secret_key) < 32:
        raise RuntimeError(f"JWT signing key file is invalid: {key_path}")
    return secret_key


SECRET_KEY = _load_secret_key()
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 8

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")
ROLE_LEVELS = {"employee": 1, "manager": 2, "admin": 3}


def _pbkdf2_hash(password: str, salt: bytes, iterations: int = 100000) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        scheme, iter_text, salt_b64, digest_b64 = hashed_password.split("$", 3)
        if scheme != "pbkdf2_sha256":
            return False
        iterations = int(iter_text)
        salt = base64.b64decode(salt_b64.encode("ascii"))
        expected = base64.b64decode(digest_b64.encode("ascii"))
        actual = _pbkdf2_hash(plain_password, salt, iterations)
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def get_password_hash(password: str) -> str:
    iterations = 100000
    salt = secrets.token_bytes(16)
    digest = _pbkdf2_hash(password, salt, iterations)
    return "pbkdf2_sha256$%s$%s$%s" % (
        iterations,
        base64.b64encode(salt).decode("ascii"),
        base64.b64encode(digest).decode("ascii"),
    )


def create_access_token(subject: str, organization_id: str | None = None, expires_delta: timedelta | None = None) -> str:
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    payload = {"sub": subject, "exp": expire}
    if organization_id is not None:
        payload["organization_id"] = organization_id
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def get_current_employee(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Employee:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        employee_id = payload.get("sub")
        if employee_id is None:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    employee = db.get(Employee, employee_id)
    if employee is None:
        raise credentials_exception
    return employee


def get_current_admin(current_employee: Employee = Depends(get_current_employee)) -> Employee:
    if (current_employee.role or "").lower() != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin role required")
    return current_employee


def get_current_super_admin(current_admin: Employee = Depends(get_current_admin)) -> Employee:
    if not current_admin.is_super_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Super admin role required")
    return current_admin


def require_min_role(current_employee: Employee, required_level: int) -> Employee:
    current_level = ROLE_LEVELS.get((current_employee.role or "employee").lower(), 1)
    if current_level < required_level:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient role")
    return current_employee


def get_current_manager_or_admin(current_employee: Employee = Depends(get_current_employee)) -> Employee:
    return require_min_role(current_employee, ROLE_LEVELS["manager"])
