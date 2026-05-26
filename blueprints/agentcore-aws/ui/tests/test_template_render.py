"""Smoke tests for Jinja templates — render each with a fixture payload."""
from __future__ import annotations

from pathlib import Path
import pytest
from jinja2 import Environment, FileSystemLoader, select_autoescape

TEMPLATE_DIR = Path(__file__).resolve().parents[1] / "templates"


@pytest.fixture()
def env() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(TEMPLATE_DIR)),
        autoescape=select_autoescape(["html"]),
    )


def test_base_template_renders(env):
    tmpl = env.get_template("base.html")
    out = tmpl.render(
        page_title="Test",
        scenarios=[],
        active_scenario_id=None,
        active_nav="scenarios",
        status={"region": "us-east-2", "runtime": "test-runtime", "data_plane": "10.50.20.110",
                "dcf_rules": "-100-", "controller_version": "9.0.10"},
        containment="on",
        body_content="<p>body</p>",
    )
    assert "AI ATTACK SIMULATION" in out
    assert "us-east-2" in out
    assert "<p>body</p>" in out


def test_flow_partial_renders_step_types(env):
    tmpl = env.get_template("partials/flow.html")
    out = tmpl.render(steps=[
        {"label": "Attacker prompt", "outcome": "info", "detail": "x"},
        {"label": "Tool", "outcome": "ok", "detail": "y"},
        {"label": "Aviatrix Gateway", "outcome": "permitted", "detail": "rule -100-"},
        {"label": "Egress", "outcome": "blocked", "detail": "z"},
    ])
    assert "Attacker prompt" in out
    assert "Aviatrix Gateway" in out
    assert "node info" in out  # info-class node present
    assert "node ok" in out


def test_rule_block_dcf(env):
    tmpl = env.get_template("partials/rule_block.html")
    rule = {
        "type": "dcf", "name": "test-rule", "priority": 100, "action": "DENY",
        "protocol": "ANY",
        "src_smart_groups": ["runtime-subnet"],
        "dst_smart_groups": ["any"],
        "decrypt_policy": None, "logging": True, "watch": False,
    }
    out = tmpl.render(rule=rule)
    assert "test-rule" in out
    assert "DENY" in out
    assert "DCF" in out


def test_rule_block_iam(env):
    tmpl = env.get_template("partials/rule_block.html")
    rule = {
        "type": "iam", "name": "vpc-mode-guardrail", "effect": "DENY",
        "action": "bedrock-agentcore-control:CreateAgentRuntime",
        "resource": "arn:…", "condition": "Null on subnets",
        "attached_to": "platform-eng",
    }
    out = tmpl.render(rule=rule)
    assert "vpc-mode-guardrail" in out
    assert "IAM" in out
    assert "CreateAgentRuntime" in out


def test_evidence_partial(env):
    tmpl = env.get_template("partials/evidence.html")
    out = tmpl.render(evidence={
        "match_attribute": "destination SNI evil.attacker.example",
        "matched_group": "dst = any (default-deny fallback)",
        "enforcement_point": "AgentCore spoke GW (L4 stateful)",
        "decryption": "not required",
        "termination": "TLS handshake closed pre-egress",
        "audit": "FlowIQ entry: action=DENY",
    })
    assert "Control evidence" in out
    assert "evil.attacker.example" in out
