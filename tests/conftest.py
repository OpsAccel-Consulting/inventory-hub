import pytest

from inventory_hub import create_app
from inventory_hub.extensions import db as _db
from inventory_hub.models import Category, Product


@pytest.fixture()
def app():
    app = create_app("testing")
    with app.app_context():
        _db.create_all()
        yield app
        _db.session.remove()
        _db.drop_all()


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def category(app):
    cat = Category(name="Networking", description="Network gear")
    _db.session.add(cat)
    _db.session.commit()
    return cat


@pytest.fixture()
def product(app, category):
    p = Product(
        sku="NET-SW-24P", name="24-port Switch", price="18999.00", quantity=5, category=category
    )
    _db.session.add(p)
    _db.session.commit()
    return p
