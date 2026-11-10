"""Input validation for product/category payloads (shared by API and UI)."""

from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation

SKU_PATTERN = re.compile(r"^[A-Z0-9][A-Z0-9-]{2,39}$")


class ValidationError(Exception):
    def __init__(self, errors: dict[str, str]):
        super().__init__("validation failed")
        self.errors = errors


def validate_product(data: dict, partial: bool = False) -> dict:
    """Return a cleaned dict or raise ValidationError."""
    errors: dict[str, str] = {}
    cleaned: dict = {}

    def required(field: str) -> bool:
        return not partial or field in data

    if required("sku"):
        sku = str(data.get("sku", "")).strip().upper()
        if not SKU_PATTERN.match(sku):
            errors["sku"] = "SKU must be 3-40 chars: A-Z, 0-9 and hyphens."
        cleaned["sku"] = sku

    if required("name"):
        name = str(data.get("name", "")).strip()
        if not 1 <= len(name) <= 120:
            errors["name"] = "Name is required (max 120 chars)."
        cleaned["name"] = name

    if "description" in data:
        cleaned["description"] = (str(data.get("description") or "").strip()) or None

    if required("price"):
        try:
            price = Decimal(str(data.get("price", "")))
            if price < 0 or price > Decimal("99999999.99"):
                raise InvalidOperation
            cleaned["price"] = price.quantize(Decimal("0.01"))
        except (InvalidOperation, ValueError):
            errors["price"] = "Price must be a non-negative number."

    if required("quantity"):
        try:
            qty = int(data.get("quantity", ""))
            if qty < 0:
                raise ValueError
            cleaned["quantity"] = qty
        except (TypeError, ValueError):
            errors["quantity"] = "Quantity must be a non-negative integer."

    if "category_id" in data:
        raw = data.get("category_id")
        if raw in (None, "", "none"):
            cleaned["category_id"] = None
        else:
            try:
                cleaned["category_id"] = int(raw)
            except (TypeError, ValueError):
                errors["category_id"] = "Invalid category."

    if errors:
        raise ValidationError(errors)
    return cleaned


def validate_category(data: dict) -> dict:
    name = str(data.get("name", "")).strip()
    if not 1 <= len(name) <= 80:
        raise ValidationError({"name": "Name is required (max 80 chars)."})
    return {"name": name, "description": (str(data.get("description") or "").strip()) or None}


def validate_stock_adjustment(data: dict) -> int:
    try:
        delta = int(data.get("delta"))
    except (TypeError, ValueError) as exc:
        raise ValidationError({"delta": "delta must be an integer."}) from exc
    if delta == 0:
        raise ValidationError({"delta": "delta must not be zero."})
    return delta
