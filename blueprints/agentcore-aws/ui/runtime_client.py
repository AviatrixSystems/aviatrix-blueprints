"""boto3 wrapper around bedrock-agentcore:InvokeAgentRuntime.

Returns (result_dict, elapsed_seconds). On AWS errors or missing
configuration, returns a dict with ok=False and a short error string —
never raises out of the boundary.
"""
from __future__ import annotations

import json
import os
import secrets
import time
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

_client: Any = None


def _get_client() -> Any:
    global _client
    if _client is None:
        region = os.environ.get("AWS_REGION", "us-east-2")
        _client = boto3.client(
            "bedrock-agentcore",
            region_name=region,
            config=Config(connect_timeout=10, read_timeout=180,
                          retries={"max_attempts": 1}),
        )
    return _client


def invoke(payload: dict[str, Any]) -> tuple[dict[str, Any], float]:
    arn = os.environ.get("AGENTCORE_RUNTIME_ARN", "")
    if not arn or arn.startswith("UNSET"):
        return ({"ok": False, "error": "AGENTCORE_RUNTIME_ARN not configured"}, 0.0)

    sid = f"ui-{int(time.time())}-{secrets.token_hex(16)}"
    start = time.perf_counter()
    try:
        resp = _get_client().invoke_agent_runtime(
            agentRuntimeArn=arn,
            runtimeSessionId=sid,
            payload=json.dumps(payload).encode(),
        )
        raw = resp["response"].read()
        result = json.loads(raw) if raw else {"ok": False, "error": "empty runtime response"}
    except (BotoCoreError, ClientError) as e:
        result = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    except json.JSONDecodeError as e:
        result = {"ok": False, "error": f"runtime returned non-JSON: {e}"}
    return (result, time.perf_counter() - start)
