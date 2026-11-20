def test_create_and_get_product(client, category):
    resp = client.post(
        "/api/v1/products",
        json={
            "sku": "STG-SSD-2T",
            "name": "NVMe SSD",
            "price": "13999",
            "quantity": 10,
            "category_id": category.id,
        },
    )
    assert resp.status_code == 201
    body = resp.get_json()
    assert body["sku"] == "STG-SSD-2T"
    assert body["category"] == "Networking"

    resp = client.get(f"/api/v1/products/{body['id']}")
    assert resp.status_code == 200
    assert resp.get_json()["price"] == "13999.00"


def test_duplicate_sku_returns_409(client, product):
    resp = client.post(
        "/api/v1/products",
        json={"sku": product.sku, "name": "Dup", "price": 1, "quantity": 1},
    )
    assert resp.status_code == 409


def test_validation_error_returns_422(client):
    resp = client.post("/api/v1/products", json={"sku": "x"})
    assert resp.status_code == 422
    assert "name" in resp.get_json()["details"]


def test_list_and_search(client, product):
    resp = client.get("/api/v1/products?q=switch")
    data = resp.get_json()
    assert data["total"] == 1
    assert data["items"][0]["sku"] == product.sku


def test_patch_product(client, product):
    resp = client.patch(f"/api/v1/products/{product.id}", json={"quantity": 50})
    assert resp.status_code == 200
    assert resp.get_json()["quantity"] == 50


def test_stock_adjustment(client, product):
    resp = client.post(f"/api/v1/products/{product.id}/stock", json={"delta": -3})
    assert resp.get_json()["quantity"] == 2

    resp = client.post(f"/api/v1/products/{product.id}/stock", json={"delta": -10})
    assert resp.status_code == 422


def test_delete_product(client, product):
    assert client.delete(f"/api/v1/products/{product.id}").status_code == 204
    assert client.get(f"/api/v1/products/{product.id}").status_code == 404


def test_summary(client, product):
    data = client.get("/api/v1/summary").get_json()
    assert data["total_products"] == 1
    assert data["low_stock"][0]["sku"] == product.sku


def test_categories(client):
    assert client.post("/api/v1/categories", json={"name": "Storage"}).status_code == 201
    assert client.get("/api/v1/categories").get_json()["items"][0]["name"] == "Storage"


def test_unknown_api_route_returns_json_404(client):
    resp = client.get("/api/v1/nope")
    assert resp.status_code == 404
    assert resp.is_json
