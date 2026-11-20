def test_healthz(client):
    assert client.get("/healthz").get_json() == {"status": "ok"}


def test_readyz(client):
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.get_json()["database"] == "ok"


def test_version(client):
    assert "version" in client.get("/version").get_json()


def test_dashboard_renders(client, product):
    resp = client.get("/")
    assert resp.status_code == 200
    assert b"Low stock" in resp.data
    assert product.sku.encode() in resp.data


def test_create_product_via_form(client, category):
    resp = client.post(
        "/products/new",
        data={
            "sku": "PER-KB-1",
            "name": "Keyboard",
            "price": "999",
            "quantity": "4",
            "category_id": str(category.id),
        },
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"PER-KB-1" in resp.data


def test_form_shows_validation_errors(client):
    resp = client.post("/products/new", data={"sku": "", "name": ""})
    assert resp.status_code == 200
    assert b"SKU must be" in resp.data


def test_edit_and_delete_via_ui(client, product):
    resp = client.post(
        f"/products/{product.id}/edit",
        data={
            "sku": product.sku,
            "name": "Renamed",
            "price": "1",
            "quantity": "1",
            "category_id": "",
        },
        follow_redirects=True,
    )
    assert b"Renamed" in resp.data
    resp = client.post(f"/products/{product.id}/delete", follow_redirects=True)
    assert b"deleted" in resp.data


def test_404_page(client):
    assert client.get("/does-not-exist").status_code == 404


def test_request_id_header(client):
    resp = client.get("/", headers={"X-Request-ID": "abc-123"})
    assert resp.headers["X-Request-ID"] == "abc-123"
