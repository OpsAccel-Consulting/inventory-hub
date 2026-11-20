"""REST API v1.

GET    /api/v1/products              list (q, category_id, page, per_page)
POST   /api/v1/products              create
GET    /api/v1/products/<id>         read
PUT    /api/v1/products/<id>         full update
PATCH  /api/v1/products/<id>         partial update
DELETE /api/v1/products/<id>         delete
POST   /api/v1/products/<id>/stock   adjust stock  {"delta": -3}
GET    /api/v1/categories            list
POST   /api/v1/categories            create
GET    /api/v1/summary               dashboard stats
"""

from __future__ import annotations

from flask import current_app, jsonify, request

from inventory_hub.api import api_bp
from inventory_hub.services import inventory_service as svc
from inventory_hub.services.validation import validate_stock_adjustment


def _json_body() -> dict:
    return request.get_json(silent=True) or {}


@api_bp.get("/products")
def list_products():
    per_page = min(request.args.get("per_page", 20, type=int), 100)
    page_obj = svc.list_products(
        search=request.args.get("q"),
        category_id=request.args.get("category_id", type=int),
        page=request.args.get("page", 1, type=int),
        per_page=per_page,
    )
    return jsonify(
        items=[p.to_dict() for p in page_obj.items],
        page=page_obj.page,
        per_page=page_obj.per_page,
        total=page_obj.total,
        pages=page_obj.pages,
    )


@api_bp.post("/products")
def create_product():
    product = svc.create_product(_json_body())
    return jsonify(product.to_dict()), 201, {"Location": f"/api/v1/products/{product.id}"}


@api_bp.get("/products/<int:product_id>")
def get_product(product_id: int):
    return jsonify(svc.get_product(product_id).to_dict())


@api_bp.put("/products/<int:product_id>")
def replace_product(product_id: int):
    return jsonify(svc.update_product(product_id, _json_body()).to_dict())


@api_bp.patch("/products/<int:product_id>")
def patch_product(product_id: int):
    return jsonify(svc.update_product(product_id, _json_body(), partial=True).to_dict())


@api_bp.delete("/products/<int:product_id>")
def delete_product(product_id: int):
    svc.delete_product(product_id)
    return "", 204


@api_bp.post("/products/<int:product_id>/stock")
def adjust_stock(product_id: int):
    delta = validate_stock_adjustment(_json_body())
    return jsonify(svc.adjust_stock(product_id, delta).to_dict())


@api_bp.get("/categories")
def list_categories():
    return jsonify(items=[c.to_dict() for c in svc.list_categories()])


@api_bp.post("/categories")
def create_category():
    return jsonify(svc.create_category(_json_body()).to_dict()), 201


@api_bp.get("/summary")
def summary():
    return jsonify(svc.inventory_summary(current_app.config["LOW_STOCK_THRESHOLD"]))
