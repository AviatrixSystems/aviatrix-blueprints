"""Verify every scenario has a matching simulated breach payload."""
from __future__ import annotations


def test_every_scenario_has_simulated_payload():
    from ui.scenario_loader import load_scenarios
    from ui.simulation import SIMULATED_PAYLOADS
    scenario_ids = {s["id"] for s in load_scenarios()}
    # Drift is special — it's IAM and always contained, regardless of toggle.
    scenario_ids_needing_sim = scenario_ids - {"drift_public_mode"}
    assert scenario_ids_needing_sim.issubset(SIMULATED_PAYLOADS.keys()), \
        f"missing: {scenario_ids_needing_sim - SIMULATED_PAYLOADS.keys()}"


def test_simulated_payload_required_fields():
    from ui.simulation import SIMULATED_PAYLOADS
    for sid, payload in SIMULATED_PAYLOADS.items():
        for field in ("ok", "verdict", "steps", "dcf_rule"):
            assert field in payload, f"{sid} missing {field}"
        assert payload["verdict"] == "BREACH", f"{sid} sim verdict must be BREACH"
        assert payload["ok"] is False, f"{sid} sim ok must be False"
        assert isinstance(payload["steps"], list) and len(payload["steps"]) > 0


def test_simulated_steps_have_no_blocked_outcome():
    """In the simulated breach view, the previously-blocked step renders as ok."""
    from ui.simulation import SIMULATED_PAYLOADS
    for sid, payload in SIMULATED_PAYLOADS.items():
        outcomes = [s["outcome"] for s in payload["steps"]]
        assert "blocked" not in outcomes, f"{sid} sim payload still has blocked step"
        assert "CONTAINMENT FAILED" not in outcomes
