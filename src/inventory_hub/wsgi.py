"""WSGI entrypoint for gunicorn: ``gunicorn inventory_hub.wsgi:app``."""

from inventory_hub import create_app

app = create_app()
