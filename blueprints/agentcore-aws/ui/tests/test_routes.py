"""Smoke tests for FastAPI routes."""
from __future__ import annotations


def test_healthz_returns_200(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "healthy"}
