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
