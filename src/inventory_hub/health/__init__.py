"""Kubernetes probes.

/healthz - liveness: process is up (never touches dependencies)
/readyz  - readiness: can serve traffic (database reachable)
/version - build metadata (image tag injected by CI/CD)
"""

from flask import Blueprint, current_app, jsonify
from sqlalchemy import text

from inventory_hub.extensions import db

health_bp = Blueprint("health", __name__)


@health_bp.get("/healthz")
def liveness():
    return jsonify(status="ok")


@health_bp.get("/readyz")
def readiness():
    try:
        db.session.execute(text("SELECT 1"))
        return jsonify(status="ready", database="ok")
    except Exception as exc:  # noqa: BLE001
        current_app.logger.warning("readiness check failed", extra={"error": str(exc)})
        return jsonify(status="not-ready", database="unreachable"), 503


@health_bp.get("/version")
def version():
    return jsonify(
        version=current_app.config["APP_VERSION"],
        environment=current_app.config.get("ENV_NAME", "unknown"),
    )
