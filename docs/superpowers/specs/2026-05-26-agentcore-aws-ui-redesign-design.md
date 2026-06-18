# `agentcore-aws` UI redesign — design

**Status:** brainstorming complete, awaiting user review of this spec
**Branch:** `design/agentcore-aws-visual-refresh-2026-05-26-1`
**Worktree:** `.worktrees/agentcore-aws-visual-refresh/`
**Affects:** `blueprints/agentcore-aws/`

## Purpose

Replace the existing Streamlit operator UI for the AgentCore VCA blueprint with a templated FastAPI + Jinja2 application styled in the Aviatrix Threat Research Center visual register. The current UI is functional but reads as a test harness; the data model it carries (OWASP / MITRE / DCF rule / structured steps / blast radius) is already threat-research-shaped, so the redesign is about re-rendering existing data, not changing what's rendered. The audience is cloud / network architects and SecOps engineers running the blueprint as a containment proof, so the visual register is **technically rigorous, trust-building, no sales sensationalism.**

A secondary outcome: introduce a **Containment ON/OFF simulation toggle** as a dummy switch in v1, with a real implementation deferred to v2 that flips DCF rule actions (`DENY → PERMIT`) without removing gateways or detaching IAM policies. The architectural integrity of the demo (same VPC, same gateways, same IAM) is preserved across both states.

## Non-goals

- No change to the agent runtime contract (`agent/app.py` `/invocations` endpoint, request/response JSON shape).
- No change to the adversary Lambda MCP server (`adversary/handler.py`).
- No change to the Aviatrix DCF policy list (`dcf.tf`), the AgentCore Runtime (`runtime.tf`), or the IAM guardrail (`iam.tf`).
- No new ALB, security group, EC2 instance, or VPC resources. The existing client invoker EC2 + ALB hosts the new UI on the same port.
- No accessibility (WCAG) certification, no mobile responsive layout, no browser matrix beyond current Chrome / Safari / Firefox.
- No Playwright visual-regression suite — the redesign IS the visual; pinned screenshots would lock us out of iteration.
- No live Aviatrix Controller integration in v1 (toggle is dummy; see § v2 roadmap).

## Locked design decisions

These are the conclusions of the brainstorming session. Each was validated against a mockup or terminal A/B in the session and approved by the user.

1. **Stack** — FastAPI + Jinja2 + Tailwind (vendored CSS), uvicorn, replacing Streamlit. Same EC2 + ALB + S3 bundle pattern.
2. **Scope** — `Scenarios` and `Chat` are first-class surfaces; `Tool` and `MCP` live behind a `Forensics` nav link with minimal visual treatment; the existing `architecture.svg` is reachable as `Architecture` in the nav.
3. **Information architecture** — Per-scenario two-pane layout: left = story (Setup / Attack / Containment narrative), right = live state (verdict, attack flow, rule, evidence). Scenarios swap via top-bar chip clicks with HTMX partial swaps; no SPA framework.
4. **Visual register** — Editorial briefing: cream body (`#FCF9F3`), dark hero band (`#030712`), dark-navy live pane (`#030712`), Aviatrix orange (`#E24402`) primary accent, secondary purple (`#7A5DDC`) for control-evidence treatment. Heading font Sora 700, body system-ui.
5. **Attack-flow visual** — Drawn from `result.steps[]` returned by the agent, not a generic Lockheed kill chain. Node colors come from `outcome` (`info` neutral, `ok` green, `blocked` red). One template loops over the runtime payload; nothing is hand-curated per scenario.
6. **Enforcement representation** — Aviatrix Gateway (for DCF scenarios) or IAM guardrail (for Drift) renders as a first-class node in the flow, between the last permitted step and the dropped step. The dropped final step is dimmed / strikethrough to show "the agent attempted it; it never happened."
7. **Rule block** — Below the attack flow. Structured key/value rendering of the actual `aviatrix_distributed_firewalling_policy_list` policy fields for DCF rules (`priority`, `action`, `protocol`, `src_smart_groups`, `dst_smart_groups`, `decrypt_policy`, `logging`) or the `aws_iam_policy` document for IAM (`effect`, `action`, `resource`, `condition`). A small `DCF` / `IAM` pill distinguishes the enforcement plane.
8. **Control Evidence block** — Below the rule block. Replaces the "Would Leak / Actually Leaked / Fields Exposed" panel removed for being sales-sensational. Architecturally rigorous fields: `match attribute`, `matched group`, `enforcement point`, `decryption`, `termination`, `audit`. Renders in a subtle purple-tinted variant of the dark-navy panel.
9. **Drift adaptation** — Same template, IAM substitutions for the rule block and evidence block. The `IAM` pill on the rule block is the only structural addition.
10. **Page chrome** — Dark header with Aviatrix mark + `AI ATTACK SIMULATION` eyebrow + nav (`Scenarios` active / `Chat` / `Forensics` / `Architecture`). Title bar with H1 (`AWS Bedrock AgentCore`). Cream-bg scenario chip picker. Status strip with `region` / `runtime` / `data plane` / `dcf rules` / `controller` version + Containment toggle. Dark footer.
11. **Containment toggle (v1)** — A switch in the status strip with no controller-side effect. When OFF the server still returns a valid response, but it sources the payload from `simulation.py` (precomputed "without Aviatrix" results) instead of calling the runtime. The card renders with a `SIMULATED` ribbon and a `BREACH` verdict. No Aviatrix Controller call; no DCF state change. Drift remains contained even when the toggle is OFF — the card displays a note explaining IAM is a separate enforcement plane outside the toggle's scope. "Dummy" here means *not affecting real policy*, not *non-functional*: the toggle is a complete and observable UI behavior in v1.
12. **Run mechanism** — Synchronous. Run button issues a single `fetch` POST; live pane renders the entire response blob at once. No SSE, no progressive step streaming. Matches the existing agent contract (sync `/invocations`).

## Architecture

### File layout

Inside `blueprints/agentcore-aws/ui/`:

```
ui/
├── app.py                  # FastAPI server: routes, controller-thin
├── runtime_client.py       # boto3 wrapper for bedrock-agentcore invoke
├── simulation.py           # per-scenario "simulated baseline" payloads (v1)
├── rules.json              # rule catalog rendered from dcf.tf + iam.tf at deploy time
├── scenarios.json          # unchanged — data contract with the agent
├── templates/
│   ├── base.html           # shell: header, picker, status strip, footer
│   ├── scenario.html       # the two-pane card
│   ├── chat.html           # chat route
│   ├── forensics.html      # Tool + MCP stubs behind one nav link
│   └── partials/
│       ├── flow.html       # attack-flow nodes
│       ├── rule_block.html # DCF or IAM rule expansion
│       └── evidence.html   # Control Evidence block
├── static/
│   ├── tailwind.css        # built output (vendored)
│   ├── sora.css            # Sora @font-face (vendored from Google Fonts)
│   ├── aviatrix.svg        # white-orange logo
│   └── tokens.css          # CSS-variable form of research/tokens.json
├── requirements.txt        # fastapi, uvicorn[standard], jinja2, boto3
├── agentcore-ui.service    # systemd unit (ExecStart edited)
└── tests/
    ├── test_simulation_payloads.py
    ├── test_template_render.py
    └── test_routes.py
```

### Deploy plumbing diff

| Component | Status | Diff |
|---|---|---|
| `aws_instance.client_invoker` | unchanged | t4g.small ARM64, same SG, same SSM role |
| `aws_lb.ui` ALB | unchanged | port 80, IP-allowlisted, 300s idle |
| `aws_s3_bucket.ui` bundle | edited | adds `templates/`, `static/`, `rules.json`, `simulation.py`, `runtime_client.py`; drops legacy Streamlit objects |
| `agentcore-ui.service` | edited | `ExecStart` swaps from `streamlit run /opt/agentcore-ui/app.py` to `/opt/agentcore-ui/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8501` |
| `user_data` in `client.tf` | edited | `pip install -r requirements.txt` pulls fastapi/uvicorn/jinja2 instead of streamlit |
| `/etc/agentcore-ui.env` | unchanged | same env vars |
| ALB target group healthcheck path | edited | `/_stcore/health` → `/healthz` (200 OK from FastAPI) |
| WebSocket stickiness on TG | optional | can be removed (FastAPI is stateless); harmless if left |

### `rules.json` generation

A small terraform-side helper writes the rule catalog at apply time. Keys are the DCF rule names (e.g., `agentcore-vca-100-runtime-default-deny`) or the IAM policy name (`agentcore-vca-vpc-mode-guardrail`). Values are the structured fields the UI displays. The file is uploaded to S3 alongside the rest of the bundle.

This avoids a runtime dependency on the Aviatrix Controller API at server boot. If the rule list changes post-deploy, `terraform apply` regenerates the file and the EC2 fetches the new version (existing `etag`-driven S3 object refresh pattern).

## Routes and data contract

### HTTP routes

| Method + path | Returns | Notes |
|---|---|---|
| `GET /` | 302 → `/s/llm01_prompt_inject_exfil` | Default landing |
| `GET /s/{scenario_id}` | `scenario.html` | Page chrome + scenario card; live pane empty until Run |
| `GET /s/{scenario_id}/fragment` | partial HTML | HTMX target for chip-click swaps |
| `POST /api/run/{scenario_id}` | JSON | Run button hits this |
| `GET /chat` | `chat.html` | Empty conversation, DCF `-30-` badge |
| `POST /api/chat` | JSON | Passes through to agent `mode=chat` |
| `GET /forensics/tool`, `/forensics/mcp` | `forensics.html` | Restyled versions of existing tabs |
| `POST /api/forensics/tool`, `/api/forensics/mcp` | JSON | Agent `mode=tool` / `mode=mcp` |
| `GET /healthz` | `200 OK {"status":"healthy"}` | ALB healthcheck |

### `POST /api/run/{scenario_id}` contract

Request:
```json
{ "containment": "on" }
```

Response (the runtime returns `ok / title / owasp / mitre / dcf_rule / steps`; the UI server augments with `rule_definition`, `control_evidence`, and `simulated` before returning to the browser):

```json
{
  "ok": true,
  "title": "Prompt Injection → Tool-Abuse Exfil",
  "owasp": "LLM01 Prompt Injection + LLM07 Insecure Output Handling",
  "mitre": "AML.T0051 + AML.T0024",
  "dcf_rule": "agentcore-vca-100-runtime-default-deny",
  "steps": [
    {"label": "Attacker prompt", "outcome": "info", "detail": "…"},
    {"label": "lookup_customer(42)", "outcome": "ok", "detail": {…}},
    {"label": "PII classified", "outcome": "info", "detail": "…"},
    {"label": "Egress to evil.attacker.example", "outcome": "blocked", "detail": "URLError: …"}
  ],
  "rule_definition": {
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
  "control_evidence": {
    "match_attribute": "destination SNI evil.attacker.example",
    "matched_group": "dst = any (default-deny fallback)",
    "enforcement_point": "AgentCore spoke GW (L4 stateful)",
    "decryption": "not required",
    "termination": "TLS handshake closed pre-egress (no bytes left VPC)",
    "audit": "FlowIQ entry: action=DENY, rule=-100-"
  },
  "simulated": false
}
```

For the Drift scenario, `rule_definition.type = "iam"` and the fields swap to `effect`, `action`, `resource`, `condition`, `attached_to`; `control_evidence` fields swap to `match_attribute`, `matched_statement`, `enforcement_point` (= `AWS IAM (pre-handler)`), `error_returned` (= `AccessDeniedException · HTTP 403`), `side_effects` (= `none — no AgentCore resource created`), `audit` (= `CloudTrail entry…`).

### Simulation dispatch

Server pseudocode for `POST /api/run/{scenario_id}`:

```python
@app.post("/api/run/{scenario_id}")
async def run_scenario(scenario_id: str, req: RunRequest) -> dict:
    scenario = scenarios[scenario_id]

    if scenario_id == "drift_public_mode":
        # Drift is always real — IAM is the enforcement plane.
        result = drift_handler.attempt_public_runtime_create()
        return _attach_rule_and_evidence(result, scenario, simulated=False)

    if req.containment == "off":
        # v1: precomputed payload from simulation.py.
        # v2: flip DCF rule, call runtime, restore rule (same response shape).
        payload = simulation.SIMULATED_PAYLOADS[scenario_id]
        return _attach_rule_and_evidence(payload, scenario, simulated=True)

    # containment = on, live runtime invoke
    raw = runtime_client.invoke({"mode": "scenario", "scenario": scenario_id})
    return _attach_rule_and_evidence(raw, scenario, simulated=False)
```

The `_attach_rule_and_evidence` helper looks up `rule_definition` from `rules.json` by `dcf_rule` ID and composes `control_evidence` from the step outcomes + rule fields. Keeps composition logic in one place.

## Data flow

### Server boot

```
systemd → uvicorn ui.app:app --port 8501
   ↓
FastAPI lifespan startup
   ├─ Load /opt/agentcore-ui/rules.json
   ├─ Load /opt/agentcore-ui/scenarios.json
   ├─ Load /opt/agentcore-ui/simulation.py SIMULATED_PAYLOADS
   └─ Init boto3 clients: bedrock-agentcore, bedrock-agentcore-control
   ↓
Ready; /healthz returns 200
```

Missing `rules.json` or `scenarios.json` = uvicorn fails to start; systemd reports failure. Missing env vars (`AGENTCORE_RUNTIME_ARN` etc) = startup OK in "config pending" mode; every `/api/run/*` returns `ok:false, error:"config pending"`.

### Run, toggle ON

```
Browser  ─── POST /api/run/llm01 {containment:"on"} ───►  UI server
                                                            │
                                              bedrock-agentcore:InvokeAgentRuntime
                                              {mode:"scenario", scenario:"llm01_..."}
                                                            │
                                              (PrivateLink → data-plane endpoint)
                                                            ▼
                                                    AgentCore Runtime
                                                    scenario_llm01_…()
                                                       lookup_customer(42)   ok
                                                       urlopen(evil...)      blocked (DCF -100-)
                                                       returns steps[]
                                                            ▲
              ◄────── JSON {steps, rule_definition, control_evidence, simulated:false} ──
Browser renders CONTAINED + flow + rule + evidence; picker dot turns green.
```

### Run, toggle OFF (v1, simulated)

```
Browser  ─── POST /api/run/llm01 {containment:"off"} ──►  UI server
                                                           │
                                       simulation.SIMULATED_PAYLOADS["llm01_..."]
                                                           │
                              ◄── JSON {steps, rule(action=PERMIT), simulated:true} ──
Browser renders SIMULATED ribbon + BREACH verdict; Aviatrix Gateway shows PERMIT;
egress node renders ok/green ("HTTP 200, 38 bytes sent").
```

### Run, Drift (regardless of toggle)

```
Browser  ─── POST /api/run/drift_public_mode ───────────►  UI server
                                                           │
                            bedrock-agentcore-control:CreateAgentRuntime
                            networkMode=PUBLIC
                                                           │
                                          AWS IAM evaluates the request
                                          → AccessDeniedException
                                                           ▼
                              ◄── JSON {ok:true, type:"iam", evidence:{...}} ──
Browser renders CONTAINED. If toggle is OFF, prepend a card-level note:
"IAM is a separate enforcement plane; toggle scope is DCF only."
```

### Chat turn

```
Browser  ─── POST /api/chat {messages:[...]} ─────►  UI server
                                                       │
                              bedrock-agentcore:InvokeAgentRuntime {mode:"chat"}
                                                       │
                                          AgentCore Runtime → bedrock-runtime.converse
                                                       ▼
                              ◄── JSON {reply, usage, stop_reason} ──
Browser appends to conversation; DCF -30- badge stays lit.
```

### Static assets, navigation, deep links

- Scenario chip clicks call `htmx.ajax('GET', '/s/{id}/fragment')` and swap the card region; `history.pushState` updates the URL.
- Containment toggle state held in `localStorage` and reflected in URL as `?containment=off` for deep linking.
- Sora woff2 and tailwind.css served from `/static/` with long-cache headers.

## Visual design system

The full token set is in `research/tokens.json` (gitignored research bundle). The canonical mockups for cross-reference are in `research/mockups/`:

- `01-page-chrome.html` — header, picker, status strip, footer
- `02-scenario-card-llm01.html` — locked LLM01 card with rule block + evidence
- `03-scenario-card-drift.html` — Drift adaptation with IAM substitutions
- `04-enforcement-marker-options.html` — A/B/C of the enforcement-marker treatment (B selected)

### Tokens summary

| Role | Hex | Use |
|---|---|---|
| Brand orange primary | `#E24402` | Aviatrix mark, primary CTA, active nav border |
| Brand orange warm | `#FA6B1E` | Eyebrows, accent text on dark, gradient stops |
| Brand purple | `#7A5DDC` | Control-evidence block tint, governance-layer accent |
| Cream body | `#FCF9F3` | Page background |
| Orange-50 | `#FFF7ED` | Inline callout backgrounds |
| Panel deep navy | `#030712` | Header, footer, live pane, hero |
| Panel ink | `#111827` | Secondary dark surfaces |
| Text ink | `#181818` | Body text on light |
| Text muted | `#6B7280` | Captions, secondary metadata |
| Severity green | `#22C55E` | Verdict CONTAINED, `ok` step nodes |
| Severity yellow | `#EAB308` | (Reserved; not currently used) |
| Severity red | `#DC2626` | Verdict BREACH, `blocked` step nodes, `× DENY` action |
| Severity gray | `#9CA3AF` | Dimmed / strikethrough nodes |

### Typography

| Role | Family | Weight | Sizes |
|---|---|---|---|
| Hero / page H1 | Sora | 700 | 32px |
| Section H2 (scenario title) | Sora | 700 | 22px |
| Eyebrow | Sora | 600 | 11px, uppercase, +0.08em tracking |
| Body | system-ui | 400 | 13px line-height 1.55 |
| Code / monospace | ui-monospace | 400 | 12px |
| Caption | system-ui | 500 | 11px |

### Component patterns

- **Panel container** — `bg-#030712 rounded-2xl p-22 text-#fff`, optional `border border-white/10 shadow-2xl backdrop-blur-md` for elevated variants.
- **Frosted-glass card** — `bg-white/10 backdrop-blur-md border border-white/10 rounded-2xl shadow-2xl` over a dark surface (only used in `Forensics` route).
- **Pill chip** — 6×14 padding, `border-radius:999px`, `border:1px solid #e7e0d4`, hover orange, active filled orange.
- **Severity pill (verdict)** — `padding:5px 12px`, `border-radius:4px`, Sora 700, 11px, +0.04em tracking. Green/red bg, near-black/white fg.
- **Phase circle** — 22×22px, `border-radius:50%`, Sora 700, 12px. Used for step markers.
- **Enforcement node** — variant of step node: orange border (1.5px solid `#E24402`), 4px orange glow, accent label.

## Error handling

Three boundaries fail; everything internal trusts itself.

### Boundary 1 — Agent runtime invoke

| Failure | Server | User |
|---|---|---|
| `ClientError` (any AWS code) | 200 + `{ok:false, error:"AWS: <code>"}` | Red error band in live pane |
| `BotoCoreError` / timeout (60s) | 200 + `{ok:false, error:"timeout calling runtime"}` | Red band: suggests checking rule `-10-` |
| Non-200 or malformed JSON from runtime | 200 + `{ok:false, error:"runtime returned invalid response", trace}` | Red band + raw payload in expander |
| Valid JSON but `ok:false` from runtime | Pass through unchanged | Live pane renders the steps the agent did return |

### Boundary 2 — Drift handler

| Failure | Server |
|---|---|
| `AccessDeniedException` / `UnauthorizedOperation` | Expected — return `ok:true, simulated:false` (contained) |
| Any other exception | Return `ok:false, error` with the exception class + message |

### Boundary 3 — Browser → server

| Failure | Browser |
|---|---|
| `fetch` rejects | Inline toast under Run button: "Network error — retry?" |
| Server 5xx | Toast: "Server error — see console" |
| Server returns `{ok:false}` | Render the error band in the live pane (no toast) |

### Server startup

Fail fast on missing `rules.json` / `scenarios.json`. Missing env vars (`AGENTCORE_RUNTIME_ARN`) is **not** a startup failure — server starts in "config pending" mode and `/api/run/*` returns a config-pending error per call.

### Deliberately not handled

- Operator-toggle race conditions (v1 toggle is client-only; v2 needs a mutex on the controller call).
- Transient AWS retry. Fail fast; let the user click Run again. Hidden retries muddy demo timings.
- Local file logging beyond `print()` to stdout (captured by systemd-journald).

## Testing

### Automated, CI-runnable

| Test file | Coverage |
|---|---|
| `ui/tests/test_simulation_payloads.py` | Every entry in `scenarios.json` has a matching `SIMULATED_PAYLOADS` entry; every payload has required fields (`steps`, `rule_definition`, `control_evidence`, `verdict`) |
| `ui/tests/test_template_render.py` | Each Jinja template renders without error against a fixture payload; partial includes resolve |
| `ui/tests/test_routes.py` | FastAPI TestClient: `/`, `/healthz`, `/s/<id>`, `/chat`, `/forensics/*` return 200; boto3 mocked with `botocore.stub.Stubber` |
| `terraform fmt -check` + `terraform validate` | Existing validation; covers `ui.tf` / `client.tf` / `agentcore-ui.service` diffs (already gated by `/validate-blueprint`) |

No AWS credentials, no Aviatrix Controller, no live runtime required.

### Manual smoke (`tests/smoke-ui.md`)

Run by the deploying engineer after `terraform apply`:

1. Open `terraform output -raw ui_alb_url` → status strip shows real region / runtime ID.
2. Click each of the 6 scenario chips → page swaps via HTMX, story pane updates.
3. Toggle Containment OFF → red banner, URL gains `?containment=off`.
4. Run LLM01 with toggle ON → CONTAINED, Aviatrix Gateway node shows DENY.
5. Run LLM01 with toggle OFF → BREACH + SIMULATED ribbon; Aviatrix Gateway shows PERMIT; egress node green.
6. Run Drift with toggle OFF → CONTAINED with the layered-controls note.
7. Run Chat → reply renders; usage data displayed; DCF `-30-` badge stays green.
8. Visit Forensics/Tool, Forensics/MCP → forms render and submit.

Time budget: ~10 minutes.

### Preserved

`tests/probe.sh` is unchanged. Agent contract is unchanged; the script's SSM-driven probe path is independent of the UI.

## v2 roadmap — live Containment toggle

When the toggle becomes real:

- **Strategy:** flip the `aviatrix_distributed_firewalling_policy_list` policy actions from `DENY` to `PERMIT` for the in-scope rules (`-29-`, `-50-`, `-100-`, etc.), **or** insert a priority-1 catch-all `PERMIT` rule above them. **The gateway stays in the data path. The IAM guardrail stays attached.** Architecture is identical in both states; only the policy decision changes.
- **Server endpoint:** `POST /api/containment/{on|off}` calling the Aviatrix Controller via the existing Aviatrix terraform provider's underlying API or via direct HTTP to the controller (decision deferred).
- **Auto-restore TTL:** 5 minutes. Server tracks `last_disabled_timestamp` and re-enables on a background task.
- **Visible state:** Header banner when off — red strip across the top reading `CONTAINMENT DISABLED · auto-restore in 4:47` with a `Restore now` button.
- **Audit:** Every toggle writes a CloudTrail / journald entry (toggle source IP, timestamp, target state).
- **Drift scope:** Toggle does not touch IAM. The Drift card's "IAM is a separate plane" note becomes a permanent part of the layered-controls narrative.

The v1 API contract for `POST /api/run/*` is unchanged in v2; only the server's behavior on `containment=off` changes from "return simulation.py payload" to "call controller, call runtime, restore, return real response." `simulated: false` in v2 responses.

## Files affected

### Added

- `blueprints/agentcore-aws/ui/runtime_client.py`
- `blueprints/agentcore-aws/ui/simulation.py`
- `blueprints/agentcore-aws/ui/rules.json` (generated by terraform helper)
- `blueprints/agentcore-aws/ui/templates/` (whole tree)
- `blueprints/agentcore-aws/ui/static/` (whole tree)
- `blueprints/agentcore-aws/ui/tests/` (3 test files)
- `blueprints/agentcore-aws/tests/smoke-ui.md`

### Edited

- `blueprints/agentcore-aws/ui/app.py` — full rewrite as FastAPI app
- `blueprints/agentcore-aws/ui/requirements.txt` — `streamlit` → `fastapi`, `uvicorn[standard]`, `jinja2`, plus existing `boto3`
- `blueprints/agentcore-aws/ui/agentcore-ui.service` — `ExecStart` line
- `blueprints/agentcore-aws/client.tf` — user_data block (pip install, healthcheck note); ALB target group health-check path
- `blueprints/agentcore-aws/ui.tf` — S3 object list for the new file set
- `blueprints/agentcore-aws/ui-alb.tf` — target-group health-check path moves to `/healthz`; stickiness optional drop
- `blueprints/agentcore-aws/dcf.tf` — no functional change; terraform-side helper added to write `rules.json` at apply time

### Removed

- `blueprints/agentcore-aws/ui/scenarios.py` (Streamlit-specific rendering)

## Resolved decisions

The four open questions from the design discussion are settled. The spec body already reflects these choices; this section records the decision trail.

1. **Spec location** — `docs/superpowers/specs/2026-05-26-agentcore-aws-ui-redesign-design.md`. Matches the existing `2026-04-29-qa-blueprint-design.md` precedent in the same directory.
2. **`rules.json` generation** — Static file written at `terraform apply` by a small helper that reads the policy resources in `dcf.tf` and `iam.tf`. Uploaded as an S3 bundle object; pulled by the EC2 user_data on boot. No live Aviatrix Controller dependency at server start.
3. **Tailwind toolchain** — Vendored built CSS file in `ui/static/tailwind.css`. No Node toolchain in the runtime image; no `cdn.tailwindcss.com` egress requirement.
4. **HTMX** — Adopted (~14kb gzipped) for chrome-nav partial swaps. Vanilla `fetch` still used for the JSON `/api/...` endpoints; HTMX is for HTML fragment swaps only.

## Appendix — research bundle

The research / mockup artifacts that informed this spec live in `research/` at the worktree root. The folder is excluded from git via the main repo's `.git/info/exclude` (entry: `research/`); the contents are durable on disk but not tracked.

- `research/design-direction.md` — 10-section synthesis of TRC visual style with computed-style evidence
- `research/tokens.json` — machine-readable design tokens
- `research/trc-snapshots/trc-index-full.png`, `research/trc-snapshots/article-kali365-full.png` — full-page screenshots of the source pages
- `research/logos/` — five Aviatrix logo variants
- `research/mockups/01-page-chrome.html` — locked chrome
- `research/mockups/02-scenario-card-llm01.html` — locked scenario card (LLM01)
- `research/mockups/03-scenario-card-drift.html` — locked Drift card
- `research/mockups/04-enforcement-marker-options.html` — A/B/C of enforcement marker (B selected)
