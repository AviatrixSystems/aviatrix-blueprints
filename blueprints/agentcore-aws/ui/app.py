"""FastAPI application for the AgentCore VCA simulation UI."""
from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from ui.scenario_loader import load_scenarios

app = FastAPI(title="AgentCore VCA — AI Attack Simulation")

BASE_DIR = Path(__file__).parent
STATIC_DIR = BASE_DIR / "static"
TEMPLATE_DIR = BASE_DIR / "templates"

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=str(TEMPLATE_DIR))


def _status() -> dict[str, str]:
    return {
        "region": os.environ.get("AWS_REGION", "us-east-2"),
        "runtime": os.environ.get("AGENTCORE_RUNTIME_ARN", "(unset)").rsplit("/", 1)[-1],
        "data_plane": os.environ.get("AGENTCORE_DATA_HOST", "(unset)"),
        "dcf_rules": "-29- -30- -31- -33- -50- -100-",
        "controller_version": os.environ.get("AVIATRIX_CONTROLLER_VERSION", "9.0+"),
    }


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}


@app.get("/", include_in_schema=False)
def root():
    scenarios = load_scenarios()
    return RedirectResponse(url=f"/s/{scenarios[0]['id']}", status_code=302)


def _render_scenario_card(scenario_id: str, containment: str) -> tuple[dict, str]:
    """Return (scenario, card_html) — the scenario.html partial with no chrome."""
    scenarios = load_scenarios()
    index = next((i for i, s in enumerate(scenarios) if s["id"] == scenario_id), None)
    if index is None:
        raise HTTPException(status_code=404, detail=f"unknown scenario: {scenario_id}")
    scenario = scenarios[index]
    card = templates.get_template("scenario.html").render(
        scenario=scenario,
        result=None,
        index=index + 1,
        total=len(scenarios),
        containment=containment,
    )
    return scenario, card


@app.get("/s/{scenario_id}", response_class=HTMLResponse)
def scenario_page(scenario_id: str, request: Request, containment: str = "on"):
    scenario, card = _render_scenario_card(scenario_id, containment)
    return templates.TemplateResponse(
        request=request,
        name="base.html",
        context={
            "page_title": scenario["short_title"],
            "scenarios": load_scenarios(),
            "active_scenario_id": scenario_id,
            "active_nav": "scenarios",
            "status": _status(),
            "containment": containment,
            "body_content": card,
        },
    )


@app.get("/s/{scenario_id}/fragment", response_class=HTMLResponse)
def scenario_fragment(scenario_id: str, containment: str = "on"):
    """HTMX target for picker chip clicks — returns just the card."""
    _, card = _render_scenario_card(scenario_id, containment)
    return HTMLResponse(card)
