from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal

from inventory_hub.extensions import db


def _utcnow() -> datetime:
    return datetime.now(UTC)


class Product(db.Model):
    __tablename__ = "products"

    id = db.Column(db.Integer, primary_key=True)
    sku = db.Column(db.String(40), unique=True, nullable=False, index=True)
    name = db.Column(db.String(120), nullable=False)
    description = db.Column(db.Text)
    price = db.Column(db.Numeric(10, 2), nullable=False, default=Decimal("0.00"))
    quantity = db.Column(db.Integer, nullable=False, default=0)
    category_id = db.Column(db.Integer, db.ForeignKey("categories.id"), nullable=True)
    created_at = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False)
    updated_at = db.Column(
        db.DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )

    category = db.relationship("Category", back_populates="products")

    __table_args__ = (
        db.CheckConstraint("quantity >= 0", name="ck_products_quantity_non_negative"),
        db.CheckConstraint("price >= 0", name="ck_products_price_non_negative"),
    )

    def is_low_stock(self, threshold: int) -> bool:
        return self.quantity <= threshold

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "sku": self.sku,
            "name": self.name,
            "description": self.description,
            "price": str(self.price),
            "quantity": self.quantity,
            "category": self.category.name if self.category else None,
            "category_id": self.category_id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
