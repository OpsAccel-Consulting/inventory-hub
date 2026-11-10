"""Gunicorn settings - tuned for a container with ~0.5 vCPU."""

import os

bind = f"0.0.0.0:{os.getenv('PORT', '8000')}"
workers = int(os.getenv("GUNICORN_WORKERS", "2"))
threads = int(os.getenv("GUNICORN_THREADS", "4"))
worker_class = "gthread"
timeout = 30
graceful_timeout = 25          # < terminationGracePeriodSeconds in the Deployment
keepalive = 65                 # > ALB idle timeout (60s) to avoid 502s
accesslog = None               # the app emits structured request logs itself
errorlog = "-"
loglevel = os.getenv("LOG_LEVEL", "info").lower()
forwarded_allow_ips = "*"      # trust X-Forwarded-* from the ALB
