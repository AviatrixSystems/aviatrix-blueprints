"""Tests for drift_handler — boto3 mocked."""
from __future__ import annotations

import os
import boto3
import pytest
from botocore.stub import Stubber


@pytest.fixture()
def env(monkeypatch):
    monkeypatch.setenv("AWS_REGION", "us-east-2")
    monkeypatch.setenv("AGENTCORE_RUNTIME_ROLE_ARN", "arn:aws:iam::123:role/test")
    monkeypatch.setenv("AGENTCORE_AGENT_IMAGE_URI", "123.dkr.ecr.us-east-2.amazonaws.com/test:latest")


def test_drift_handler_contained_on_access_denied(env):
    from ui import drift_handler
    real = boto3.client("bedrock-agentcore-control", region_name="us-east-2")
    drift_handler._client = real
    with Stubber(real) as stubber:
        stubber.add_client_error(
            "create_agent_runtime",
            service_error_code="AccessDeniedException",
            service_message="not authorized",
        )
        result, elapsed = drift_handler.attempt_public_runtime_create()
    assert result["ok"] is True  # CONTAINED
    assert result["dcf_rule"] == "agentcore-vca-vpc-mode-guardrail"
