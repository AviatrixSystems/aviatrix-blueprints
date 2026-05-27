"""Augment runtime payloads with rule_definition, control_evidence, and the
synthetic enforcement node between the last permitted step and the first
blocked step. The verdict is always 100% driven by the agent's actual
outcome (`ok`); there is no simulation path."""
from __future__ import annotations

from typing import Any

from ui.rules_catalog import load_catalog


def augment(payload: dict[str, Any], elapsed: float) -> dict[str, Any]:
    rule_name = payload.get("dcf_rule")
    catalog = load_catalog()
    rule = catalog.get(rule_name)

    steps: list[dict[str, Any]] = list(payload.get("steps") or [])
    contained = bool(payload.get("ok"))

    # The enforcement node, rule block, and control evidence only render
    # when DCF/IAM actually fired (the agent reports the egress was
    # blocked). On breach we omit all three: the flow shows the unbroken
    # egress to the sink, and the sink panel + BREACH verdict carry the
    # story.
    if contained:
        steps = _insert_enforcement_node(steps, rule)

    payload["steps"] = steps
    payload["elapsed_seconds"] = elapsed
    if contained and rule:
        payload["rule_definition"] = rule
        payload["control_evidence"] = _build_evidence(payload, rule)
    else:
        payload["rule_definition"] = None
        payload["control_evidence"] = None
    payload["verdict"] = "CONTAINED" if contained else "BREACH"
    return payload


def _insert_enforcement_node(steps: list[dict[str, Any]], rule: dict[str, Any] | None) -> list[dict[str, Any]]:
    block_idx = next((i for i, s in enumerate(steps) if s.get("outcome") in ("blocked", "CONTAINMENT FAILED")), None)
    if block_idx is None or rule is None:
        return steps

    if rule.get("type") == "iam":
        node = {
            "label": "IAM guardrail policy",
            "outcome": "permitted",
            "detail": rule["name"],
        }
    else:
        node = {
            "label": "Aviatrix Gateway",
            "outcome": "permitted",
            "detail": f"policy {rule['name']} · action {rule.get('action', 'DENY')}",
        }
    return steps[:block_idx] + [node] + steps[block_idx:]


def _build_evidence(payload: dict[str, Any], rule: dict[str, Any] | None) -> dict[str, str]:
    if not rule:
        return {}
    if rule.get("type") == "iam":
        return {
            "match_attribute": "request param networkMode=PUBLIC",
            "matched_statement": "guardrail Statement 1 (Null condition true)",
            "enforcement_point": "AWS IAM — before service handler executes",
            "error_returned": "AccessDeniedException · HTTP 403",
            "side_effects": "none — no AgentCore resource created",
            "audit": "CloudTrail entry: errorCode=AccessDenied, eventName=CreateAgentRuntime",
        }
    return {
        "match_attribute": _summarize_match(payload),
        "matched_group": f"dst = {rule['dst_smart_groups'][0]}",
        "enforcement_point": "AgentCore spoke GW (L4 stateful)",
        "decryption": rule.get("decrypt_policy") or "not required for this rule",
        "termination": "TLS/L4 closed pre-egress (no bytes left VPC)",
        "audit": f"FlowIQ entry: action={rule.get('action', 'DENY')}, rule={rule['name']}",
    }


def _summarize_match(payload: dict[str, Any]) -> str:
    last = next((s for s in reversed(payload.get("steps", [])) if s.get("outcome") in ("blocked", "CONTAINMENT FAILED")), None)
    if not last:
        return "(unavailable)"
    return last.get("label", "(unavailable)")
