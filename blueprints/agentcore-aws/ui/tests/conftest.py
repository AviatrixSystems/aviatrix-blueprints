"""Shared pytest fixtures for the UI test suite."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client():
    # Import inside the fixture so tests can monkeypatch boto3 if needed
    from ui.app import app
    return TestClient(app)
