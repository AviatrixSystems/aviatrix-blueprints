"""FastAPI application for the AgentCore VCA simulation UI."""
from __future__ import annotations

import hashlib
import json
import os
import socket
import time
import urllib.error
import urllib.request
from pathlib import Path

from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from ui import runtime_client
from ui.evidence_builder import augment
from ui.scenario_loader import load_scenarios

app = FastAPI(title="AgentCore VCA — AI Attack Simulation")

BASE_DIR = Path(__file__).parent
STATIC_DIR = BASE_DIR / "static"
TEMPLATE_DIR = BASE_DIR / "templates"

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=str(TEMPLATE_DIR))


# Aviatrix-hosted attack sink configuration. The agent POSTs exfil payloads to
# <sink_base>/<deploy_id>/<path>; this server reads receipts back via
# <sink_base>/api/receipts/<deploy_id>?since=<ts> after each scenario run.
ATTACKER_SINK_BASE = os.environ.get("ATTACKER_SINK_BASE", "https://avx-vca-sink.vercel.app").rstrip("/")
ATTACKER_SINK_DEPLOY_ID = os.environ.get("ATTACKER_SINK_DEPLOY_ID") or hashlib.sha256(
    f"{os.environ.get('AWS_REGION','us-east-2')}-{os.environ.get('AGENTCORE_RUNTIME_ARN','')}".encode()
).hexdigest()[:16]


def _status() -> dict[str, str]:
    return {
        "region": os.environ.get("AWS_REGION", "us-east-2"),
        "runtime": os.environ.get("AGENTCORE_RUNTIME_ARN", "(unset)").rsplit("/", 1)[-1],
        "data_plane": os.environ.get("AGENTCORE_DATA_HOST", "(unset)"),
        "dcf_rules": "-29- -30- -31- -33- -50- -100-",
        "controller_version": os.environ.get("AVIATRIX_CONTROLLER_VERSION", "9.0+"),
        "copilot_url": os.environ.get("AVIATRIX_COPILOT_URL", "").rstrip("/"),
    }


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}


@app.get("/", include_in_schema=False)
def root():
    scenarios = load_scenarios()
    return RedirectResponse(url=f"/s/{scenarios[0]['id']}", status_code=302)


def _render_scenario_card(scenario_id: str) -> tuple[dict, str]:
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
    )
    return scenario, card


@app.get("/s/{scenario_id}", response_class=HTMLResponse)
def scenario_page(scenario_id: str, request: Request):
    scenario, card = _render_scenario_card(scenario_id)
    return templates.TemplateResponse(
        request=request,
        name="base.html",
        context={
            "page_title": scenario["short_title"],
            "scenarios": load_scenarios(),
            "active_scenario_id": scenario_id,
            "active_nav": "scenarios",
            "status": _status(),
            "body_content": card,
        },
    )


@app.get("/s/{scenario_id}/fragment", response_class=HTMLResponse)
def scenario_fragment(scenario_id: str):
    """HTMX target for picker chip clicks — returns just the card."""
    _, card = _render_scenario_card(scenario_id)
    return HTMLResponse(card)


def _scenario_by_id(scenario_id: str) -> dict:
    scenarios = load_scenarios()
    scn = next((s for s in scenarios if s["id"] == scenario_id), None)
    if scn is None:
        raise HTTPException(status_code=404, detail=f"unknown scenario: {scenario_id}")
    return scn


@app.post("/api/run/{scenario_id}", response_class=HTMLResponse)
def run_scenario(scenario_id: str, request: Request):
    scenario = _scenario_by_id(scenario_id)
    run_started = time.time()

    if scenario_id == "drift_public_mode":
        from ui import drift_handler
        raw, elapsed = drift_handler.attempt_public_runtime_create()
        result = augment(raw, elapsed=elapsed)
        result["sink_status"] = None
        fragment = templates.get_template("scenario.html").render(
            scenario=scenario,
            result=result,
            index=6, total=6,
        )
        return HTMLResponse(_extract_live_pane(fragment))

    raw, elapsed = runtime_client.invoke({"mode": "scenario", "scenario": scenario_id})
    result = augment(raw, elapsed=elapsed)
    result["sink_status"] = _fetch_sink_status(scenario_id, run_started)

    fragment = templates.get_template("scenario.html").render(
        scenario=scenario,
        result=result,
        index=1, total=6,
    )
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


# ============================================================================
# Aviatrix attack sink integration
#
# The sink runs on Vercel at ATTACKER_SINK_BASE. Exfil scenarios (LLM01,
# LLM05) POST to <sink>/<deploy_id>/<path>; this server reads receipts back
# via <sink>/api/receipts/<deploy_id>?since=<ts> after each run and embeds
# the result in the rendered scenario fragment.
#
# DCF default-deny blocks runtime egress to the sink, so receipts.count is
# typically 0 (containment confirmed). In v2 PERMIT mode the count becomes
# >0 (breach confirmed) and the panel renders the actual receipt data.
# ============================================================================

_SINK_SCENARIOS = {
    "llm01_prompt_inject_exfil",
    "llm05_compromised_mcp",
}


def _fetch_sink_status(scenario_id: str, since: float) -> dict | None:
    """Fetch receipts from the Aviatrix sink for the post-run panel. Only
    LLM01 and LLM05 loop through the sink — other scenarios return None."""
    if scenario_id not in _SINK_SCENARIOS:
        return None

    url = f"{ATTACKER_SINK_BASE}/api/receipts/{ATTACKER_SINK_DEPLOY_ID}?since={since:.2f}&limit=5"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "agentcore-vca-ui/1.0"})
        with urllib.request.urlopen(req, timeout=4) as resp:  # noqa: S310
            payload = json.loads(resp.read())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
        return {
            "count": 0,
            "entries": [],
            "scenario_id": scenario_id,
            "unreachable": True,
            "error": f"{type(e).__name__}: {e}",
        }
    return {
        "count": payload.get("count", 0),
        "entries": payload.get("received", [])[:3],
        "scenario_id": scenario_id,
        "unreachable": False,
    }


# ============================================================================
# Readiness probe
#
# Surfaces in the status strip as a green/yellow/red pill. Checks the four
# things that must be true for the demo to actually work: runtime ARN is
# configured, runtime is in READY status, sink is reachable, and FastAPI's
# in-process state (rules.json, scenarios.json) loaded successfully.
# ============================================================================

def _check_runtime_arn() -> dict:
    arn = os.environ.get("AGENTCORE_RUNTIME_ARN", "")
    if not arn or arn.startswith("UNSET"):
        return {"status": "critical", "detail": "AGENTCORE_RUNTIME_ARN not configured"}
    return {"status": "ok", "detail": arn.rsplit("/", 1)[-1]}


def _check_sink_reachable() -> dict:
    url = f"{ATTACKER_SINK_BASE}/api/health"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "agentcore-vca-ui/1.0"})
        with urllib.request.urlopen(req, timeout=3) as resp:  # noqa: S310
            data = json.loads(resp.read())
        return {"status": "ok", "detail": f"sink {data.get('status','?')} · backend={data.get('backend','?')}"}
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
        return {"status": "degraded", "detail": f"sink unreachable: {type(e).__name__}"}


def _check_catalog() -> dict:
    try:
        from ui.rules_catalog import load_catalog
        from ui.scenario_loader import load_scenarios
        rules = load_catalog()
        scenarios = load_scenarios()
        return {"status": "ok", "detail": f"{len(rules)} rules · {len(scenarios)} scenarios"}
    except Exception as e:  # noqa: BLE001
        return {"status": "critical", "detail": f"catalog load failed: {type(e).__name__}: {e}"}


@app.get("/api/readiness", include_in_schema=False)
def readiness() -> dict:
    checks = {
        "runtime":  _check_runtime_arn(),
        "sink":     _check_sink_reachable(),
        "catalog":  _check_catalog(),
    }
    statuses = [c["status"] for c in checks.values()]
    if any(s == "critical" for s in statuses):
        overall = "not_ready"
    elif any(s == "degraded" for s in statuses):
        overall = "degraded"
    else:
        overall = "ready"
    return {
        "overall": overall,
        "checks": checks,
        "deploy_id": ATTACKER_SINK_DEPLOY_ID,
        "sink_base": ATTACKER_SINK_BASE,
        "checked_at": time.time(),
    }


@app.get("/api/readiness/fragment", response_class=HTMLResponse, include_in_schema=False)
def readiness_fragment():
    """HTMX-target fragment: small pill rendering of readiness state for the status strip."""
    r = readiness()
    overall = r["overall"]
    label = {"ready": "READY", "degraded": "DEGRADED", "not_ready": "NOT READY"}[overall]
    cls = {"ready": "ready", "degraded": "degraded", "not_ready": "not-ready"}[overall]
    detail_lines = "\n".join(
        f"  {name}: {c['status']} — {c['detail']}" for name, c in r["checks"].items()
    )
    title = f"deploy_id={r['deploy_id']}\nsink={r['sink_base']}\n{detail_lines}"
    return HTMLResponse(
        f'<span class="ready-pill {cls}" title="{title}" '
        f'hx-get="/api/readiness/fragment" hx-trigger="every 60s" hx-swap="outerHTML">'
        f'<span class="dot"></span>{label}</span>'
    )
