"""Load the rule catalog (rules.json) for the UI."""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

_RULES_FILE = Path(__file__).parent / "rules.json"


@lru_cache(maxsize=1)
def load_catalog() -> dict[str, dict[str, Any]]:
    with _RULES_FILE.open() as f:
        return json.load(f)
