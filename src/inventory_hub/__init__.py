"""InventoryHub - a sample inventory management service.

Application factory pattern: ``create_app()`` builds and wires a Flask app
for the requested configuration (development, testing, production).
"""

from __future__ import annotations

import os

from flask import Flask

from inventory_hub.config import get_config
from inventory_hub.extensions import db, migrate
from inventory_hub.utils.logging import configure_logging

__version__ = "1.0.0"


def create_app(config_name: str | None = None) -> Flask:
    """Create and configure the Flask application."""
    app = Flask(__name__)

    config_name = config_name or os.getenv("APP_ENV", "development")
    app.config.from_object(get_config(config_name))
    app.config["APP_VERSION"] = os.getenv("APP_VERSION", __version__)

    configure_logging(app)

    # Extensions
    db.init_app(app)
    migrate.init_app(app, db, directory=app.config["MIGRATIONS_DIR"])

    # Blueprints
    from inventory_hub.api import api_bp
    from inventory_hub.health import health_bp
    from inventory_hub.web import web_bp

    app.register_blueprint(health_bp)
    app.register_blueprint(api_bp, url_prefix="/api/v1")
    app.register_blueprint(web_bp)

    from inventory_hub.errors import register_error_handlers

    register_error_handlers(app)

    from inventory_hub.cli import register_cli

    register_cli(app)

    app.logger.info(
        "application started",
        extra={"env": config_name, "version": app.config["APP_VERSION"]},
    )
    return app
