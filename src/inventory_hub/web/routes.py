"""Server-rendered UI (Jinja2). Uses the same service layer as the API."""

from __future__ import annotations

from flask import current_app, flash, redirect, render_template, request, url_for

from inventory_hub.services import inventory_service as svc
from inventory_hub.services.inventory_service import ConflictError
from inventory_hub.services.validation import ValidationError
from inventory_hub.web import web_bp


@web_bp.get("/")
def dashboard():
    summary = svc.inventory_summary(current_app.config["LOW_STOCK_THRESHOLD"])
    return render_template("dashboard.html", summary=summary)


@web_bp.get("/products")
def products():
    page = svc.list_products(
        search=request.args.get("q"),
        category_id=request.args.get("category_id", type=int),
        page=request.args.get("page", 1, type=int),
        per_page=current_app.config["ITEMS_PER_PAGE"],
    )
    return render_template(
        "products/list.html",
        page=page,
        categories=svc.list_categories(),
        q=request.args.get("q", ""),
        category_id=request.args.get("category_id", type=int),
        threshold=current_app.config["LOW_STOCK_THRESHOLD"],
    )


@web_bp.route("/products/new", methods=["GET", "POST"])
def new_product():
    errors, form = {}, {}
    if request.method == "POST":
        form = request.form.to_dict()
        try:
            product = svc.create_product(form)
            flash(f"Product {product.sku} created.", "success")
            return redirect(url_for("web.products"))
        except ValidationError as err:
            errors = err.errors
        except ConflictError as err:
            errors = {"sku": str(err)}
    return render_template(
        "products/form.html",
        form=form,
        errors=errors,
        categories=svc.list_categories(),
        mode="create",
    )


@web_bp.route("/products/<int:product_id>/edit", methods=["GET", "POST"])
def edit_product(product_id: int):
    product = svc.get_product(product_id)
    errors = {}
    form = {**product.to_dict(), "category_id": product.category_id or ""}
    if request.method == "POST":
        form = request.form.to_dict()
        try:
            svc.update_product(product_id, form)
            flash(f"Product {product.sku} updated.", "success")
            return redirect(url_for("web.products"))
        except ValidationError as err:
            errors = err.errors
        except ConflictError as err:
            errors = {"sku": str(err)}
    return render_template(
        "products/form.html",
        form=form,
        errors=errors,
        product=product,
        categories=svc.list_categories(),
        mode="edit",
    )


@web_bp.post("/products/<int:product_id>/delete")
def delete_product(product_id: int):
    product = svc.get_product(product_id)
    svc.delete_product(product_id)
    flash(f"Product {product.sku} deleted.", "info")
    return redirect(url_for("web.products"))


@web_bp.route("/categories", methods=["GET", "POST"])
def categories():
    errors, form = {}, {}
    if request.method == "POST":
        form = request.form.to_dict()
        try:
            category = svc.create_category(form)
            flash(f"Category '{category.name}' added.", "success")
            return redirect(url_for("web.categories"))
        except ValidationError as err:
            errors = err.errors
        except ConflictError as err:
            errors = {"name": str(err)}
    return render_template(
        "categories.html", categories=svc.list_categories(), errors=errors, form=form
    )
