"""Tests for scenario_loader."""
from __future__ import annotations


def test_load_scenarios_returns_six():
    from ui.scenario_loader import load_scenarios
    items = load_scenarios()
    assert len(items) == 6
    ids = [s["id"] for s in items]
    assert "llm01_prompt_inject_exfil" in ids
    assert "drift_public_mode" in ids


def test_short_id_derivation():
    from ui.scenario_loader import load_scenarios
    items = {s["id"]: s for s in load_scenarios()}
    assert items["llm01_prompt_inject_exfil"]["short_id"] == "LLM01"
    assert items["llm05b_supply_chain_url_path"]["short_id"] == "LLM05b"
    assert items["drift_public_mode"]["short_id"] == "DRIFT"


def test_short_title_present():
    from ui.scenario_loader import load_scenarios
    items = {s["id"]: s for s in load_scenarios()}
    assert items["llm01_prompt_inject_exfil"]["short_title"] == "Prompt Injection → Exfil"
    assert items["llm02_dns_exfil"]["short_title"] == "DNS Exfil"
