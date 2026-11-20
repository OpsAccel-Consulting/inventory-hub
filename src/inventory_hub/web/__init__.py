from flask import Blueprint

web_bp = Blueprint("web", __name__)

from inventory_hub.web import routes  # noqa: E402,F401
