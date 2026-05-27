"""Tests for rules_catalog."""
from __future__ import annotations


def test_catalog_contains_all_referenced_rules():
    from ui.rules_catalog import load_catalog
    catalog = load_catalog()
    # Every DCF rule the scenarios reference must be in the catalog.
    expected = {
        "agentcore-vca-29-runtime-deny-supply-chain-ioc-github",
        "agentcore-vca-50-runtime-dns-exfil-deny",
        "agentcore-vca-100-runtime-default-deny",
        "agentcore-vca-vpc-mode-guardrail",
    }
    assert expected.issubset(catalog.keys())


def test_default_deny_rule_shape():
    from ui.rules_catalog import load_catalog
    rule = load_catalog()["agentcore-vca-100-runtime-default-deny"]
    assert rule["type"] == "dcf"
    assert rule["action"] == "DENY"
    assert rule["priority"] == 100
    assert rule["protocol"] == "ANY"
    assert "runtime-subnet" in rule["src_smart_groups"][0]


def test_iam_guardrail_shape():
    from ui.rules_catalog import load_catalog
    rule = load_catalog()["agentcore-vca-vpc-mode-guardrail"]
    assert rule["type"] == "iam"
    assert rule["effect"] == "DENY"
    assert "CreateAgentRuntime" in rule["action"]
