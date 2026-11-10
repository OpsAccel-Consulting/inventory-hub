"""Central error handling: JSON for /api/*, HTML pages for the UI."""

from __future__ import annotations

from flask import Flask, jsonify, render_template, request
from werkzeug.exceptions import HTTPException

from inventory_hub.services.inventory_service import ConflictError, NotFoundError
from inventory_hub.services.validation import ValidationError


def _wants_json() -> bool:
    return request.path.startswith("/api/")


def register_error_handlers(app: Flask) -> None:
    @app.errorhandler(ValidationError)
    def handle_validation(err: ValidationError):
        if _wants_json():
            return jsonify(error="validation_error", details=err.errors), 422
        return render_template("errors/error.html", code=422, message="Invalid input"), 422

    @app.errorhandler(NotFoundError)
    def handle_not_found(err: NotFoundError):
        if _wants_json():
            return jsonify(error="not_found", message=str(err)), 404
        return render_template("errors/error.html", code=404, message=str(err)), 404

    @app.errorhandler(ConflictError)
    def handle_conflict(err: ConflictError):
        if _wants_json():
            return jsonify(error="conflict", message=str(err)), 409
        return render_template("errors/error.html", code=409, message=str(err)), 409

    @app.errorhandler(HTTPException)
    def handle_http(err: HTTPException):
        if _wants_json():
            return jsonify(
                error=err.name.lower().replace(" ", "_"), message=err.description
            ), err.code
        return render_template("errors/error.html", code=err.code, message=err.name), err.code

    @app.errorhandler(Exception)
    def handle_unexpected(err: Exception):
        app.logger.exception("unhandled exception")
        if _wants_json():
            return jsonify(error="internal_error", message="An unexpected error occurred"), 500
        return render_template("errors/error.html", code=500, message="Something went wrong"), 500
