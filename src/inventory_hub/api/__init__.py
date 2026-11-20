from flask import Blueprint

api_bp = Blueprint("api", __name__)

from inventory_hub.api import routes  # noqa: E402,F401
