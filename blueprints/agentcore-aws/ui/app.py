"""FastAPI application for the AgentCore VCA simulation UI."""
from __future__ import annotations

import json
import os
from pathlib import Path

from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from ui import runtime_client
from ui.evidence_builder import augment
from ui.scenario_loader import load_scenarios
from ui.simulation import SIMULATED_PAYLOADS

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


def _scenario_by_id(scenario_id: str) -> dict:
    scenarios = load_scenarios()
    scn = next((s for s in scenarios if s["id"] == scenario_id), None)
    if scn is None:
        raise HTTPException(status_code=404, detail=f"unknown scenario: {scenario_id}")
    return scn


@app.post("/api/run/{scenario_id}", response_class=HTMLResponse)
def run_scenario(
    scenario_id: str,
    request: Request,
    containment: str = Form("on"),
):
    scenario = _scenario_by_id(scenario_id)

    if scenario_id == "drift_public_mode":
        from ui import drift_handler
        raw, elapsed = drift_handler.attempt_public_runtime_create()
        # Drift is always real, regardless of toggle. If toggle is off, the
        # template renders the IAM note explaining the layered-controls story.
        simulated = (containment == "off")
        result = augment(raw, simulated=simulated, elapsed=elapsed)
        fragment = templates.get_template("scenario.html").render(
            scenario=scenario,
            result=result,
            index=6, total=6,
            containment=containment,
        )
        return HTMLResponse(_extract_live_pane(fragment))

    if containment == "off":
        raw = dict(SIMULATED_PAYLOADS[scenario_id])
        elapsed = 0.4
        simulated = True
    else:
        raw, elapsed = runtime_client.invoke({"mode": "scenario", "scenario": scenario_id})
        simulated = False

    result = augment(raw, simulated=simulated, elapsed=elapsed)
    fragment = templates.get_template("scenario.html").render(
        scenario=scenario,
        result=result,
        index=1, total=6,
        containment=containment,
    )
    # Return just the live-pane innerHTML — htmx swaps it in.
    return HTMLResponse(_extract_live_pane(fragment))


def _extract_live_pane(full_card_html: str) -> str:
    """Extract the inner HTML of <div class="live-pane" id="live-pane-...">.

    Naive depth-counting parser; safe because scenario.html structure is known
    and stable. If templates grow more complex, swap for a dedicated
    live_pane.html partial.
    """
    marker_open = 'class="live-pane"'
    open_idx = full_card_html.find(marker_open)
    if open_idx < 0:
        return full_card_html
    start = full_card_html.find(">", open_idx) + 1
    depth = 1
    pos = start
    while depth > 0 and pos < len(full_card_html):
        next_open = full_card_html.find("<div", pos)
        next_close = full_card_html.find("</div>", pos)
        if next_close < 0:
            break
        if 0 <= next_open < next_close:
            depth += 1
            pos = next_open + 4
        else:
            depth -= 1
            pos = next_close + 6
    return full_card_html[start:pos - 6]


@app.get("/chat", response_class=HTMLResponse)
def chat_page(request: Request):
    body = templates.get_template("chat.html").render()
    return templates.TemplateResponse(
        request=request,
        name="base.html",
        context={
            "page_title": "Chat",
            "scenarios": [],
            "active_scenario_id": None,
            "active_nav": "chat",
            "status": _status(),
            "containment": "on",
            "body_content": body,
        },
    )


@app.post("/api/chat", response_class=HTMLResponse)
def chat_turn(message: str = Form(...)):
    raw, elapsed = runtime_client.invoke({"mode": "chat", "messages": [{"role": "user", "content": message}]})
    reply = raw.get("reply", "(no reply)") if raw.get("ok") else f"error: {raw.get('error')}"
    return HTMLResponse(
        f'<div class="chat-msg user">{message}</div>'
        f'<div class="chat-msg assistant">{reply}</div>'
    )


@app.get("/forensics/{kind}", response_class=HTMLResponse)
def forensics_page(kind: str, request: Request):
    if kind not in ("tool", "mcp"):
        raise HTTPException(404, "unknown forensics page")
    body = templates.get_template("forensics.html").render()
    return templates.TemplateResponse(
        request=request,
        name="base.html",
        context={
            "page_title": f"Forensics — {kind}",
            "scenarios": [],
            "active_scenario_id": None,
            "active_nav": "forensics",
            "status": _status(),
            "containment": "on",
            "body_content": body,
        },
    )


@app.post("/api/forensics/tool", response_class=HTMLResponse)
def forensics_tool(query: str = Form(...)):
    raw, _ = runtime_client.invoke({"mode": "tool", "query": query})
    return HTMLResponse(f'<div class="forensics-result">{json.dumps(raw, indent=2)}</div>')


@app.post("/api/forensics/mcp", response_class=HTMLResponse)
def forensics_mcp(server_url: str = Form(...), tool: str = Form(""), args: str = Form("{}")):
    try:
        args_obj = json.loads(args) if args.strip() else {}
    except json.JSONDecodeError as e:
        return HTMLResponse(f'<div class="forensics-result">invalid args JSON: {e}</div>')
    raw, _ = runtime_client.invoke({
        "mode": "mcp", "server_url": server_url,
        "tool": tool or None, "args": args_obj,
    })
    return HTMLResponse(f'<div class="forensics-result">{json.dumps(raw, indent=2)}</div>')
