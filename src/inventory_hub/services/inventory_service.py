"""Business logic layer. Routes stay thin; all DB work happens here."""

from __future__ import annotations

from sqlalchemy import func, or_
from sqlalchemy.exc import IntegrityError

from inventory_hub.extensions import db
from inventory_hub.models import Category, Product
from inventory_hub.services.validation import (
    ValidationError,
    validate_category,
    validate_product,
)


class NotFoundError(Exception):
    pass


class ConflictError(Exception):
    pass


# ---------- Products ----------


def list_products(
    search: str | None = None, category_id: int | None = None, page: int = 1, per_page: int = 20
):
    query = Product.query
    if search:
        like = f"%{search}%"
        query = query.filter(or_(Product.name.ilike(like), Product.sku.ilike(like)))
    if category_id:
        query = query.filter(Product.category_id == category_id)
    return query.order_by(Product.updated_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )


def get_product(product_id: int) -> Product:
    product = db.session.get(Product, product_id)
    if product is None:
        raise NotFoundError(f"Product {product_id} not found")
    return product


def _check_category(category_id: int | None) -> None:
    if category_id is not None and db.session.get(Category, category_id) is None:
        raise ValidationError({"category_id": "Category does not exist."})


def create_product(data: dict) -> Product:
    cleaned = validate_product(data)
    _check_category(cleaned.get("category_id"))
    product = Product(**cleaned)
    db.session.add(product)
    _commit(f"SKU '{cleaned['sku']}' already exists")
    return product


def update_product(product_id: int, data: dict, partial: bool = False) -> Product:
    product = get_product(product_id)
    cleaned = validate_product(data, partial=partial)
    if "category_id" in cleaned:
        _check_category(cleaned["category_id"])
    for key, value in cleaned.items():
        setattr(product, key, value)
    _commit(f"SKU '{cleaned.get('sku')}' already exists")
    return product


def adjust_stock(product_id: int, delta: int) -> Product:
    product = get_product(product_id)
    if product.quantity + delta < 0:
        raise ValidationError({"delta": f"Insufficient stock (available: {product.quantity})."})
    product.quantity += delta
    db.session.commit()
    return product


def delete_product(product_id: int) -> None:
    product = get_product(product_id)
    db.session.delete(product)
    db.session.commit()


# ---------- Categories ----------


def list_categories() -> list[Category]:
    return Category.query.order_by(Category.name).all()


def create_category(data: dict) -> Category:
    cleaned = validate_category(data)
    category = Category(**cleaned)
    db.session.add(category)
    _commit(f"Category '{cleaned['name']}' already exists")
    return category


# ---------- Dashboard ----------


def inventory_summary(low_stock_threshold: int) -> dict:
    total_products = db.session.query(func.count(Product.id)).scalar() or 0
    total_units = db.session.query(func.coalesce(func.sum(Product.quantity), 0)).scalar()
    total_value = db.session.query(
        func.coalesce(func.sum(Product.price * Product.quantity), 0)
    ).scalar()
    low_stock = (
        Product.query.filter(Product.quantity <= low_stock_threshold)
        .order_by(Product.quantity.asc())
        .limit(10)
        .all()
    )
    return {
        "total_products": int(total_products),
        "total_units": int(total_units or 0),
        "total_value": f"{float(total_value or 0):.2f}",
        "low_stock_threshold": low_stock_threshold,
        "low_stock": [p.to_dict() for p in low_stock],
        "category_count": db.session.query(func.count(Category.id)).scalar() or 0,
    }


def _commit(conflict_message: str) -> None:
    try:
        db.session.commit()
    except IntegrityError as exc:
        db.session.rollback()
        raise ConflictError(conflict_message) from exc
