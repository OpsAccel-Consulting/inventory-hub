"""Custom Flask CLI commands: ``flask seed`` loads demo data."""

from __future__ import annotations

from decimal import Decimal

import click
from flask import Flask

from inventory_hub.extensions import db
from inventory_hub.models import Category, Product

DEMO_CATEGORIES = [
    ("Networking", "Switches, routers and cabling"),
    ("Compute", "Servers and workstations"),
    ("Storage", "Disks, SSDs and NAS"),
    ("Peripherals", "Keyboards, monitors and accessories"),
]

DEMO_PRODUCTS = [
    ("NET-SW-24P", "24-port Gigabit Switch", "Networking", "18999.00", 14),
    ("NET-RTR-AX6", "Wi-Fi 6 Router", "Networking", "8499.00", 6),
    ("NET-CAT6-305", "Cat6 Cable Box 305m", "Networking", "7250.00", 22),
    ("CMP-SRV-R1", "1U Rack Server 32GB", "Compute", "245000.00", 3),
    ("CMP-WS-I7", "Developer Workstation i7", "Compute", "118500.00", 9),
    ("STG-SSD-2T", "NVMe SSD 2TB", "Storage", "13999.00", 41),
    ("STG-NAS-4B", "4-bay NAS Enclosure", "Storage", "38900.00", 4),
    ("PER-MON-27", "27-inch 4K Monitor", "Peripherals", "27999.00", 17),
    ("PER-KB-MECH", "Mechanical Keyboard", "Peripherals", "5499.00", 2),
]


def register_cli(app: Flask) -> None:
    @app.cli.command("seed")
    @click.option("--force", is_flag=True, help="Seed even if data already exists.")
    def seed(force: bool) -> None:
        """Load demo categories and products (idempotent)."""
        if Product.query.first() and not force:
            click.echo("Data already present - skipping (use --force to override).")
            return

        categories = {}
        for name, desc in DEMO_CATEGORIES:
            cat = Category.query.filter_by(name=name).first() or Category(
                name=name, description=desc
            )
            db.session.add(cat)
            categories[name] = cat
        db.session.flush()

        for sku, name, cat_name, price, qty in DEMO_PRODUCTS:
            if Product.query.filter_by(sku=sku).first():
                continue
            db.session.add(
                Product(
                    sku=sku,
                    name=name,
                    category=categories[cat_name],
                    price=Decimal(price),
                    quantity=qty,
                )
            )
        db.session.commit()
        click.echo(f"Seeded {len(DEMO_CATEGORIES)} categories and {len(DEMO_PRODUCTS)} products.")
