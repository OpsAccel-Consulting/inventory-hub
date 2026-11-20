"""AWS Secrets Manager helper.

The RDS instance is created with ``manage_master_user_password = true`` so AWS
owns and rotates the password. The secret JSON contains ``username`` and
``password``; host/port/db name are passed as plain config.
"""

from __future__ import annotations

import json
from functools import lru_cache


@lru_cache(maxsize=8)
def get_secret_json(secret_arn: str, region: str | None = None) -> dict:
    import boto3  # imported lazily so local dev/tests don't need AWS

    client = boto3.client("secretsmanager", region_name=region)
    response = client.get_secret_value(SecretId=secret_arn)
    return json.loads(response["SecretString"])


def get_db_credentials(secret_arn: str, region: str | None = None) -> dict:
    secret = get_secret_json(secret_arn, region)
    return {"username": secret["username"], "password": secret["password"]}
