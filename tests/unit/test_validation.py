from decimal import Decimal

import pytest

from inventory_hub.services.validation import (
    ValidationError,
    validate_product,
    validate_stock_adjustment,
)


def test_valid_product_is_cleaned():
    data = validate_product(
        {"sku": "abc-123", "name": " Widget ", "price": "10.5", "quantity": "3"}
    )
    assert data == {"sku": "ABC-123", "name": "Widget", "price": Decimal("10.50"), "quantity": 3}


@pytest.mark.parametrize(
    "payload,field",
    [
        ({"sku": "a", "name": "x", "price": 1, "quantity": 1}, "sku"),
        ({"sku": "ABC", "name": "", "price": 1, "quantity": 1}, "name"),
        ({"sku": "ABC", "name": "x", "price": -1, "quantity": 1}, "price"),
        ({"sku": "ABC", "name": "x", "price": 1, "quantity": -2}, "quantity"),
        ({"sku": "ABC", "name": "x", "price": "abc", "quantity": 1}, "price"),
    ],
)
def test_invalid_product_fields(payload, field):
    with pytest.raises(ValidationError) as exc:
        validate_product(payload)
    assert field in exc.value.errors


def test_partial_validation_only_checks_supplied_fields():
    assert validate_product({"quantity": 7}, partial=True) == {"quantity": 7}


def test_stock_adjustment_rejects_zero():
    with pytest.raises(ValidationError):
        validate_stock_adjustment({"delta": 0})
