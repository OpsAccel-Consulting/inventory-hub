"""Structured (JSON) logging so logs are queryable in CloudWatch Logs Insights."""

from __future__ import annotations

import json
import logging
import sys
import time
import uuid

from flask import Flask, g, request

_RESERVED = set(vars(logging.makeLogRecord({})).keys()) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in vars(record).items():
            if key not in _RESERVED and not key.startswith("_"):
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(app: Flask) -> None:
    handler = logging.StreamHandler(sys.stdout)
    if app.config.get("LOG_JSON"):
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s"))

    app.logger.handlers = [handler]
    app.logger.setLevel(app.config.get("LOG_LEVEL", "INFO"))
    app.logger.propagate = False

    @app.before_request
    def _start_timer() -> None:
        g.start_time = time.perf_counter()
        g.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))

    @app.after_request
    def _log_request(response):
        response.headers["X-Request-ID"] = g.get("request_id", "")
        # Skip noisy probe logs
        if request.path not in ("/healthz", "/readyz"):
            duration_ms = round((time.perf_counter() - g.get("start_time", 0)) * 1000, 2)
            app.logger.info(
                "request",
                extra={
                    "request_id": g.get("request_id"),
                    "method": request.method,
                    "path": request.path,
                    "status": response.status_code,
                    "duration_ms": duration_ms,
                    "remote_addr": request.headers.get("X-Forwarded-For", request.remote_addr),
                },
            )
        return response
