"""Drift scenario handler. Calls bedrock-agentcore-control:CreateAgentRuntime
with networkMode=PUBLIC and expects AccessDeniedException from the IAM guardrail."""
from __future__ import annotations

import os
import time
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

_client: Any = None


def _get_client() -> Any:
    global _client
    if _client is None:
        region = os.environ.get("AWS_REGION", "us-east-2")
        _client = boto3.client(
            "bedrock-agentcore-control",
            region_name=region,
            config=Config(connect_timeout=5, read_timeout=30),
        )
    return _client


def attempt_public_runtime_create() -> tuple[dict[str, Any], float]:
    role_arn = os.environ.get("AGENTCORE_RUNTIME_ROLE_ARN", "")
    image_uri = os.environ.get("AGENTCORE_AGENT_IMAGE_URI", "")
    name = f"drift_demo_{int(time.time())}"
    start = time.perf_counter()
    try:
        _get_client().create_agent_runtime(
            agentRuntimeName=name,
            agentRuntimeArtifact={"containerConfiguration": {"containerUri": image_uri}},
            roleArn=role_arn,
            networkConfiguration={"networkMode": "PUBLIC"},
            protocolConfiguration={"serverProtocol": "HTTP"},
        )
        elapsed = time.perf_counter() - start
        return ({
            "ok": False,  # BREACH — runtime was created
            "title": "Drift — PUBLIC Mode Runtime Created (BREACH)",
            "dcf_rule": "agentcore-vca-vpc-mode-guardrail",
            "steps": [
                {"label": "CreateAgentRuntime request", "outcome": "info",
                 "detail": f"networkMode=PUBLIC, name={name}"},
                {"label": "IAM guardrail evaluation", "outcome": "ok",
                 "detail": "request permitted (BREACH)"},
                {"label": "PUBLIC-mode runtime provisioned", "outcome": "ok",
                 "detail": "runtime exists outside DCF visibility"},
            ],
        }, elapsed)
    except ClientError as e:
        elapsed = time.perf_counter() - start
        code = e.response.get("Error", {}).get("Code", "")
        contained = code in ("AccessDeniedException", "AccessDenied", "UnauthorizedOperation")
        return ({
            "ok": contained,
            "title": "Drift — Create Runtime in PUBLIC Mode",
            "dcf_rule": "agentcore-vca-vpc-mode-guardrail",
            "steps": [
                {"label": "CreateAgentRuntime request", "outcome": "info",
                 "detail": f"networkMode=PUBLIC, name={name}"},
                {"label": "IAM guardrail policy", "outcome": "permitted",
                 "detail": "agentcore-vca-vpc-mode-guardrail · effect=DENY"},
                {"label": "PUBLIC-mode runtime", "outcome": "blocked",
                 "detail": f"{code}: {str(e)[:200]}"},
            ],
        }, elapsed)
