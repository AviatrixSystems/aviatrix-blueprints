"""Tests for the runtime_client wrapper."""
from __future__ import annotations

import io
import json
import os

import boto3
import pytest
from botocore.stub import Stubber


@pytest.fixture()
def stubbed_client(monkeypatch):
    monkeypatch.setenv("AWS_REGION", "us-east-2")
    monkeypatch.setenv("AGENTCORE_RUNTIME_ARN",
                       "arn:aws:bedrock-agentcore:us-east-2:123456789012:runtime/test-runtime")
    from ui import runtime_client
    # Replace the module-level client with a stubbed one
    real = boto3.client("bedrock-agentcore", region_name="us-east-2")
    runtime_client._client = real
    return real


def test_invoke_round_trip(stubbed_client):
    """Stubber asserts the call shape; we don't assert the session id since
    it's time + random and would require freezing both. The boto3 Stubber's
    default behavior (no expected_params) accepts any kwargs."""
    from ui.runtime_client import invoke
    with Stubber(stubbed_client) as stubber:
        body = io.BytesIO(json.dumps({"ok": True, "steps": []}).encode())
        stubber.add_response(
            "invoke_agent_runtime",
            {"response": body, "contentType": "application/json", "statusCode": 200},
        )
        result, elapsed = invoke({"mode": "scenario", "scenario": "llm01_prompt_inject_exfil"})
    assert result["ok"] is True
    assert "steps" in result
    assert elapsed >= 0


def test_invoke_returns_error_dict_when_runtime_arn_unset(monkeypatch):
    monkeypatch.delenv("AGENTCORE_RUNTIME_ARN", raising=False)
    from ui import runtime_client
    runtime_client._client = None  # force fresh init
    result, elapsed = runtime_client.invoke({"mode": "scenario", "scenario": "x"})
    assert result["ok"] is False
    assert "AGENTCORE_RUNTIME_ARN" in result["error"]
