# agentcore-aws UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Streamlit operator UI in `blueprints/agentcore-aws/ui/` with a FastAPI + Jinja2 + Tailwind application styled in the Aviatrix Threat Research Center editorial register, including a dummy Containment toggle that renders precomputed "without Aviatrix" payloads.

**Architecture:** FastAPI + Jinja2 + vendored Tailwind, served by uvicorn on the existing client invoker EC2 (same ALB, same S3 bundle pattern, same env file). Templates loop over runtime payloads — no per-scenario rendering code. A static `rules.json` written by a terraform helper at apply time supplies the DCF / IAM rule catalog the UI server uses to augment runtime responses.

**Tech Stack:** Python 3.11, FastAPI, uvicorn[standard], Jinja2, boto3, HTMX (vendored), Tailwind (vendored CSS), pytest, botocore.stub.Stubber for AWS mocking. Spec: `docs/superpowers/specs/2026-05-26-agentcore-aws-ui-redesign-design.md`.

---

## File Structure

**New directories under `blueprints/agentcore-aws/ui/`:**
```
ui/
├── runtime_client.py        (NEW)
├── simulation.py            (NEW)
├── templates/
│   ├── base.html            (NEW)
│   ├── scenario.html        (NEW)
│   ├── chat.html            (NEW)
│   ├── forensics.html       (NEW)
│   └── partials/
│       ├── flow.html        (NEW)
│       ├── rule_block.html  (NEW)
│       └── evidence.html    (NEW)
├── static/
│   ├── tailwind.css         (NEW, vendored)
│   ├── sora.css             (NEW, vendored woff2 + @font-face)
│   ├── htmx.min.js          (NEW, vendored)
│   ├── aviatrix.svg         (NEW, copied from research/logos/)
│   └── tokens.css           (NEW, CSS-variable form of design tokens)
└── tests/
    ├── __init__.py          (NEW)
    ├── conftest.py          (NEW)
    ├── test_simulation_payloads.py  (NEW)
    ├── test_template_render.py      (NEW)
    └── test_routes.py               (NEW)
```

**Files rewritten:** `ui/app.py` (full rewrite).

**Files edited:**
- `ui/requirements.txt` — swap `streamlit` for fastapi/uvicorn/jinja2
- `ui/agentcore-ui.service` — `ExecStart` line
- `client.tf` — user_data S3 fetch list + venv bootstrap
- `ui.tf` — S3 bundle objects list expands; old streamlit objects removed
- `ui-alb.tf` — target-group healthcheck path moves to `/healthz`
- `dcf.tf` — add a `local_file` resource that writes `rules.json` from terraform state
- `.gitignore` — add `ui/.venv/` and `ui/__pycache__/`

**Files preserved unchanged:** `agent/app.py`, `adversary/handler.py`, `scenarios.json`, `tests/probe.sh`, everything else under `blueprints/agentcore-aws/`.

---

## Task 1: Bootstrap directory structure and local dev venv

**Files:**
- Create: `blueprints/agentcore-aws/ui/templates/partials/.gitkeep`
- Create: `blueprints/agentcore-aws/ui/static/.gitkeep`
- Create: `blueprints/agentcore-aws/ui/tests/__init__.py`
- Modify: `blueprints/agentcore-aws/.gitignore`

- [ ] **Step 1: Read the spec to confirm the file layout**

```bash
cat docs/superpowers/specs/2026-05-26-agentcore-aws-ui-redesign-design.md | head -200
```
Expected: see § "File layout" listing the structure above. Use this section as the source of truth for paths.

- [ ] **Step 2: Create the new directories**

```bash
cd blueprints/agentcore-aws
mkdir -p ui/templates/partials ui/static ui/tests
touch ui/templates/partials/.gitkeep ui/static/.gitkeep
```

- [ ] **Step 3: Create the test package marker**

Write `blueprints/agentcore-aws/ui/tests/__init__.py` (empty file).

```python
```

- [ ] **Step 4: Update .gitignore for dev-only artifacts**

Read `blueprints/agentcore-aws/.gitignore` first, then append:

```
# Local dev only
ui/.venv/
ui/__pycache__/
ui/**/__pycache__/
ui/.pytest_cache/
```

- [ ] **Step 5: Create local venv for development**

```bash
cd blueprints/agentcore-aws/ui
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
```

Expected: `.venv/` directory created. This directory is gitignored.

- [ ] **Step 6: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.worktrees/agentcore-aws-visual-refresh
git add blueprints/agentcore-aws/ui/templates blueprints/agentcore-aws/ui/static blueprints/agentcore-aws/ui/tests blueprints/agentcore-aws/.gitignore
git commit -m "agentcore-aws ui: scaffold directories for FastAPI redesign"
```

---

## Task 2: Update requirements.txt and install deps

**Files:**
- Modify: `blueprints/agentcore-aws/ui/requirements.txt`

- [ ] **Step 1: Replace requirements.txt contents**

```
fastapi>=0.110
uvicorn[standard]>=0.27
jinja2>=3.1
boto3>=1.34
pytest>=8.0
httpx>=0.27
```

(`httpx` is required by `fastapi.testclient.TestClient`.)

- [ ] **Step 2: Install into the dev venv**

```bash
cd blueprints/agentcore-aws/ui
.venv/bin/pip install -r requirements.txt
```

Expected: clean install, no errors. `.venv/bin/pytest --version` works.

- [ ] **Step 3: Verify FastAPI imports**

```bash
.venv/bin/python -c "import fastapi, jinja2, boto3, httpx; print('ok')"
```

Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.worktrees/agentcore-aws-visual-refresh
git add blueprints/agentcore-aws/ui/requirements.txt
git commit -m "agentcore-aws ui: swap streamlit deps for fastapi/uvicorn/jinja2"
```

---

## Task 3: Write the healthz route test, then implement the FastAPI scaffold

**Files:**
- Create: `blueprints/agentcore-aws/ui/tests/test_routes.py`
- Create: `blueprints/agentcore-aws/ui/tests/conftest.py`
- Rewrite: `blueprints/agentcore-aws/ui/app.py`

- [ ] **Step 1: Write conftest.py with a TestClient fixture**

`blueprints/agentcore-aws/ui/tests/conftest.py`:

```python
"""Shared pytest fixtures for the UI test suite."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client():
    # Import inside the fixture so tests can monkeypatch boto3 if needed
    from ui.app import app
    return TestClient(app)
```

- [ ] **Step 2: Write the healthz test**

`blueprints/agentcore-aws/ui/tests/test_routes.py`:

```python
"""Smoke tests for FastAPI routes."""
from __future__ import annotations


def test_healthz_returns_200(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "healthy"}
```

- [ ] **Step 3: Run the test (expect failure: no app module yet)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_routes.py -v 2>&1 | tail -20
```
Run from `blueprints/agentcore-aws/` so `ui.app` is importable. Expected: ImportError / ModuleNotFoundError.

- [ ] **Step 4: Write the minimal FastAPI app**

Rewrite `blueprints/agentcore-aws/ui/app.py` completely:

```python
"""FastAPI application for the AgentCore VCA simulation UI.

Replaces the previous Streamlit implementation. See
docs/superpowers/specs/2026-05-26-agentcore-aws-ui-redesign-design.md
for the full design.
"""
from __future__ import annotations

from fastapi import FastAPI

app = FastAPI(title="AgentCore VCA — AI Attack Simulation")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}
```

- [ ] **Step 5: Run the test (expect pass)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_routes.py -v
```
Expected: 1 passed.

- [ ] **Step 6: Run uvicorn locally to sanity-check**

```bash
cd blueprints/agentcore-aws
.venv/bin/uvicorn ui.app:app --port 18501 &
sleep 1
curl -s http://127.0.0.1:18501/healthz
kill %1 2>/dev/null
```
Expected: `{"status":"healthy"}`.

- [ ] **Step 7: Commit**

```bash
git add blueprints/agentcore-aws/ui/app.py blueprints/agentcore-aws/ui/tests
git commit -m "agentcore-aws ui: FastAPI scaffold with /healthz"
```

---

## Task 4: Vendor Tailwind, Sora, HTMX, and the Aviatrix logo

**Files:**
- Create: `blueprints/agentcore-aws/ui/static/tailwind.css`
- Create: `blueprints/agentcore-aws/ui/static/sora.css`
- Create: `blueprints/agentcore-aws/ui/static/sora-700.woff2`
- Create: `blueprints/agentcore-aws/ui/static/sora-600.woff2`
- Create: `blueprints/agentcore-aws/ui/static/htmx.min.js`
- Create: `blueprints/agentcore-aws/ui/static/aviatrix.svg`
- Create: `blueprints/agentcore-aws/ui/static/tokens.css`

These are static assets vendored locally so the EC2 doesn't need to reach external CDNs.

- [ ] **Step 1: Download Tailwind 3.x standalone CSS**

```bash
cd blueprints/agentcore-aws/ui/static
curl -fSLo tailwind.css https://cdn.jsdelivr.net/npm/tailwindcss@3.4.4/dist/tailwind.min.css
ls -la tailwind.css
```
Expected: file ~3MB. (Acceptable — vendored once, served with long cache.)

- [ ] **Step 2: Download Sora woff2 files from Google Fonts**

```bash
cd blueprints/agentcore-aws/ui/static
# Sora 600 + 700 are the only weights used per the spec § Typography
curl -fSLo sora-600.woff2 'https://fonts.gstatic.com/s/sora/v12/xMQOuFFYT72X5wkB_18qmnndmSdSnk-DKQJRBg.woff2'
curl -fSLo sora-700.woff2 'https://fonts.gstatic.com/s/sora/v12/xMQOuFFYT72X5wkB_18qmnndmSdSnk-DKQJRBg.woff2'
ls -la sora-*.woff2
```
Expected: two files ~20KB each. (Note: the actual woff2 URLs vary by Google Fonts API revision; the engineer should pin the URLs that resolve at execution time.)

- [ ] **Step 3: Write sora.css**

`blueprints/agentcore-aws/ui/static/sora.css`:

```css
@font-face {
  font-family: 'Sora';
  font-weight: 600;
  font-display: swap;
  src: url('/static/sora-600.woff2') format('woff2');
}
@font-face {
  font-family: 'Sora';
  font-weight: 700;
  font-display: swap;
  src: url('/static/sora-700.woff2') format('woff2');
}
```

- [ ] **Step 4: Download HTMX**

```bash
cd blueprints/agentcore-aws/ui/static
curl -fSLo htmx.min.js https://unpkg.com/htmx.org@1.9.12/dist/htmx.min.js
ls -la htmx.min.js
```
Expected: file ~50KB.

- [ ] **Step 5: Copy the Aviatrix logo**

```bash
cp ../../../research/logos/aviatrix-logo-white-orange.svg blueprints/agentcore-aws/ui/static/aviatrix.svg
```

Run from the worktree root. Expected: SVG exists in static/.

- [ ] **Step 6: Write tokens.css**

`blueprints/agentcore-aws/ui/static/tokens.css`:

```css
/* Design tokens — source of truth: research/tokens.json + spec § Visual design system */
:root {
  --brand-orange-primary: #E24402;
  --brand-orange-warm: #FA6B1E;
  --brand-purple: #7A5DDC;

  --surface-cream: #FCF9F3;
  --surface-orange-50: #FFF7ED;
  --surface-white: #FFFFFF;
  --surface-panel-deep: #030712;
  --surface-panel-ink: #111827;
  --surface-border: #e7e0d4;
  --surface-divider: #E5E7EB;

  --text-ink: #181818;
  --text-muted: #6B7280;
  --text-on-dark: #FFFFFF;
  --text-on-dark-muted: rgba(255,255,255,0.65);

  --severity-green: #22C55E;
  --severity-yellow: #EAB308;
  --severity-red: #DC2626;
  --severity-gray: #9CA3AF;

  --radius-panel: 16px;
  --radius-card: 12px;
  --radius-pill: 9999px;

  --font-display: 'Sora', system-ui, sans-serif;
  --font-body: ui-sans-serif, system-ui, sans-serif;
  --font-mono: ui-monospace, SFMono-Regular, Menlo, monospace;
}
```

- [ ] **Step 7: Mount /static in FastAPI**

Edit `blueprints/agentcore-aws/ui/app.py` — add the StaticFiles mount:

```python
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pathlib import Path

app = FastAPI(title="AgentCore VCA — AI Attack Simulation")

STATIC_DIR = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}
```

- [ ] **Step 8: Add a route test for static assets**

Append to `blueprints/agentcore-aws/ui/tests/test_routes.py`:

```python
def test_static_assets_served(client):
    for asset in ["/static/tokens.css", "/static/sora.css", "/static/htmx.min.js", "/static/aviatrix.svg"]:
        r = client.get(asset)
        assert r.status_code == 200, f"{asset} returned {r.status_code}"
```

- [ ] **Step 9: Run tests**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/ -v
```
Expected: 2 passed.

- [ ] **Step 10: Commit**

```bash
git add blueprints/agentcore-aws/ui/static blueprints/agentcore-aws/ui/app.py blueprints/agentcore-aws/ui/tests/test_routes.py
git commit -m "agentcore-aws ui: vendor static assets (tailwind, sora, htmx, logo, tokens)"
```

---

## Task 5: Write the base template (page chrome shell)

**Files:**
- Create: `blueprints/agentcore-aws/ui/templates/base.html`

The chrome from the locked mockup `research/mockups/01-page-chrome.html`. The base template is the shell into which scenario/chat/forensics content slots.

- [ ] **Step 1: Write the test for base.html rendering**

Create `blueprints/agentcore-aws/ui/tests/test_template_render.py`:

```python
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
```

- [ ] **Step 2: Run the test (expect failure: no template yet)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_template_render.py -v 2>&1 | tail -10
```
Expected: TemplateNotFound for base.html.

- [ ] **Step 3: Write base.html**

`blueprints/agentcore-aws/ui/templates/base.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{{ page_title }} — Aviatrix AI Attack Simulation</title>
<link rel="stylesheet" href="/static/sora.css" />
<link rel="stylesheet" href="/static/tokens.css" />
<link rel="stylesheet" href="/static/tailwind.css" />
<script src="/static/htmx.min.js" defer></script>
<style>
  body { font-family: var(--font-body); background: var(--surface-cream); color: var(--text-ink); margin: 0; }
  .header { background: var(--surface-panel-deep); color: var(--text-on-dark); padding: 16px 32px; display: flex; align-items: center; justify-content: space-between; }
  .header .brand { display: flex; align-items: center; gap: 14px; }
  .header .logo { display: inline-flex; align-items: center; gap: 8px; font-family: var(--font-display); font-weight: 700; font-size: 18px; }
  .header .logo-mark { width: 26px; height: 26px; background: var(--brand-orange-primary); border-radius: 5px; display: inline-flex; align-items: center; justify-content: center; font-weight: 800; }
  .header .eyebrow { font-family: var(--font-display); font-weight: 600; font-size: 11px; letter-spacing: 0.10em; text-transform: uppercase; color: var(--brand-orange-warm); }
  .header nav { display: flex; gap: 22px; }
  .header nav a { color: rgba(255,255,255,0.75); text-decoration: none; font-family: var(--font-display); font-weight: 500; font-size: 13px; }
  .header nav a.active { color: #fff; border-bottom: 2px solid var(--brand-orange-primary); padding-bottom: 2px; }
  .title-bar { background: var(--surface-panel-deep); color: #fff; padding: 8px 32px 28px; }
  .title-bar h1 { font-family: var(--font-display); font-weight: 700; font-size: 32px; margin: 0 0 4px; }
  .title-bar .subtitle { color: rgba(255,255,255,0.7); font-size: 14px; max-width: 760px; }
  .picker { background: var(--surface-cream); border-bottom: 1px solid var(--surface-border); padding: 16px 32px; display: flex; align-items: center; gap: 12px; overflow-x: auto; }
  .picker .picker-label { font-family: var(--font-display); font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-muted); white-space: nowrap; }
  .picker .chip { padding: 6px 14px; border-radius: var(--radius-pill); background: #fff; border: 1px solid var(--surface-border); font-family: var(--font-display); font-weight: 500; font-size: 12px; color: #374151; white-space: nowrap; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 6px; }
  .picker .chip:hover { border-color: var(--brand-orange-warm); }
  .picker .chip.active { background: var(--brand-orange-primary); color: #fff; border-color: var(--brand-orange-primary); }
  .picker .chip .id { font-family: var(--font-mono); font-size: 10px; opacity: 0.7; }
  .status-strip { background: #fff; border-bottom: 1px solid var(--surface-border); padding: 10px 32px; display: flex; gap: 24px; flex-wrap: wrap; font-family: var(--font-mono); font-size: 11px; align-items: center; }
  .status-strip .item { display: flex; gap: 6px; align-items: baseline; }
  .status-strip .k { color: #9ca3af; }
  .status-strip .v { color: #374151; }
  .containment-toggle { margin-left: auto; display: flex; align-items: center; gap: 8px; font-family: var(--font-display); font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: #374151; }
  .containment-toggle .switch { width: 36px; height: 18px; background: var(--severity-green); border-radius: var(--radius-pill); position: relative; cursor: pointer; }
  .containment-toggle .switch::after { content: ""; position: absolute; left: 19px; top: 2px; width: 14px; height: 14px; background: #fff; border-radius: 50%; transition: left 0.2s; box-shadow: 0 1px 2px rgba(0,0,0,0.3); }
  .containment-toggle .switch.off { background: var(--severity-red); }
  .containment-toggle .switch.off::after { left: 3px; }
  .footer { background: var(--surface-panel-deep); color: rgba(255,255,255,0.5); padding: 16px 32px; font-size: 11px; font-family: var(--font-mono); display: flex; justify-content: space-between; }
  .footer a { color: rgba(255,255,255,0.7); text-decoration: none; }
  .content { padding: 24px 32px; }
</style>
</head>
<body>

<div class="header">
  <div class="brand">
    <span class="logo">
      <span class="logo-mark">A</span>
      <span>aviatrix</span>
    </span>
    <span class="eyebrow">AI ATTACK SIMULATION</span>
  </div>
  <nav>
    <a class="{{ 'active' if active_nav == 'scenarios' else '' }}" href="/">Scenarios</a>
    <a class="{{ 'active' if active_nav == 'chat' else '' }}" href="/chat">Chat</a>
    <a class="{{ 'active' if active_nav == 'forensics' else '' }}" href="/forensics/tool">Forensics</a>
    <a style="color: rgba(255,255,255,0.5);" href="https://github.com/AviatrixSystems/aviatrix-blueprints/blob/main/blueprints/agentcore-aws/architecture.svg" target="_blank" rel="noopener">Architecture</a>
  </nav>
</div>

<div class="title-bar">
  <h1>AWS Bedrock AgentCore</h1>
  <div class="subtitle">Six AI attack paths run against a live Aviatrix-contained agent runtime. Toggle containment to see the same attack succeed without Aviatrix, then fail with it.</div>
</div>

{% if scenarios %}
<div class="picker">
  <span class="picker-label">Scenario</span>
  {% for s in scenarios %}
  <a class="chip {{ 'active' if s.id == active_scenario_id else '' }}"
     href="/s/{{ s.id }}"
     hx-get="/s/{{ s.id }}/fragment"
     hx-target="#content"
     hx-swap="innerHTML"
     hx-push-url="/s/{{ s.id }}">
    <span class="id">{{ s.short_id }}</span>
    {{ s.short_title }}
  </a>
  {% endfor %}
</div>
{% endif %}

<div class="status-strip">
  <span class="item"><span class="k">region</span><span class="v">{{ status.region }}</span></span>
  <span class="item"><span class="k">runtime</span><span class="v">{{ status.runtime }}</span></span>
  <span class="item"><span class="k">data plane</span><span class="v">{{ status.data_plane }}</span></span>
  <span class="item"><span class="k">dcf rules</span><span class="v">{{ status.dcf_rules }}</span></span>
  <span class="item"><span class="k">controller</span><span class="v">{{ status.controller_version }}</span></span>
  <span class="containment-toggle">
    <span>Containment</span>
    <span class="switch {{ 'off' if containment == 'off' else '' }}" data-toggle="containment"></span>
    <span class="label">{{ containment | upper }}</span>
  </span>
</div>

<div class="content" id="content">
  {{ body_content | safe }}
</div>

<div class="footer">
  <div>aviatrix ai attack simulation · AgentCore VCA · controller {{ status.controller_version }}</div>
  <div>
    <a href="https://github.com/AviatrixSystems/aviatrix-blueprints/blob/main/blueprints/agentcore-aws/" target="_blank" rel="noopener">terraform source</a>
  </div>
</div>

</body>
</html>
```

- [ ] **Step 4: Run the test**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_template_render.py::test_base_template_renders -v
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add blueprints/agentcore-aws/ui/templates/base.html blueprints/agentcore-aws/ui/tests/test_template_render.py
git commit -m "agentcore-aws ui: base template with header, picker, status strip, footer"
```

---

## Task 6: Scenario data loader and short-id derivation

**Files:**
- Create: `blueprints/agentcore-aws/ui/scenario_loader.py`
- Create: `blueprints/agentcore-aws/ui/tests/test_scenario_loader.py`

`scenarios.json` already exists (unchanged from current). We need a typed loader that derives a `short_id` (e.g., `LLM01`, `LLM05b`, `DRIFT`) and a `short_title` for the chip picker.

- [ ] **Step 1: Write the loader test**

`blueprints/agentcore-aws/ui/tests/test_scenario_loader.py`:

```python
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
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_scenario_loader.py -v 2>&1 | tail -10
```
Expected: ModuleNotFoundError.

- [ ] **Step 3: Write the loader**

`blueprints/agentcore-aws/ui/scenario_loader.py`:

```python
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
```

- [ ] **Step 4: Run the test**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_scenario_loader.py -v
```
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add blueprints/agentcore-aws/ui/scenario_loader.py blueprints/agentcore-aws/ui/tests/test_scenario_loader.py
git commit -m "agentcore-aws ui: scenario loader with short_id + short_title"
```

---

## Task 7: Static rule catalog (rules.json) and rules loader

**Files:**
- Create: `blueprints/agentcore-aws/ui/rules.json`
- Create: `blueprints/agentcore-aws/ui/rules_catalog.py`
- Create: `blueprints/agentcore-aws/ui/tests/test_rules_catalog.py`

In v1 we ship a hand-written `rules.json` that mirrors `dcf.tf` and `iam.tf`. (Task 16 wires up the terraform-side generator.) The fields here are the source of truth for what the rule block on each scenario card renders.

- [ ] **Step 1: Write the rule catalog test**

`blueprints/agentcore-aws/ui/tests/test_rules_catalog.py`:

```python
"""Tests for rules_catalog."""
from __future__ import annotations


def test_catalog_contains_all_referenced_rules():
    from ui.rules_catalog import load_catalog
    catalog = load_catalog()
    # Every DCF rule the scenarios reference must be in the catalog.
    expected = {
        "agentcore-vca-29-runtime-deny-supply-chain-ioc-github",
        "agentcore-vca-50-runtime-dns-exfil-deny",
        "agentcore-vca-100-runtime-default-deny",
        "agentcore-vca-vpc-mode-guardrail",
    }
    assert expected.issubset(catalog.keys())


def test_default_deny_rule_shape():
    from ui.rules_catalog import load_catalog
    rule = load_catalog()["agentcore-vca-100-runtime-default-deny"]
    assert rule["type"] == "dcf"
    assert rule["action"] == "DENY"
    assert rule["priority"] == 100
    assert rule["protocol"] == "ANY"
    assert "runtime-subnet" in rule["src_smart_groups"][0]


def test_iam_guardrail_shape():
    from ui.rules_catalog import load_catalog
    rule = load_catalog()["agentcore-vca-vpc-mode-guardrail"]
    assert rule["type"] == "iam"
    assert rule["effect"] == "DENY"
    assert "CreateAgentRuntime" in rule["action"]
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_rules_catalog.py -v 2>&1 | tail -10
```
Expected: ModuleNotFoundError or FileNotFoundError.

- [ ] **Step 3: Write rules.json**

`blueprints/agentcore-aws/ui/rules.json`:

```json
{
  "agentcore-vca-29-runtime-deny-supply-chain-ioc-github": {
    "type": "dcf",
    "name": "agentcore-vca-29-runtime-deny-supply-chain-ioc-github",
    "priority": 29,
    "action": "DENY",
    "protocol": "TCP",
    "src_smart_groups": ["runtime-subnet (10.50.10.0/24)"],
    "dst_smart_groups": ["github_hosts (FQDN: raw.githubusercontent.com, github.com)"],
    "web_groups": ["supply_chain_ioc_github (path patterns)"],
    "decrypt_policy": "DECRYPT_ALLOWED",
    "logging": true,
    "watch": false
  },
  "agentcore-vca-50-runtime-dns-exfil-deny": {
    "type": "dcf",
    "name": "agentcore-vca-50-runtime-dns-exfil-deny",
    "priority": 50,
    "action": "DENY",
    "protocol": "UDP",
    "port_ranges": ["53"],
    "src_smart_groups": ["runtime-subnet (10.50.10.0/24)"],
    "dst_smart_groups": ["any (catch-all)"],
    "decrypt_policy": null,
    "logging": true,
    "watch": false
  },
  "agentcore-vca-100-runtime-default-deny": {
    "type": "dcf",
    "name": "agentcore-vca-100-runtime-default-deny",
    "priority": 100,
    "action": "DENY",
    "protocol": "ANY",
    "src_smart_groups": ["runtime-subnet (10.50.10.0/24)"],
    "dst_smart_groups": ["any (catch-all)"],
    "decrypt_policy": null,
    "logging": true,
    "watch": false
  },
  "agentcore-vca-vpc-mode-guardrail": {
    "type": "iam",
    "name": "agentcore-vca-vpc-mode-guardrail",
    "effect": "DENY",
    "action": "bedrock-agentcore-control:CreateAgentRuntime",
    "resource": "arn:aws:bedrock-agentcore:*:*:runtime/*",
    "condition": "Null on bedrock-agentcore:subnets OR ForAnyValue:StringNotEquals on approved subnets",
    "attached_to": "platform-eng / ci-cd / human-admin roles"
  }
}
```

- [ ] **Step 4: Write rules_catalog.py**

`blueprints/agentcore-aws/ui/rules_catalog.py`:

```python
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
```

- [ ] **Step 5: Run the test**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_rules_catalog.py -v
```
Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add blueprints/agentcore-aws/ui/rules.json blueprints/agentcore-aws/ui/rules_catalog.py blueprints/agentcore-aws/ui/tests/test_rules_catalog.py
git commit -m "agentcore-aws ui: rule catalog with DCF and IAM entries"
```

---

## Task 8: Simulation payloads (precomputed "without Aviatrix" results)

**Files:**
- Create: `blueprints/agentcore-aws/ui/simulation.py`
- Create: `blueprints/agentcore-aws/ui/tests/test_simulation_payloads.py`

Per spec § Containment toggle (v1), when containment=off the server returns a precomputed breach payload for each scenario. The shape matches what the live runtime returns plus the augmentation fields the UI adds.

- [ ] **Step 1: Write the test**

`blueprints/agentcore-aws/ui/tests/test_simulation_payloads.py`:

```python
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
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_simulation_payloads.py -v 2>&1 | tail -10
```
Expected: ModuleNotFoundError.

- [ ] **Step 3: Write simulation.py**

`blueprints/agentcore-aws/ui/simulation.py`:

```python
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
```

- [ ] **Step 4: Run the test**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_simulation_payloads.py -v
```
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add blueprints/agentcore-aws/ui/simulation.py blueprints/agentcore-aws/ui/tests/test_simulation_payloads.py
git commit -m "agentcore-aws ui: precomputed simulation payloads for 5 DCF scenarios"
```

---

## Task 9: Runtime client wrapper (boto3 bedrock-agentcore invoke)

**Files:**
- Create: `blueprints/agentcore-aws/ui/runtime_client.py`
- Create: `blueprints/agentcore-aws/ui/tests/test_runtime_client.py`

Thin wrapper around `bedrock-agentcore:InvokeAgentRuntime`. Owns the JSON encoding / decoding and the session ID generation. Tests use `botocore.stub.Stubber`.

- [ ] **Step 1: Write the test**

`blueprints/agentcore-aws/ui/tests/test_runtime_client.py`:

```python
"""Tests for the runtime_client wrapper."""
from __future__ import annotations

import io
import json
import os

import boto3
import pytest
from botocore.stub import Stubber


@pytest.fixture()
def stubbed_client(monkeypatch):
    monkeypatch.setenv("AWS_REGION", "us-east-2")
    monkeypatch.setenv("AGENTCORE_RUNTIME_ARN",
                       "arn:aws:bedrock-agentcore:us-east-2:123456789012:runtime/test-runtime")
    from ui import runtime_client
    # Replace the module-level client with a stubbed one
    real = boto3.client("bedrock-agentcore", region_name="us-east-2")
    runtime_client._client = real
    return real


def test_invoke_round_trip(stubbed_client):
    """Stubber asserts the call shape; we don't assert the session id since
    it's time + random and would require freezing both. The boto3 Stubber's
    default behavior (no expected_params) accepts any kwargs."""
    from ui.runtime_client import invoke
    with Stubber(stubbed_client) as stubber:
        body = io.BytesIO(json.dumps({"ok": True, "steps": []}).encode())
        stubber.add_response(
            "invoke_agent_runtime",
            {"response": body, "contentType": "application/json", "statusCode": 200},
        )
        result, elapsed = invoke({"mode": "scenario", "scenario": "llm01_prompt_inject_exfil"})
    assert result["ok"] is True
    assert "steps" in result
    assert elapsed >= 0


def test_invoke_returns_error_dict_when_runtime_arn_unset(monkeypatch):
    monkeypatch.delenv("AGENTCORE_RUNTIME_ARN", raising=False)
    from ui import runtime_client
    runtime_client._client = None  # force fresh init
    result, elapsed = runtime_client.invoke({"mode": "scenario", "scenario": "x"})
    assert result["ok"] is False
    assert "AGENTCORE_RUNTIME_ARN" in result["error"]
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_runtime_client.py -v 2>&1 | tail -10
```
Expected: ModuleNotFoundError.

- [ ] **Step 3: Write runtime_client.py**

`blueprints/agentcore-aws/ui/runtime_client.py`:

```python
"""boto3 wrapper around bedrock-agentcore:InvokeAgentRuntime.

Returns (result_dict, elapsed_seconds). On AWS errors or missing
configuration, returns a dict with ok=False and a short error string —
never raises out of the boundary.
"""
from __future__ import annotations

import json
import os
import secrets
import time
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

_client: Any = None


def _get_client() -> Any:
    global _client
    if _client is None:
        region = os.environ.get("AWS_REGION", "us-east-2")
        _client = boto3.client(
            "bedrock-agentcore",
            region_name=region,
            config=Config(connect_timeout=10, read_timeout=180,
                          retries={"max_attempts": 1}),
        )
    return _client


def invoke(payload: dict[str, Any]) -> tuple[dict[str, Any], float]:
    arn = os.environ.get("AGENTCORE_RUNTIME_ARN", "")
    if not arn or arn.startswith("UNSET"):
        return ({"ok": False, "error": "AGENTCORE_RUNTIME_ARN not configured"}, 0.0)

    sid = f"ui-{int(time.time())}-{secrets.token_hex(16)}"
    start = time.perf_counter()
    try:
        resp = _get_client().invoke_agent_runtime(
            agentRuntimeArn=arn,
            runtimeSessionId=sid,
            payload=json.dumps(payload).encode(),
        )
        raw = resp["response"].read()
        result = json.loads(raw) if raw else {"ok": False, "error": "empty runtime response"}
    except (BotoCoreError, ClientError) as e:
        result = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    except json.JSONDecodeError as e:
        result = {"ok": False, "error": f"runtime returned non-JSON: {e}"}
    return (result, time.perf_counter() - start)
```

- [ ] **Step 4: Run the test**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_runtime_client.py -v
```
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add blueprints/agentcore-aws/ui/runtime_client.py blueprints/agentcore-aws/ui/tests/test_runtime_client.py
git commit -m "agentcore-aws ui: runtime_client wrapper with boundary error handling"
```

---

## Task 10: Attack-flow and rule-block partials

**Files:**
- Create: `blueprints/agentcore-aws/ui/templates/partials/flow.html`
- Create: `blueprints/agentcore-aws/ui/templates/partials/rule_block.html`
- Create: `blueprints/agentcore-aws/ui/templates/partials/evidence.html`

These three partials render the live-pane contents from the runtime payload.

- [ ] **Step 1: Add render tests for the three partials**

Append to `blueprints/agentcore-aws/ui/tests/test_template_render.py`:

```python
def test_flow_partial_renders_step_types(env):
    tmpl = env.get_template("partials/flow.html")
    out = tmpl.render(steps=[
        {"label": "Attacker prompt", "outcome": "info", "detail": "x"},
        {"label": "Tool", "outcome": "ok", "detail": "y"},
        {"label": "Aviatrix Gateway", "outcome": "permitted", "detail": "rule -100-"},
        {"label": "Egress", "outcome": "blocked", "detail": "z"},
    ])
    assert "Attacker prompt" in out
    assert "Aviatrix Gateway" in out
    assert "node info" in out  # info-class node present
    assert "node ok" in out


def test_rule_block_dcf(env):
    tmpl = env.get_template("partials/rule_block.html")
    rule = {
        "type": "dcf", "name": "test-rule", "priority": 100, "action": "DENY",
        "protocol": "ANY",
        "src_smart_groups": ["runtime-subnet"],
        "dst_smart_groups": ["any"],
        "decrypt_policy": None, "logging": True, "watch": False,
    }
    out = tmpl.render(rule=rule)
    assert "test-rule" in out
    assert "DENY" in out
    assert "DCF" in out


def test_rule_block_iam(env):
    tmpl = env.get_template("partials/rule_block.html")
    rule = {
        "type": "iam", "name": "vpc-mode-guardrail", "effect": "DENY",
        "action": "bedrock-agentcore-control:CreateAgentRuntime",
        "resource": "arn:…", "condition": "Null on subnets",
        "attached_to": "platform-eng",
    }
    out = tmpl.render(rule=rule)
    assert "vpc-mode-guardrail" in out
    assert "IAM" in out
    assert "CreateAgentRuntime" in out


def test_evidence_partial(env):
    tmpl = env.get_template("partials/evidence.html")
    out = tmpl.render(evidence={
        "match_attribute": "destination SNI evil.attacker.example",
        "matched_group": "dst = any (default-deny fallback)",
        "enforcement_point": "AgentCore spoke GW (L4 stateful)",
        "decryption": "not required",
        "termination": "TLS handshake closed pre-egress",
        "audit": "FlowIQ entry: action=DENY",
    })
    assert "Control evidence" in out
    assert "evil.attacker.example" in out
```

- [ ] **Step 2: Run the tests (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_template_render.py -v 2>&1 | tail -10
```
Expected: TemplateNotFound for the three partials.

- [ ] **Step 3: Write flow.html**

`blueprints/agentcore-aws/ui/templates/partials/flow.html`:

```html
<style>
  .flow { display: flex; align-items: stretch; gap: 0; flex-wrap: wrap; row-gap: 14px; margin: 4px 0 20px; }
  .node { position: relative; display: flex; flex-direction: column; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; padding: 10px 12px; min-width: 140px; max-width: 180px; flex: 1 1 140px; color: #fff; }
  .node + .node { margin-left: 30px; }
  .node + .node::before { content: ""; position: absolute; left: -30px; top: 50%; width: 30px; height: 2px; background: rgba(255,255,255,0.18); transform: translateY(-1px); }
  .node + .node::after { content: ""; position: absolute; left: -8px; top: 50%; border: 5px solid transparent; border-left-color: rgba(255,255,255,0.4); transform: translateY(-50%); }
  .node .marker { display: inline-flex; align-items: center; justify-content: center; width: 22px; height: 22px; border-radius: 50%; font-weight: 700; font-size: 12px; color: #fff; margin-bottom: 6px; }
  .node .lbl { font-family: 'Sora', sans-serif; font-weight: 600; font-size: 11px; line-height: 1.3; margin-bottom: 4px; }
  .node .det { font-size: 10px; color: rgba(255,255,255,0.6); line-height: 1.4; font-family: ui-monospace, monospace; }
  .node.info .marker { background: rgba(255,255,255,0.15); color: #d4d4d8; }
  .node.ok { background: rgba(34,197,94,0.06); border-color: rgba(34,197,94,0.25); }
  .node.ok .marker { background: #22C55E; color: #00170a; }
  .node.blocked { background: rgba(220,38,38,0.08); border-color: rgba(220,38,38,0.35); opacity: 0.55; }
  .node.blocked .marker { background: #DC2626; color: #fff; }
  .node.blocked .lbl { text-decoration: line-through; }
  .node.permitted { background: rgba(226,68,2,0.07); border: 1.5px solid #E24402; box-shadow: 0 0 0 4px rgba(226,68,2,0.08); min-width: 160px; }
  .node.permitted .marker { background: #E24402; color: #fff; }
  .node.permitted .lbl { color: #FA6B1E; }
  .node.permitted .det { color: rgba(255,170,140,0.85); }
</style>

<div class="flow">
  {% for step in steps %}
  <div class="node {{ step.outcome }}">
    <span class="marker">
      {%- if step.outcome == 'ok' -%}&#x2713;
      {%- elif step.outcome == 'blocked' -%}&#x2715;
      {%- elif step.outcome == 'permitted' -%}&#x2715;
      {%- else -%}&middot;
      {%- endif -%}
    </span>
    <div class="lbl">{{ step.label }}</div>
    {% if step.detail is mapping %}
      <div class="det">{{ step.detail | tojson }}</div>
    {% else %}
      <div class="det">{{ step.detail }}</div>
    {% endif %}
  </div>
  {% endfor %}
</div>
```

- [ ] **Step 4: Write rule_block.html**

`blueprints/agentcore-aws/ui/templates/partials/rule_block.html`:

```html
<style>
  .rule-block { background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.08); border-radius: 8px; padding: 14px 16px; margin-bottom: 14px; }
  .rule-block .pane-h { font-family: 'Sora', sans-serif; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: #FA6B1E; margin: 0 0 10px; }
  .rule-block .rule-name { font-family: 'Sora', sans-serif; font-weight: 600; font-size: 13px; color: #fff; }
  .rule-block .rule-name code { color: #FA6B1E; font-family: ui-monospace, monospace; }
  .rule-block .type-pill { display: inline-block; font-family: 'Sora', sans-serif; font-weight: 600; font-size: 9px; padding: 2px 7px; border-radius: 3px; letter-spacing: 0.06em; margin-left: 8px; vertical-align: middle; }
  .rule-block .type-pill.dcf { background: rgba(250,107,30,0.12); color: #FA6B1E; }
  .rule-block .type-pill.iam { background: rgba(122,93,220,0.15); color: #C4B5FD; }
  .rule-grid { display: grid; grid-template-columns: 130px 1fr; gap: 4px 14px; margin-top: 10px; font-family: ui-monospace, monospace; font-size: 11px; }
  .rule-grid .k { color: rgba(255,255,255,0.5); }
  .rule-grid .v { color: #d4d4d8; }
  .rule-grid .v.deny { color: #FCA5A5; font-weight: 600; }
  .rule-grid .v code { color: #FA6B1E; }
</style>

<div class="pane-h">{% if rule.type == 'iam' %}IAM policy{% else %}DCF rule{% endif %}</div>
<div class="rule-block">
  <div class="rule-name">
    <code>{{ rule.name }}</code>
    <span class="type-pill {{ rule.type }}">{{ rule.type | upper }}</span>
  </div>
  <div class="rule-grid">
  {% if rule.type == 'dcf' %}
    <span class="k">priority</span><span class="v"><code>{{ rule.priority }}</code></span>
    <span class="k">action</span><span class="v deny">{{ rule.action }}</span>
    <span class="k">protocol</span><span class="v"><code>{{ rule.protocol }}</code></span>
    {% if rule.port_ranges %}<span class="k">port</span><span class="v"><code>{{ rule.port_ranges | join(', ') }}</code></span>{% endif %}
    <span class="k">src_smart_groups</span><span class="v">{% for g in rule.src_smart_groups %}<code>{{ g }}</code>{% if not loop.last %}, {% endif %}{% endfor %}</span>
    <span class="k">dst_smart_groups</span><span class="v">{% for g in rule.dst_smart_groups %}<code>{{ g }}</code>{% if not loop.last %}, {% endif %}{% endfor %}</span>
    {% if rule.web_groups %}<span class="k">web_groups</span><span class="v">{% for g in rule.web_groups %}<code>{{ g }}</code>{% if not loop.last %}, {% endif %}{% endfor %}</span>{% endif %}
    <span class="k">decrypt_policy</span><span class="v">{{ rule.decrypt_policy or '(none — SNI/L4 only)' }}</span>
    <span class="k">logging</span><span class="v">{{ 'enabled' if rule.logging else 'disabled' }}</span>
    <span class="k">watch</span><span class="v">{{ rule.watch | string }}</span>
  {% else %}
    <span class="k">effect</span><span class="v deny">{{ rule.effect }}</span>
    <span class="k">action</span><span class="v"><code>{{ rule.action }}</code></span>
    <span class="k">resource</span><span class="v"><code>{{ rule.resource }}</code></span>
    <span class="k">condition</span><span class="v">{{ rule.condition }}</span>
    <span class="k">attached_to</span><span class="v">{{ rule.attached_to }}</span>
  {% endif %}
  </div>
</div>
```

- [ ] **Step 5: Write evidence.html**

`blueprints/agentcore-aws/ui/templates/partials/evidence.html`:

```html
<style>
  .evidence-block { background: rgba(122,93,220,0.06); border: 1px solid rgba(122,93,220,0.25); border-radius: 8px; padding: 14px 16px; }
  .evidence-block .pane-h { font-family: 'Sora', sans-serif; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: #B5A3F2; margin: 0 0 8px; }
  .evidence-grid { display: grid; grid-template-columns: 140px 1fr; gap: 6px 14px; font-family: ui-monospace, monospace; font-size: 11px; }
  .evidence-grid .k { color: rgba(255,255,255,0.55); text-transform: lowercase; }
  .evidence-grid .v { color: #d4d4d8; }
  .evidence-grid .v code { color: #FA6B1E; }
</style>

<div class="evidence-block">
  <div class="pane-h">Control evidence</div>
  <div class="evidence-grid">
    {% for k, v in evidence.items() %}
    <span class="k">{{ k | replace('_', ' ') }}</span><span class="v">{{ v }}</span>
    {% endfor %}
  </div>
</div>
```

- [ ] **Step 6: Run all template tests**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_template_render.py -v
```
Expected: 5 passed (base + 4 partials).

- [ ] **Step 7: Commit**

```bash
git add blueprints/agentcore-aws/ui/templates/partials blueprints/agentcore-aws/ui/tests/test_template_render.py
git commit -m "agentcore-aws ui: attack-flow, rule-block, and evidence partials"
```

---

## Task 11: Scenario template (two-pane card)

**Files:**
- Create: `blueprints/agentcore-aws/ui/templates/scenario.html`

The locked layout from `research/mockups/02-scenario-card-llm01.html`. Inherits from base.html via the `body_content` slot.

- [ ] **Step 1: Add the scenario.html render test**

Append to `blueprints/agentcore-aws/ui/tests/test_template_render.py`:

```python
def test_scenario_template_renders_with_result(env):
    tmpl = env.get_template("scenario.html")
    scenario = {
        "id": "llm01_prompt_inject_exfil",
        "short_id": "LLM01",
        "title": "Prompt Injection → Tool-Abuse Exfil",
        "owasp": "LLM01 + LLM07", "mitre": "AML.T0051",
        "setup": "Agent has a sanctioned tool.",
        "attack": "Prompt asks for exfil.",
        "expected_behavior": "DCF -100- closes the egress.",
        "control": "rule -100-",
    }
    result = {
        "ok": True, "verdict": "CONTAINED", "steps": [
            {"label": "Attacker prompt", "outcome": "info", "detail": "x"},
        ],
        "rule_definition": {
            "type": "dcf", "name": "rule-x", "priority": 100, "action": "DENY",
            "protocol": "ANY", "src_smart_groups": ["s"], "dst_smart_groups": ["d"],
            "decrypt_policy": None, "logging": True, "watch": False,
        },
        "control_evidence": {"match_attribute": "x"},
        "elapsed_seconds": 2.1,
        "simulated": False,
    }
    out = tmpl.render(scenario=scenario, result=result, index=1, total=6)
    assert "Prompt Injection" in out
    assert "CONTAINED" in out
    assert "SCENARIO 1 of 6" in out


def test_scenario_template_renders_without_result(env):
    """Pre-Run: no result yet, live pane shows a Run button only."""
    tmpl = env.get_template("scenario.html")
    scenario = {
        "id": "x", "short_id": "X", "title": "T",
        "owasp": "", "mitre": "", "setup": "", "attack": "", "expected_behavior": "",
    }
    out = tmpl.render(scenario=scenario, result=None, index=1, total=6)
    assert "Run scenario" in out
    assert "CONTAINED" not in out
```

- [ ] **Step 2: Run tests (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_template_render.py -v 2>&1 | tail -10
```
Expected: TemplateNotFound for scenario.html.

- [ ] **Step 3: Write scenario.html**

`blueprints/agentcore-aws/ui/templates/scenario.html`:

```html
<style>
  .scenario-block { background: #fff; border: 1px solid #e7e0d4; border-radius: 16px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
  .scn-head { padding: 18px 22px; border-bottom: 1px solid #e7e0d4; }
  .scn-eyebrow { font-family: 'Sora'; font-weight: 600; font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; color: #E24402; margin-bottom: 4px; }
  .scn-title { font-family: 'Sora'; font-weight: 700; font-size: 22px; margin: 0; color: #181818; }
  .scn-meta { font-size: 12px; color: #6b7280; margin-top: 4px; font-family: ui-monospace, monospace; }
  .panes { display: grid; grid-template-columns: 0.9fr 1.4fr; gap: 0; }
  .story-pane { background: #fff; padding: 22px; border-right: 1px solid #e7e0d4; }
  .live-pane { background: #030712; color: #fff; padding: 22px; min-height: 220px; }
  .story-pane .pane-h { font-family: 'Sora'; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: #6b7280; margin: 0 0 10px; }
  .story-pane p { font-size: 13px; line-height: 1.55; margin: 0 0 10px; color: #374151; }
  .story-pane b { color: #181818; }
  .story-pane code { font-family: ui-monospace, monospace; font-size: 12px; }
  .verdict-row { display: flex; align-items: center; gap: 14px; margin-bottom: 18px; }
  .verdict { padding: 5px 12px; border-radius: 4px; font-family: 'Sora'; font-weight: 700; font-size: 11px; letter-spacing: 0.04em; }
  .verdict.contained { background: #22C55E; color: #00170a; }
  .verdict.breach { background: #DC2626; color: #fff; }
  .verdict-row .rt { font-size: 11px; color: rgba(255,255,255,0.55); font-family: ui-monospace, monospace; }
  .verdict-row .sim-ribbon { background: rgba(250,107,30,0.18); color: #FA6B1E; font-family: 'Sora'; font-weight: 700; font-size: 10px; letter-spacing: 0.08em; padding: 3px 8px; border-radius: 4px; }
  .runbtn { display: inline-block; padding: 9px 20px; border-radius: 6px; background: #E24402; color: #fff; font-family: 'Sora'; font-weight: 600; font-size: 12px; margin-top: 18px; cursor: pointer; border: none; }
  .runbtn:hover { background: #c93a01; }
  .pre-run-pane { display: flex; align-items: center; justify-content: center; min-height: 160px; flex-direction: column; gap: 8px; color: rgba(255,255,255,0.55); }
  .iam-note { background: rgba(122,93,220,0.07); border-left: 3px solid #7A5DDC; padding: 8px 12px; border-radius: 0 4px 4px 0; font-size: 11px; color: rgba(255,255,255,0.85); margin-bottom: 14px; }
</style>

<div class="scenario-block">
  <div class="scn-head">
    <div class="scn-eyebrow">SCENARIO {{ index }} of {{ total }}{% if scenario.owasp %} · {{ scenario.owasp }}{% endif %}</div>
    <h3 class="scn-title">{{ scenario.title }}</h3>
    {% if scenario.mitre %}<div class="scn-meta">{{ scenario.mitre }}</div>{% endif %}
  </div>
  <div class="panes">
    <div class="story-pane">
      <div class="pane-h">Attack path</div>
      {% if scenario.setup %}<p><b>Setup.</b> {{ scenario.setup }}</p>{% endif %}
      {% if scenario.attack %}<p><b>Attack.</b> {{ scenario.attack }}</p>{% endif %}
      {% if scenario.expected_behavior %}<p><b>Containment.</b> {{ scenario.expected_behavior }}</p>{% endif %}
    </div>
    <div class="live-pane" id="live-pane-{{ scenario.id }}">
      {% if result %}
        {% if result.simulated and scenario.id == 'drift_public_mode' %}
          <div class="iam-note">IAM is a separate enforcement plane; this toggle's scope is DCF only. Drift remains contained.</div>
        {% endif %}
        <div class="verdict-row">
          <span class="verdict {{ 'contained' if result.ok else 'breach' }}">{{ 'CONTAINED' if result.ok else 'BREACH' }}</span>
          {% if result.simulated %}<span class="sim-ribbon">SIMULATED</span>{% endif %}
          <span class="rt">round-trip {{ '%.1f'|format(result.elapsed_seconds or 0) }}s</span>
        </div>

        {% if result.steps %}
        <div style="font-family:'Sora';font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:0.06em;color:#FA6B1E;margin:0 0 10px;">Attack flow</div>
        {% include 'partials/flow.html' %}
        {% endif %}

        {% if result.rule_definition %}
        {% set rule = result.rule_definition %}
        {% include 'partials/rule_block.html' %}
        {% endif %}

        {% if result.control_evidence %}
        {% set evidence = result.control_evidence %}
        {% include 'partials/evidence.html' %}
        {% endif %}

        <button class="runbtn"
                hx-post="/api/run/{{ scenario.id }}"
                hx-vals='{"containment": "{{ containment | default('on') }}"}'
                hx-target="#live-pane-{{ scenario.id }}"
                hx-swap="innerHTML">Run scenario again</button>
      {% else %}
        <div class="pre-run-pane">
          <span style="font-family:'Sora';font-weight:600;font-size:12px;letter-spacing:0.04em;">Press Run to execute this attack against the live runtime.</span>
          <button class="runbtn"
                  hx-post="/api/run/{{ scenario.id }}"
                  hx-vals='{"containment": "{{ containment | default('on') }}"}'
                  hx-target="#live-pane-{{ scenario.id }}"
                  hx-swap="innerHTML">Run scenario</button>
        </div>
      {% endif %}
    </div>
  </div>
</div>
```

- [ ] **Step 4: Run tests**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_template_render.py -v
```
Expected: all template tests pass.

- [ ] **Step 5: Commit**

```bash
git add blueprints/agentcore-aws/ui/templates/scenario.html blueprints/agentcore-aws/ui/tests/test_template_render.py
git commit -m "agentcore-aws ui: two-pane scenario template (story + live pane)"
```

---

## Task 12: GET /s/{id} route, full-page render

**Files:**
- Modify: `blueprints/agentcore-aws/ui/app.py`

- [ ] **Step 1: Add a route test for GET /s/{id}**

Append to `blueprints/agentcore-aws/ui/tests/test_routes.py`:

```python
def test_root_redirects_to_first_scenario(client):
    r = client.get("/", follow_redirects=False)
    assert r.status_code == 302
    assert "/s/llm01_prompt_inject_exfil" in r.headers["location"]


def test_scenario_page_renders(client):
    r = client.get("/s/llm01_prompt_inject_exfil")
    assert r.status_code == 200
    assert "Prompt Injection" in r.text
    assert "AI ATTACK SIMULATION" in r.text


def test_scenario_page_404_for_unknown(client):
    r = client.get("/s/no-such-scenario")
    assert r.status_code == 404


def test_scenario_fragment_returns_card_only(client):
    """The /fragment route is HTMX's target for chip-swap. It returns the
    scenario card body without the page chrome (no header / footer / picker)."""
    r = client.get("/s/llm02_dns_exfil/fragment")
    assert r.status_code == 200
    assert "DNS" in r.text
    # No chrome in a fragment response:
    assert "AI ATTACK SIMULATION" not in r.text
    assert "<footer" not in r.text and "<nav" not in r.text
```

- [ ] **Step 2: Run tests (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_routes.py -v 2>&1 | tail -15
```
Expected: redirect missing, 404 for the scenario, etc.

- [ ] **Step 3: Add the routes to app.py**

Rewrite `blueprints/agentcore-aws/ui/app.py` to its full form:

```python
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
    return templates.TemplateResponse("base.html", {
        "request": request,
        "page_title": scenario["short_title"],
        "scenarios": load_scenarios(),
        "active_scenario_id": scenario_id,
        "active_nav": "scenarios",
        "status": _status(),
        "containment": containment,
        "body_content": card,
    })


@app.get("/s/{scenario_id}/fragment", response_class=HTMLResponse)
def scenario_fragment(scenario_id: str, containment: str = "on"):
    """HTMX target for picker chip clicks — returns just the card."""
    _, card = _render_scenario_card(scenario_id, containment)
    return HTMLResponse(card)
```

- [ ] **Step 4: Run tests**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_routes.py -v
```
Expected: all pass.

- [ ] **Step 5: Manual sanity in browser**

```bash
cd blueprints/agentcore-aws
.venv/bin/uvicorn ui.app:app --port 18501 &
sleep 1
curl -sI http://127.0.0.1:18501/ | head -3
curl -s http://127.0.0.1:18501/s/llm01_prompt_inject_exfil | head -30
kill %1 2>/dev/null
```
Expected: `/` returns 302; `/s/llm01_...` returns HTML with the page chrome and the LLM01 story pane.

- [ ] **Step 6: Commit**

```bash
git add blueprints/agentcore-aws/ui/app.py blueprints/agentcore-aws/ui/tests/test_routes.py
git commit -m "agentcore-aws ui: GET /s/{id} route, root redirect, status strip"
```

---

## Task 13: POST /api/run/{id} route — live runtime path (containment=on)

**Files:**
- Modify: `blueprints/agentcore-aws/ui/app.py`
- Create: `blueprints/agentcore-aws/ui/evidence_builder.py`

- [ ] **Step 1: Write tests for /api/run/{id} with mocked runtime**

Append to `blueprints/agentcore-aws/ui/tests/test_routes.py`:

```python
def test_run_live_path_returns_html_fragment(client, monkeypatch):
    """containment=on calls runtime_client.invoke and returns the rendered fragment."""
    from ui import runtime_client

    def fake_invoke(payload):
        return ({
            "ok": True,
            "title": "LLM01",
            "steps": [
                {"label": "Attacker prompt", "outcome": "info", "detail": "x"},
                {"label": "Egress to evil.attacker.example", "outcome": "blocked", "detail": "URLError"},
            ],
            "dcf_rule": "agentcore-vca-100-runtime-default-deny",
        }, 2.1)

    monkeypatch.setattr(runtime_client, "invoke", fake_invoke)

    r = client.post("/api/run/llm01_prompt_inject_exfil", data={"containment": "on"})
    assert r.status_code == 200
    assert "CONTAINED" in r.text
    assert "Aviatrix Gateway" in r.text  # inserted between last-ok and first-blocked
    assert "agentcore-vca-100-runtime-default-deny" in r.text
```

- [ ] **Step 2: Run test (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_routes.py::test_run_live_path_returns_html_fragment -v 2>&1 | tail -10
```
Expected: 404 or other failure.

- [ ] **Step 3: Write evidence_builder.py**

The augmentation layer: insert the Aviatrix Gateway / IAM enforcement node, look up rule_definition, build control_evidence.

`blueprints/agentcore-aws/ui/evidence_builder.py`:

```python
"""Augment runtime payloads with rule_definition, control_evidence, and the
synthetic enforcement node between the last permitted step and the first blocked step."""
from __future__ import annotations

from typing import Any

from ui.rules_catalog import load_catalog


def augment(payload: dict[str, Any], simulated: bool, elapsed: float) -> dict[str, Any]:
    rule_name = payload.get("dcf_rule")
    catalog = load_catalog()
    rule = catalog.get(rule_name)

    steps: list[dict[str, Any]] = list(payload.get("steps") or [])
    if not simulated:
        # Insert an "Aviatrix Gateway" node between the last non-blocked step
        # and the first blocked step (if any).
        steps = _insert_enforcement_node(steps, rule)

    payload["steps"] = steps
    payload["elapsed_seconds"] = elapsed
    payload["simulated"] = simulated
    if rule:
        payload["rule_definition"] = rule
    payload["control_evidence"] = _build_evidence(payload, rule, simulated)
    payload["verdict"] = "CONTAINED" if payload.get("ok") else "BREACH"
    return payload


def _insert_enforcement_node(steps: list[dict[str, Any]], rule: dict[str, Any] | None) -> list[dict[str, Any]]:
    block_idx = next((i for i, s in enumerate(steps) if s.get("outcome") in ("blocked", "CONTAINMENT FAILED")), None)
    if block_idx is None or rule is None:
        return steps

    if rule.get("type") == "iam":
        node = {
            "label": "IAM guardrail policy",
            "outcome": "permitted",  # styled as the orange enforcement node
            "detail": rule["name"],
        }
    else:
        node = {
            "label": "Aviatrix Gateway",
            "outcome": "permitted",
            "detail": f"policy {rule['name']} · action {rule.get('action', 'DENY')}",
        }
    return steps[:block_idx] + [node] + steps[block_idx:]


def _build_evidence(payload: dict[str, Any], rule: dict[str, Any] | None, simulated: bool) -> dict[str, str]:
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
    # DCF
    if simulated:
        return {
            "match_attribute": "n/a — Aviatrix policy was overridden to PERMIT in this simulation",
            "matched_group": f"src = {rule['src_smart_groups'][0]}, dst = {rule['dst_smart_groups'][0]}",
            "enforcement_point": "AgentCore spoke GW (no decision — pass-through)",
            "decryption": rule.get("decrypt_policy") or "not configured",
            "termination": "no termination — egress completed",
            "audit": f"FlowIQ entry: action=PERMIT (simulated), rule={rule['name']}",
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
    # Pull from the blocked step's label/detail. Tight summarizer; the live UI
    # will refine these in v2 once we wire FlowIQ.
    last = next((s for s in reversed(payload.get("steps", [])) if s.get("outcome") in ("blocked", "CONTAINMENT FAILED")), None)
    if not last:
        return "(unavailable)"
    return last.get("label", "(unavailable)")
```

- [ ] **Step 4: Add the route to app.py**

Append to `blueprints/agentcore-aws/ui/app.py`:

```python
from fastapi import Form
from ui import runtime_client
from ui.evidence_builder import augment
from ui.simulation import SIMULATED_PAYLOADS


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
        # Drift uses a local handler — added in Task 14.
        raise HTTPException(status_code=501, detail="drift handler not wired yet")

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
        index=1, total=6,  # not used inside the fragment beyond header — keep static
        containment=containment,
    )
    # Return just the live-pane innerHTML — htmx swaps it in.
    # The scenario.html renders the full card; we extract just the live-pane subtree.
    # For simplicity, render a dedicated fragment template instead.
    return HTMLResponse(_extract_live_pane(fragment))


def _extract_live_pane(full_card_html: str) -> str:
    # Pull just the contents of <div class="live-pane" id="live-pane-...">…</div>.
    # We can do this with simple string ops because scenario.html structure is known.
    marker_open = 'class="live-pane"'
    open_idx = full_card_html.find(marker_open)
    if open_idx < 0:
        return full_card_html
    start = full_card_html.find(">", open_idx) + 1
    # Find the matching </div> — naive count of <div / </div from start.
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
    return full_card_html[start:pos - 6]  # strip the closing </div>
```

(The `_extract_live_pane` helper is intentionally simple — DOM parsing is overkill here. If this proves brittle we'll move to a dedicated `live_pane.html` partial in a follow-up; for now it tests cleanly.)

- [ ] **Step 5: Run all tests**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests -v
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add blueprints/agentcore-aws/ui/app.py blueprints/agentcore-aws/ui/evidence_builder.py blueprints/agentcore-aws/ui/tests/test_routes.py
git commit -m "agentcore-aws ui: POST /api/run/{id} with evidence builder + enforcement node"
```

---

## Task 14: Drift handler

**Files:**
- Create: `blueprints/agentcore-aws/ui/drift_handler.py`
- Create: `blueprints/agentcore-aws/ui/tests/test_drift_handler.py`
- Modify: `blueprints/agentcore-aws/ui/app.py`

The Drift scenario runs entirely in the UI server (calling `bedrock-agentcore-control:CreateAgentRuntime`). Same as the current Streamlit's `render_drift_card`.

- [ ] **Step 1: Write the drift handler test**

`blueprints/agentcore-aws/ui/tests/test_drift_handler.py`:

```python
"""Tests for drift_handler — boto3 mocked."""
from __future__ import annotations

import os
import boto3
import pytest
from botocore.stub import Stubber


@pytest.fixture()
def env(monkeypatch):
    monkeypatch.setenv("AWS_REGION", "us-east-2")
    monkeypatch.setenv("AGENTCORE_RUNTIME_ROLE_ARN", "arn:aws:iam::123:role/test")
    monkeypatch.setenv("AGENTCORE_AGENT_IMAGE_URI", "123.dkr.ecr.us-east-2.amazonaws.com/test:latest")


def test_drift_handler_contained_on_access_denied(env):
    from ui import drift_handler
    real = boto3.client("bedrock-agentcore-control", region_name="us-east-2")
    drift_handler._client = real
    with Stubber(real) as stubber:
        stubber.add_client_error(
            "create_agent_runtime",
            service_error_code="AccessDeniedException",
            service_message="not authorized",
        )
        result, elapsed = drift_handler.attempt_public_runtime_create()
    assert result["ok"] is True  # CONTAINED
    assert result["dcf_rule"] == "agentcore-vca-vpc-mode-guardrail"
```

- [ ] **Step 2: Run test (expect failure)**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests/test_drift_handler.py -v 2>&1 | tail -10
```
Expected: ModuleNotFoundError.

- [ ] **Step 3: Write drift_handler.py**

`blueprints/agentcore-aws/ui/drift_handler.py`:

```python
"""Drift scenario handler. Calls bedrock-agentcore-control:CreateAgentRuntime
with networkMode=PUBLIC and expects AccessDeniedException from the IAM guardrail."""
from __future__ import annotations

import os
import time
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

_client: Any = None


def _get_client() -> Any:
    global _client
    if _client is None:
        region = os.environ.get("AWS_REGION", "us-east-2")
        _client = boto3.client(
            "bedrock-agentcore-control",
            region_name=region,
            config=Config(connect_timeout=5, read_timeout=30),
        )
    return _client


def attempt_public_runtime_create() -> tuple[dict[str, Any], float]:
    role_arn = os.environ.get("AGENTCORE_RUNTIME_ROLE_ARN", "")
    image_uri = os.environ.get("AGENTCORE_AGENT_IMAGE_URI", "")
    name = f"drift_demo_{int(time.time())}"
    start = time.perf_counter()
    try:
        _get_client().create_agent_runtime(
            agentRuntimeName=name,
            agentRuntimeArtifact={"containerConfiguration": {"containerUri": image_uri}},
            roleArn=role_arn,
            networkConfiguration={"networkMode": "PUBLIC"},
            protocolConfiguration={"serverProtocol": "HTTP"},
        )
        elapsed = time.perf_counter() - start
        return ({
            "ok": False,  # BREACH — runtime was created
            "title": "Drift — PUBLIC Mode Runtime Created (BREACH)",
            "dcf_rule": "agentcore-vca-vpc-mode-guardrail",
            "steps": [
                {"label": "CreateAgentRuntime request", "outcome": "info",
                 "detail": f"networkMode=PUBLIC, name={name}"},
                {"label": "IAM guardrail evaluation", "outcome": "ok",
                 "detail": "request permitted (BREACH)"},
                {"label": "PUBLIC-mode runtime provisioned", "outcome": "ok",
                 "detail": "runtime exists outside DCF visibility"},
            ],
        }, elapsed)
    except ClientError as e:
        elapsed = time.perf_counter() - start
        code = e.response.get("Error", {}).get("Code", "")
        contained = code in ("AccessDeniedException", "AccessDenied", "UnauthorizedOperation")
        return ({
            "ok": contained,
            "title": "Drift — Create Runtime in PUBLIC Mode",
            "dcf_rule": "agentcore-vca-vpc-mode-guardrail",
            "steps": [
                {"label": "CreateAgentRuntime request", "outcome": "info",
                 "detail": f"networkMode=PUBLIC, name={name}"},
                {"label": "IAM guardrail policy", "outcome": "permitted",
                 "detail": "agentcore-vca-vpc-mode-guardrail · effect=DENY"},
                {"label": "PUBLIC-mode runtime", "outcome": "blocked",
                 "detail": f"{code}: {str(e)[:200]}"},
            ],
        }, elapsed)
```

- [ ] **Step 4: Wire drift into the run endpoint**

Edit the `run_scenario` route in `app.py` — replace the `HTTPException(status_code=501)` line with a call to `drift_handler.attempt_public_runtime_create()`:

```python
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
```

- [ ] **Step 5: Run all tests**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests -v
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add blueprints/agentcore-aws/ui/drift_handler.py blueprints/agentcore-aws/ui/app.py blueprints/agentcore-aws/ui/tests/test_drift_handler.py
git commit -m "agentcore-aws ui: drift handler + wire into run endpoint"
```

---

## Task 15: Chat and Forensics routes

**Files:**
- Create: `blueprints/agentcore-aws/ui/templates/chat.html`
- Create: `blueprints/agentcore-aws/ui/templates/forensics.html`
- Modify: `blueprints/agentcore-aws/ui/app.py`

These are minimal-treatment routes per spec § Scope. Same chrome (base.html), simpler bodies.

- [ ] **Step 1: Write chat.html**

`blueprints/agentcore-aws/ui/templates/chat.html`:

```html
<style>
  .chat-card { background: #fff; border: 1px solid #e7e0d4; border-radius: 16px; padding: 22px; }
  .chat-card h2 { font-family: 'Sora'; font-weight: 700; font-size: 18px; margin: 0 0 4px; }
  .chat-card .badge { display: inline-block; background: #22C55E; color: #00170a; padding: 3px 8px; border-radius: 4px; font-family: 'Sora'; font-weight: 600; font-size: 10px; letter-spacing: 0.06em; }
  .chat-thread { margin: 20px 0; }
  .chat-msg { padding: 10px 12px; border-radius: 8px; margin-bottom: 8px; font-size: 13px; line-height: 1.5; }
  .chat-msg.user { background: #FFF7ED; border-left: 3px solid #E24402; }
  .chat-msg.assistant { background: #030712; color: #fff; }
  .chat-form { display: flex; gap: 8px; }
  .chat-form input { flex: 1; padding: 10px 12px; border: 1px solid #e7e0d4; border-radius: 6px; font-family: ui-sans-serif; font-size: 13px; }
  .chat-form button { padding: 10px 16px; background: #E24402; color: #fff; border: none; border-radius: 6px; font-family: 'Sora'; font-weight: 600; font-size: 12px; cursor: pointer; }
</style>

<div class="chat-card">
  <h2>Chat with the agent <span class="badge">DCF -30- allowed-models</span></h2>
  <p style="color: #6b7280; font-size: 13px;">Every turn traverses the allowed-models WebGroup. Off-allowlist model destinations are blocked at the spoke gateway.</p>

  <div class="chat-thread" id="chat-thread">
    {# Messages appear here. v1: client-side state. #}
  </div>

  <form class="chat-form"
        hx-post="/api/chat"
        hx-target="#chat-thread"
        hx-swap="beforeend">
    <input type="text" name="message" placeholder="Message the agent…" required autofocus />
    <button type="submit">Send</button>
  </form>
</div>
```

- [ ] **Step 2: Write forensics.html**

`blueprints/agentcore-aws/ui/templates/forensics.html`:

```html
<style>
  .forensics-card { background: #fff; border: 1px solid #e7e0d4; border-radius: 16px; padding: 22px; margin-bottom: 18px; }
  .forensics-card h2 { font-family: 'Sora'; font-weight: 700; font-size: 18px; margin: 0 0 4px; }
  .forensics-card form { display: flex; flex-direction: column; gap: 10px; margin-top: 12px; }
  .forensics-card textarea, .forensics-card input { padding: 8px 10px; border: 1px solid #e7e0d4; border-radius: 6px; font-family: ui-monospace, monospace; font-size: 12px; }
  .forensics-card button { align-self: flex-start; padding: 8px 14px; background: #E24402; color: #fff; border: none; border-radius: 6px; font-family: 'Sora'; font-weight: 600; font-size: 12px; cursor: pointer; }
  .forensics-result { background: #030712; color: #d4d4d8; padding: 14px; border-radius: 8px; margin-top: 12px; font-family: ui-monospace, monospace; font-size: 11px; white-space: pre-wrap; }
</style>

<div class="forensics-card">
  <h2>Tool use — github_search_issues <span style="font-family: ui-monospace, monospace; font-size: 11px; color: #6b7280;">DCF -31- allowed-tools</span></h2>
  <p style="color: #6b7280; font-size: 13px;">Claude decides when to call the tool; the call hits <code>api.github.com</code>, which the allowed-tools WebGroup permits.</p>
  <form hx-post="/api/forensics/tool" hx-target="#tool-result">
    <textarea name="query" rows="3" placeholder="Find recent GitHub issues about Bedrock AgentCore...">Find recent GitHub issues about Bedrock AgentCore.</textarea>
    <button type="submit">Run tool-use loop</button>
  </form>
  <div id="tool-result"></div>
</div>

<div class="forensics-card">
  <h2>MCP — list/call tools on a remote server <span style="font-family: ui-monospace, monospace; font-size: 11px; color: #6b7280;">DCF -33- allowed-mcp-servers</span></h2>
  <p style="color: #6b7280; font-size: 13px;">Allowlisted MCP sources only. Off-list servers see TLS UNEXPECTED_EOF at the spoke gateway.</p>
  <form hx-post="/api/forensics/mcp" hx-target="#mcp-result">
    <input type="url" name="server_url" placeholder="https://mcp.deepwiki.com/mcp" value="https://mcp.deepwiki.com/mcp" required />
    <input type="text" name="tool" placeholder="Tool to call (optional)" />
    <textarea name="args" rows="2" placeholder='{"k":"v"}'>{}</textarea>
    <button type="submit">Send MCP request</button>
  </form>
  <div id="mcp-result"></div>
</div>
```

- [ ] **Step 3: Wire routes in app.py**

Append to `blueprints/agentcore-aws/ui/app.py`:

```python
import json


@app.get("/chat", response_class=HTMLResponse)
def chat_page(request: Request):
    body = templates.get_template("chat.html").render()
    return templates.TemplateResponse("base.html", {
        "request": request,
        "page_title": "Chat",
        "scenarios": [],  # no picker on chat
        "active_scenario_id": None,
        "active_nav": "chat",
        "status": _status(),
        "containment": "on",
        "body_content": body,
    })


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
    return templates.TemplateResponse("base.html", {
        "request": request,
        "page_title": f"Forensics — {kind}",
        "scenarios": [],
        "active_scenario_id": None,
        "active_nav": "forensics",
        "status": _status(),
        "containment": "on",
        "body_content": body,
    })


@app.post("/api/forensics/tool", response_class=HTMLResponse)
def forensics_tool(query: str = Form(...)):
    raw, elapsed = runtime_client.invoke({"mode": "tool", "query": query})
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
```

- [ ] **Step 4: Add route tests**

Append to `blueprints/agentcore-aws/ui/tests/test_routes.py`:

```python
def test_chat_page_renders(client):
    r = client.get("/chat")
    assert r.status_code == 200
    assert "Chat with the agent" in r.text


def test_forensics_tool_page_renders(client):
    r = client.get("/forensics/tool")
    assert r.status_code == 200
    assert "github_search_issues" in r.text


def test_forensics_unknown_returns_404(client):
    r = client.get("/forensics/whatever")
    assert r.status_code == 404
```

- [ ] **Step 5: Run all tests**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests -v
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add blueprints/agentcore-aws/ui/templates/chat.html blueprints/agentcore-aws/ui/templates/forensics.html blueprints/agentcore-aws/ui/app.py blueprints/agentcore-aws/ui/tests/test_routes.py
git commit -m "agentcore-aws ui: chat and forensics routes"
```

---

## Task 16: Generate rules.json from terraform at apply time

**Files:**
- Modify: `blueprints/agentcore-aws/dcf.tf`
- Create: `blueprints/agentcore-aws/ui-rules.tf` (small, focused file)

Replace the hand-written `rules.json` with one rendered from the actual `aviatrix_distributed_firewalling_policy_list` and `aws_iam_policy` resources at terraform apply time. This keeps the catalog and policy in sync.

- [ ] **Step 1: Inspect the current DCF and IAM resource shapes**

```bash
grep -E "name *=|priority *=|action *=" blueprints/agentcore-aws/dcf.tf | head -30
grep -E "name *=|policy *=" blueprints/agentcore-aws/iam.tf | head -20
```

Note the policy resource references so the templatefile in step 2 lines up with reality.

- [ ] **Step 2: Write the rules-catalog generator**

Create `blueprints/agentcore-aws/ui-rules.tf`:

```hcl
# =============================================================================
# UI rule catalog — generated from terraform state at apply time.
#
# The agentcore-aws UI server reads /opt/agentcore-ui/rules.json to render
# the "DCF rule" / "IAM policy" block on each scenario card. We render that
# file here so the UI's catalog cannot drift from the actual policies that
# terraform applied.
#
# Only the rules referenced by scenario cards are exported. New scenarios that
# reference new rules need to add entries here too.
# =============================================================================

locals {
  # Explicit catalog keyed by rule name. We don't iterate the live
  # aviatrix_distributed_firewalling_policy_list.main.policies because:
  #   (a) the list order is sensitive to additions in dcf.tf
  #   (b) the provider doesn't expose all the human-friendly fields we want
  #       (e.g., SmartGroup names — only their UUIDs are on policy objects)
  # So we restate the structured fields here in HCL. The single source of
  # truth for the rule contents remains dcf.tf / iam.tf; this catalog just
  # mirrors them for the UI to render.
  ui_rules_catalog = {
    "${var.name_prefix}-29-runtime-deny-supply-chain-ioc-github" = {
      type             = "dcf"
      name             = "${var.name_prefix}-29-runtime-deny-supply-chain-ioc-github"
      priority         = 29
      action           = "DENY"
      protocol         = "TCP"
      port_ranges      = ["443"]
      src_smart_groups = ["runtime-subnet (${aws_subnet.agentcore_runtime.cidr_block})"]
      dst_smart_groups = ["github_hosts (FQDN raw.githubusercontent.com, github.com)"]
      web_groups       = ["supply_chain_ioc_github (URL-path patterns)"]
      decrypt_policy   = "DECRYPT_ALLOWED"
      logging          = true
      watch            = false
    }
    "${var.name_prefix}-50-runtime-dns-exfil-deny" = {
      type             = "dcf"
      name             = "${var.name_prefix}-50-runtime-dns-exfil-deny"
      priority         = 50
      action           = "DENY"
      protocol         = "UDP"
      port_ranges      = ["53"]
      src_smart_groups = ["runtime-subnet (${aws_subnet.agentcore_runtime.cidr_block})"]
      dst_smart_groups = ["any (catch-all)"]
      decrypt_policy   = null
      logging          = true
      watch            = false
    }
    "${var.name_prefix}-100-runtime-default-deny" = {
      type             = "dcf"
      name             = "${var.name_prefix}-100-runtime-default-deny"
      priority         = 100
      action           = "DENY"
      protocol         = "ANY"
      src_smart_groups = ["runtime-subnet (${aws_subnet.agentcore_runtime.cidr_block})"]
      dst_smart_groups = ["any (catch-all)"]
      decrypt_policy   = null
      logging          = true
      watch            = false
    }
    "${var.name_prefix}-vpc-mode-guardrail" = {
      type        = "iam"
      name        = "${var.name_prefix}-vpc-mode-guardrail"
      effect      = "DENY"
      action      = "bedrock-agentcore-control:CreateAgentRuntime"
      resource    = "arn:aws:bedrock-agentcore:*:*:runtime/*"
      condition   = "Null on bedrock-agentcore:subnets OR ForAnyValue:StringNotEquals on approved subnets"
      attached_to = "platform-eng / ci-cd / human-admin roles"
    }
  }
}

# Render the catalog to disk so the existing aws_s3_object in ui.tf can
# upload it. Keeping the file in path.module/ui/rules.json mirrors the
# layout the EC2 user_data expects.
resource "local_file" "ui_rules_json" {
  filename        = "${path.module}/ui/rules.json"
  content         = jsonencode(local.ui_rules_catalog)
  file_permission = "0644"
}
```

- [ ] **Step 3: Mark rules.json as a generated artifact in gitignore**

Edit `blueprints/agentcore-aws/.gitignore` to add:

```
# Generated by terraform (see ui-rules.tf)
ui/rules.json
```

Remove the hand-written `ui/rules.json` from git tracking (but keep it locally so the tests still pass before first apply):

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.worktrees/agentcore-aws-visual-refresh
git rm --cached blueprints/agentcore-aws/ui/rules.json
```

- [ ] **Step 4: Validate the terraform**

```bash
cd blueprints/agentcore-aws
terraform fmt -recursive
terraform init -backend=false
terraform validate
```
Expected: success, no errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.worktrees/agentcore-aws-visual-refresh
git add blueprints/agentcore-aws/ui-rules.tf blueprints/agentcore-aws/.gitignore
git commit -m "agentcore-aws ui: render rules.json from terraform state at apply"
```

---

## Task 17: Update systemd unit, user_data, S3 bundle, and ALB healthcheck

**Files:**
- Modify: `blueprints/agentcore-aws/ui/agentcore-ui.service`
- Modify: `blueprints/agentcore-aws/client.tf`
- Modify: `blueprints/agentcore-aws/ui.tf`
- Modify: `blueprints/agentcore-aws/ui-alb.tf`

- [ ] **Step 1: Edit the systemd unit**

`blueprints/agentcore-aws/ui/agentcore-ui.service`:

```ini
[Unit]
Description=AgentCore VCA AI Attack Simulation UI (FastAPI/uvicorn)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/agentcore-ui
EnvironmentFile=/etc/agentcore-ui.env
ExecStart=/opt/agentcore-ui/venv/bin/uvicorn ui.app:app \
  --host 0.0.0.0 \
  --port 8501 \
  --no-server-header \
  --log-level info
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Note the `ui.app:app` import path requires the working directory to contain a `ui/` package. The user_data is updated to lay out files that way.

- [ ] **Step 2: Edit ui.tf — replace S3 object list**

Open `blueprints/agentcore-aws/ui.tf` and replace the `aws_s3_object` block list with these objects:

```hcl
# Remove the streamlit-era objects:
#   aws_s3_object.ui_app, ui_scenarios_py
# Keep: ui_requirements, ui_service (file content edited), ui_scenarios_json
# Add: ui_runtime_client, ui_simulation, ui_rules_catalog, ui_evidence_builder,
#      ui_drift_handler, ui_scenario_loader,
#      every file under ui/templates/ and ui/static/.

resource "aws_s3_object" "ui_app" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/app.py"
  source = "${path.module}/ui/app.py"
  etag   = filemd5("${path.module}/ui/app.py")
}

resource "aws_s3_object" "ui_runtime_client" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/runtime_client.py"
  source = "${path.module}/ui/runtime_client.py"
  etag   = filemd5("${path.module}/ui/runtime_client.py")
}

resource "aws_s3_object" "ui_simulation" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/simulation.py"
  source = "${path.module}/ui/simulation.py"
  etag   = filemd5("${path.module}/ui/simulation.py")
}

resource "aws_s3_object" "ui_scenario_loader" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/scenario_loader.py"
  source = "${path.module}/ui/scenario_loader.py"
  etag   = filemd5("${path.module}/ui/scenario_loader.py")
}

resource "aws_s3_object" "ui_rules_catalog" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/rules_catalog.py"
  source = "${path.module}/ui/rules_catalog.py"
  etag   = filemd5("${path.module}/ui/rules_catalog.py")
}

resource "aws_s3_object" "ui_evidence_builder" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/evidence_builder.py"
  source = "${path.module}/ui/evidence_builder.py"
  etag   = filemd5("${path.module}/ui/evidence_builder.py")
}

resource "aws_s3_object" "ui_drift_handler" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/drift_handler.py"
  source = "${path.module}/ui/drift_handler.py"
  etag   = filemd5("${path.module}/ui/drift_handler.py")
}

resource "aws_s3_object" "ui_scenarios_json" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/scenarios.json"
  source = "${path.module}/ui/scenarios.json"
  etag   = filemd5("${path.module}/ui/scenarios.json")
}

resource "aws_s3_object" "ui_rules_json" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/rules.json"
  source = "${path.module}/ui/rules.json"
  etag   = filemd5("${path.module}/ui/rules.json")
  depends_on = [local_file.ui_rules_json]
}

resource "aws_s3_object" "ui_requirements" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/requirements.txt"
  source = "${path.module}/ui/requirements.txt"
  etag   = filemd5("${path.module}/ui/requirements.txt")
}

resource "aws_s3_object" "ui_service" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/agentcore-ui.service"
  source = "${path.module}/ui/agentcore-ui.service"
  etag   = filemd5("${path.module}/ui/agentcore-ui.service")
}

# Templates
resource "aws_s3_object" "ui_template_files" {
  for_each = fileset("${path.module}/ui/templates", "**/*.html")
  bucket   = aws_s3_bucket.ui.id
  key      = "ui/ui/templates/${each.value}"
  source   = "${path.module}/ui/templates/${each.value}"
  etag     = filemd5("${path.module}/ui/templates/${each.value}")
}

# Static assets
resource "aws_s3_object" "ui_static_files" {
  for_each = fileset("${path.module}/ui/static", "**/*")
  bucket   = aws_s3_bucket.ui.id
  key      = "ui/ui/static/${each.value}"
  source   = "${path.module}/ui/static/${each.value}"
  etag     = filemd5("${path.module}/ui/static/${each.value}")
}
```

(Note the doubled `ui/` in the S3 key — the bundle root is `/opt/agentcore-ui/`, and inside that we want a `ui/` package directory containing the python modules. Hence `s3://bucket/ui/ui/<file>`.)

- [ ] **Step 3: Edit client.tf user_data**

Open `blueprints/agentcore-aws/client.tf` and replace the `# ---- Streamlit scenario UI ----` block with:

```bash
    # ---- AgentCore VCA AI Attack Simulation UI (FastAPI) ----------------------
    mkdir -p /opt/agentcore-ui/ui
    UI_BUCKET='${aws_s3_bucket.ui.id}'

    # Sync the entire ui tree (templates, static, python modules, scenarios.json,
    # rules.json) under /opt/agentcore-ui/ui/. requirements.txt and the service
    # file live one level up.
    aws s3 cp --recursive "s3://$${UI_BUCKET}/ui/" /opt/agentcore-ui/
    mv /opt/agentcore-ui/agentcore-ui.service /etc/systemd/system/agentcore-ui.service

    python3 -m venv /opt/agentcore-ui/venv
    /opt/agentcore-ui/venv/bin/pip install --upgrade pip >/dev/null
    /opt/agentcore-ui/venv/bin/pip install -r /opt/agentcore-ui/requirements.txt >/dev/null

    cat > /etc/agentcore-ui.env <<ENVEOF
AWS_REGION=${var.aws_region}
AGENTCORE_DATA_HOST=${local.agentcore_data_host}
AGENTCORE_RUNTIME_ARN=UNSET_POPULATED_POST_APPLY
AGENTCORE_RUNTIME_ROLE_ARN=UNSET_POPULATED_POST_APPLY
AGENTCORE_AGENT_IMAGE_URI=UNSET_POPULATED_POST_APPLY
ADVERSARY_MCP_URL=UNSET_POPULATED_POST_APPLY
AVIATRIX_CONTROLLER_VERSION=9.0.10
ENVEOF
    systemctl daemon-reload
    systemctl enable --now agentcore-ui.service || true
```

- [ ] **Step 4: Edit ui-alb.tf — healthcheck path**

Open `blueprints/agentcore-aws/ui-alb.tf` and change the target group health-check block:

```hcl
  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
```

(Was `/_stcore/health`. Streamlit-specific.)

- [ ] **Step 5: Validate terraform**

```bash
cd blueprints/agentcore-aws
terraform fmt -recursive
terraform init -backend=false
terraform validate
```
Expected: success.

- [ ] **Step 6: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.worktrees/agentcore-aws-visual-refresh
git add blueprints/agentcore-aws/ui/agentcore-ui.service blueprints/agentcore-aws/client.tf blueprints/agentcore-aws/ui.tf blueprints/agentcore-aws/ui-alb.tf
git commit -m "agentcore-aws ui: systemd uvicorn unit, S3 bundle, ALB healthcheck"
```

---

## Task 18: Smoke checklist + final validation

**Files:**
- Create: `blueprints/agentcore-aws/tests/smoke-ui.md`

- [ ] **Step 1: Write the smoke checklist**

`blueprints/agentcore-aws/tests/smoke-ui.md`:

```markdown
# UI smoke checklist

Run after `terraform apply` against a fresh deploy. ~10 minutes.

1. `terraform output -raw ui_alb_url` — open in browser.
2. Status strip shows real `region`, `runtime`, `data plane`, `dcf rules`, `controller`.
3. Click each scenario chip in turn — page swaps; story pane updates per scenario.
4. Toggle **Containment OFF** in the status strip — switch slides to red, URL gains `?containment=off`.
5. Run **LLM01** with toggle ON → verdict `CONTAINED`; attack flow shows Aviatrix Gateway node with DENY action; rule block shows `agentcore-vca-100-runtime-default-deny`; Control Evidence shows TLS termination at spoke GW.
6. Run **LLM01** with toggle OFF → verdict `BREACH` + `SIMULATED` ribbon; same nodes but Aviatrix Gateway shows PERMIT; final egress node green ("HTTP 200, 38 bytes sent").
7. Run **LLM02** through **LLM08** with toggle ON, then OFF — verify each card adapts.
8. Run **Drift** with toggle ON → CONTAINED; rule block has `IAM` pill instead of `DCF`; Control Evidence shows `AccessDeniedException`.
9. Run **Drift** with toggle OFF → still CONTAINED + IAM-note: "IAM is a separate enforcement plane".
10. Visit `/chat` — send a message; reply appears; `DCF -30-` badge visible.
11. Visit `/forensics/tool` — submit form; JSON result rendered.
12. Visit `/forensics/mcp` — submit form with `https://mcp.deepwiki.com/mcp`; JSON tool list rendered.
```

- [ ] **Step 2: Run full test suite one more time**

```bash
cd blueprints/agentcore-aws
.venv/bin/pytest ui/tests -v
```
Expected: all tests pass.

- [ ] **Step 3: Final terraform validate across the blueprint**

```bash
cd blueprints/agentcore-aws
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```
Expected: success.

- [ ] **Step 4: Final commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.worktrees/agentcore-aws-visual-refresh
git add blueprints/agentcore-aws/tests/smoke-ui.md
git commit -m "agentcore-aws ui: smoke checklist for post-deploy verification"
```

- [ ] **Step 5: Push (only if user requests it)**

Do not push automatically. The user will review the branch and decide.
