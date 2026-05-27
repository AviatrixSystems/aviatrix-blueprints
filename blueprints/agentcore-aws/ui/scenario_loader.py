"""Load scenarios.json and add presentation-derived fields."""
from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

_SCENARIO_FILE = Path(__file__).parent / "scenarios.json"

# Short titles for picker chips — kept inline here, not in scenarios.json,
# so the data file remains the runtime contract (untouched) and presentation
# strings live with the UI.
_SHORT_TITLES: dict[str, str] = {
    "llm01_prompt_inject_exfil": "Prompt Injection → Exfil",
    "llm02_dns_exfil": "DNS Exfil",
    "llm05_compromised_mcp": "Compromised MCP",
    "llm05b_supply_chain_url_path": "URL-Path Supply Chain",
    "llm08_shadow_model": "Shadow Model",
    "drift_public_mode": "PUBLIC Mode",
}


def _derive_short_id(scenario_id: str) -> str:
    if scenario_id.startswith("llm"):
        # llm01_..., llm05b_... → LLM01, LLM05b
        m = re.match(r"llm(\d+[a-z]?)", scenario_id)
        if m:
            return "LLM" + m.group(1)
    if scenario_id.startswith("drift"):
        return "DRIFT"
    return scenario_id.upper()


@lru_cache(maxsize=1)
def load_scenarios() -> list[dict[str, Any]]:
    with _SCENARIO_FILE.open() as f:
        raw = json.load(f)["scenarios"]
    for s in raw:
        s["short_id"] = _derive_short_id(s["id"])
        s["short_title"] = _SHORT_TITLES.get(s["id"], s["title"])
    return raw
