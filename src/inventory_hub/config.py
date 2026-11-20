"""Configuration classes.

Database credentials are resolved in this order:
  1. DATABASE_URL (local development / tests)
  2. DB_SECRET_ARN + DB_HOST + DB_NAME (AWS: password pulled from Secrets Manager
     at startup using the pod's EKS Pod Identity role - no secrets in env vars
     or Kubernetes manifests)

The Flask SECRET_KEY follows the same pattern via APP_SECRET_ARN.
"""

from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import quote_plus

from inventory_hub.utils.secrets import get_db_credentials, get_secret_json

BASE_DIR = Path(__file__).resolve().parent.parent.parent


def _build_database_uri() -> str:
    url = os.getenv("DATABASE_URL")
    if url:
        return url

    secret_arn = os.getenv("DB_SECRET_ARN")
    if secret_arn:
        creds = get_db_credentials(secret_arn, region=os.getenv("AWS_REGION"))
        host = os.environ["DB_HOST"]
        port = os.getenv("DB_PORT", "5432")
        name = os.getenv("DB_NAME", "inventory")
        user = quote_plus(creds["username"])
        password = quote_plus(creds["password"])
        return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{name}?sslmode=require"

    return f"sqlite:///{BASE_DIR / 'instance' / 'dev.db'}"


def _resolve_secret_key() -> str:
    """Flask SECRET_KEY from Secrets Manager (AWS) or env var (local)."""
    secret_arn = os.getenv("APP_SECRET_ARN")
    if secret_arn:
        return get_secret_json(secret_arn, region=os.getenv("AWS_REGION"))["secret_key"]
    return os.getenv("SECRET_KEY", "change-me-in-production")


class BaseConfig:
    @property
    def SECRET_KEY(self) -> str:  # noqa: N802 - Flask config key
        return _resolve_secret_key()

    ENV_NAME = os.getenv("ENV_NAME", "local")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True, "pool_recycle": 1800}
    MIGRATIONS_DIR = str(BASE_DIR / "migrations")
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
    LOG_JSON = os.getenv("LOG_JSON", "true").lower() == "true"
    ITEMS_PER_PAGE = int(os.getenv("ITEMS_PER_PAGE", "20"))
    LOW_STOCK_THRESHOLD = int(os.getenv("LOW_STOCK_THRESHOLD", "10"))

    @property
    def SQLALCHEMY_DATABASE_URI(self) -> str:  # noqa: N802 - Flask config key
        return _build_database_uri()


class DevelopmentConfig(BaseConfig):
    DEBUG = True
    LOG_JSON = os.getenv("LOG_JSON", "false").lower() == "true"


class TestingConfig(BaseConfig):
    TESTING = True
    LOG_JSON = False

    @property
    def SQLALCHEMY_DATABASE_URI(self) -> str:  # noqa: N802
        return os.getenv("TEST_DATABASE_URL", "sqlite:///:memory:")


class ProductionConfig(BaseConfig):
    DEBUG = False


_CONFIGS = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig,
}


def get_config(name: str) -> BaseConfig:
    try:
        return _CONFIGS[name]()
    except KeyError as exc:
        raise ValueError(f"Unknown APP_ENV '{name}'") from exc
