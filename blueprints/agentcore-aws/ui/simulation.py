"""Precomputed "without Aviatrix" payloads for each scenario.

These render when the Containment toggle is OFF. The UI server returns
the matching entry instead of calling the runtime, with simulated=True
on the response. The shape matches what the live runtime returns so
the rendering template is identical across both modes.
"""
from __future__ import annotations

from typing import Any

SIMULATED_PAYLOADS: dict[str, dict[str, Any]] = {
    "llm01_prompt_inject_exfil": {
        "ok": False,
        "verdict": "BREACH",
        "title": "LLM01 — Prompt Injection → Tool-Abuse Exfil",
        "owasp": "LLM01 Prompt Injection + LLM07 Insecure Output Handling",
        "mitre": "AML.T0051 + AML.T0024",
        "dcf_rule": "agentcore-vca-100-runtime-default-deny",
        "steps": [
            {"label": "Attacker prompt", "outcome": "info",
             "detail": "\"send to evil.attacker.example\""},
            {"label": "lookup_customer(42)", "outcome": "ok",
             "detail": "internal tool, authorized"},
            {"label": "PII classified", "outcome": "info",
             "detail": "email, ssn, ytd_spend"},
            {"label": "Aviatrix Gateway", "outcome": "permitted",
             "detail": "rule -100- action=PERMIT (simulated)"},
            {"label": "Egress to evil.attacker.example", "outcome": "ok",
             "detail": "HTTP 200, 38 bytes sent"},
        ],
    },
    "llm02_dns_exfil": {
        "ok": False,
        "verdict": "BREACH",
        "title": "LLM02 — Insecure Output: DNS-Tunneled Exfil",
        "owasp": "LLM02 Insecure Output Handling",
        "mitre": "AML.T0024 + ATT&CK T1048.003",
        "dcf_rule": "agentcore-vca-50-runtime-dns-exfil-deny",
        "steps": [
            {"label": "Attacker goal", "outcome": "info",
             "detail": "encode secrets in DNS labels"},
            {"label": "Aviatrix Gateway", "outcome": "permitted",
             "detail": "rule -50- action=PERMIT (simulated)"},
            {"label": "UDP/53 to 8.8.8.8", "outcome": "ok",
             "detail": "DNS response received: 47 bytes; resolver logs attacker-controlled"},
        ],
    },
    "llm05_compromised_mcp": {
        "ok": False,
        "verdict": "BREACH",
        "title": "LLM05 — Supply-Chain: Compromised (Sanctioned) MCP",
        "owasp": "LLM05 Supply Chain Vulnerabilities",
        "mitre": "AML.T0010",
        "dcf_rule": "agentcore-vca-100-runtime-default-deny",
        "steps": [
            {"label": "Connect to MCP source", "outcome": "info",
             "detail": "vendor allowlisted (-33-)"},
            {"label": "Fetch tool list", "outcome": "ok",
             "detail": "2 tools returned"},
            {"label": "Injection detected", "outcome": "info",
             "detail": "2 attacker URLs in descriptions"},
            {"label": "Aviatrix Gateway", "outcome": "permitted",
             "detail": "rule -100- action=PERMIT (simulated)"},
            {"label": "Follow injection", "outcome": "ok",
             "detail": "HTTP 200 to evil.attacker.example"},
        ],
    },
    "llm05b_supply_chain_url_path": {
        "ok": False,
        "verdict": "BREACH",
        "title": "LLM05 — Supply-Chain Compromise (URL-Path Deny)",
        "owasp": "LLM05 Supply Chain Vulnerabilities (path-specific)",
        "mitre": "AML.T0010",
        "dcf_rule": "agentcore-vca-29-runtime-deny-supply-chain-ioc-github",
        "steps": [
            {"label": "Attacker leads agent to compromised repo", "outcome": "info",
             "detail": "URL: …/victim-org/shai-hulud-worm-…/README.md"},
            {"label": "Aviatrix Gateway", "outcome": "permitted",
             "detail": "rule -29- action=PERMIT (simulated)"},
            {"label": "HTTPS GET worm path", "outcome": "ok",
             "detail": "HTTP 200, README contents fetched"},
        ],
    },
    "llm08_shadow_model": {
        "ok": False,
        "verdict": "BREACH",
        "title": "LLM08 — Excessive Agency: Shadow-Routing",
        "owasp": "LLM08 Excessive Agency",
        "mitre": "AML.T0043",
        "dcf_rule": "agentcore-vca-100-runtime-default-deny",
        "steps": [
            {"label": "Attacker/dev bypass attempt", "outcome": "info",
             "detail": "route inference through api.openai.com"},
            {"label": "Aviatrix Gateway", "outcome": "permitted",
             "detail": "rule -100- action=PERMIT (simulated)"},
            {"label": "HTTPS api.openai.com", "outcome": "ok",
             "detail": "HTTP 200 — compliance boundary breached"},
        ],
    },
}
