"""Smoke tests for FastAPI routes."""
from __future__ import annotations


def test_healthz_returns_200(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "healthy"}


def test_static_assets_served(client):
    for asset in ["/static/tokens.css", "/static/sora.css", "/static/htmx.min.js", "/static/aviatrix.svg"]:
        r = client.get(asset)
        assert r.status_code == 200, f"{asset} returned {r.status_code}"
