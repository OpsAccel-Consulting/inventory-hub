"""Runs against a real PostgreSQL (CI provides one as a service container).

TEST_DATABASE_URL=postgresql+psycopg2://app:app@localhost:5432/inventory_test pytest -m integration
"""

import os

import pytest

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        not os.getenv("TEST_DATABASE_URL", "").startswith("postgresql"),
        reason="TEST_DATABASE_URL not pointing at PostgreSQL",
    ),
]


def test_check_constraint_blocks_negative_quantity(app, product):
    from sqlalchemy.exc import IntegrityError

    from inventory_hub.extensions import db

    product.quantity = -1
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


def test_case_insensitive_search(client, product):
    data = client.get("/api/v1/products?q=SWITCH").get_json()
    assert data["total"] == 1
