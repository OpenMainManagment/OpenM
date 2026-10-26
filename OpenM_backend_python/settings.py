"""
Application configuration settings.
This file contains the core configuration values for the OpenM backend application.
"""

import os
from typing import Optional

# Database configuration
DATABASE_URL = os.getenv("OpenM_DATABASE_URL", "sqlite:///./openm.db")

# Security settings
SECRET_KEY = os.getenv("OPENM_SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# Email settings (from environment variables)
SMTP_HOST = os.getenv("OPENM_SMTP_HOST", "")
SMTP_PORT = int(os.getenv("OPENM_SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("OPENM_SMTP_USERNAME", "")
SMTP_PASSWORD = os.getenv("OPENM_SMTP_PASSWORD", "")
SMTP_USE_TLS = os.getenv("OPENM_SMTP_USE_TLS", "true").lower() == "true"
MAIL_FROM = os.getenv("OPENM_MAIL_FROM", "")

# Storage settings
STORAGE_ROOT = os.getenv("OPENM_STORAGE_ROOT", "./storage")

# AI/ML settings
OLLAMA_BASE_URL = os.getenv("OpenM_OLLAMA_BASE_URL", "http://localhost:11434")
LM_STUDIO_BASE_URL = os.getenv("OpenM_LM_STUDIO_BASE_URL", "http://localhost:1234")

# Other settings
ALLOWED_ORIGINS = ["*"]