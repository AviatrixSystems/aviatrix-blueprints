"""Scenarios tab renderer - threat-model-anchored attack cards.

Each card corresponds to a named scenario defined in scenarios.json. The
runtime executes the attack via mode="scenario" and returns a structured
result. This module renders the card with a narrative layout that reads
like a threat-report section - not a feature checklist.

The drift scenario is special: it runs entirely in the UI (directly
invoking `bedrock-agentcore-control.CreateAgentRuntime` with the UI's
own IAM role) to demonstrate the IAM guardrail blocking before any
traffic flows. Other scenarios delegate to the agent runtime.
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Callable

import boto3
import streamlit as st
from botocore.exceptions import ClientError


_SCENARIO_FILE = Path(__file__).parent / "scenarios.json"


def load_scenarios() -> list[dict]:
    with _SCENARIO_FILE.open() as f:
        return json.load(f)["scenarios"]


def _verdict_badge(contained: bool) -> str:
    if contained:
        return ('<span style="background:#16a34a;color:#fff;padding:2px 10px;'
                'border-radius:4px;font-weight:600;font-size:0.75rem;">'
                'CONTAINED</span>')
    return ('<span style="background:#dc2626;color:#fff;padding:2px 10px;'
            'border-radius:4px;font-weight:600;font-size:0.75rem;">'
            'BREACH</span>')


def _step_row(step: dict) -> str:
    outcome = step.get("outcome", "info")
    color = {
        "ok": "#16a34a",
        "info": "#64748b",
        "blocked": "#16a34a",
        "CONTAINMENT FAILED": "#dc2626",
    }.get(outcome, "#64748b")
    marker = {
        "ok": "✓",
        "info": "·",
        "blocked": "✓ blocked",
        "CONTAINMENT FAILED": "✗ leaked",
    }.get(outcome, "·")
    detail = step.get("detail", "")
    if isinstance(detail, (dict, list)):
        detail_html = f"<pre style='margin:4px 0;font-size:0.78rem;overflow-x:auto;'>{json.dumps(detail, indent=2)[:1200]}</pre>"
    else:
        detail_html = f"<div style='font-size:0.82rem;color:#475569;'>{detail}</div>"
    return (f"<div style='border-left:3px solid {color};padding:4px 10px;margin:4px 0;'>"
            f"<div style='font-size:0.88rem;'><span style='color:{color};font-weight:600;'>{marker}</span> "
            f"{step.get('label','')}</div>{detail_html}</div>")


def _render_narrative(scn: dict) -> None:
    st.markdown(f"**Setup.** {scn['setup']}")
    st.markdown(f"**Attack.** {scn['attack']}")
    st.markdown(f"**Expected behavior.** {scn['expected_behavior']}")
    c1, c2 = st.columns([1, 1])
    with c1:
        st.markdown(f"**Control.** {scn['control']}")
    with c2:
        st.caption(f"**OWASP:** {scn['owasp']}  \n**MITRE ATLAS:** {scn['mitre']}")
    if scn.get("notes"):
        st.info(scn["notes"])


def _render_blast_radius(br: dict) -> None:
    if not br:
        return
    st.markdown("**Blast radius**")
    cols = st.columns(min(len(br), 4) or 1)
    for i, (k, v) in enumerate(br.items()):
        with cols[i % len(cols)]:
            label = k.replace("_", " ")
            if isinstance(v, bool):
                display = "yes" if v else "no"
            elif isinstance(v, (int, float)):
                display = f"{v:,}"
            elif isinstance(v, list):
                display = f"{len(v)} fields"
            else:
                display = str(v)[:40]
            st.metric(label, display)


def _render_result(result: dict, scn: dict, elapsed: float) -> None:
    contained = bool(result.get("ok"))
    badge = _verdict_badge(contained)
    st.markdown(
        f"<div style='display:flex;align-items:center;gap:12px;margin:8px 0;'>"
        f"{badge} <span style='color:#64748b;font-size:0.85rem;'>round-trip {elapsed:.1f}s</span>"
        f"<span style='color:#64748b;font-size:0.85rem;'>| DCF rule: "
        f"<code>{result.get('dcf_rule','(n/a)')}</code></span></div>",
        unsafe_allow_html=True,
    )

    steps_html = "".join(_step_row(s) for s in result.get("steps", []))
    st.markdown(steps_html or "<i>no steps returned</i>", unsafe_allow_html=True)

    _render_blast_radius(result.get("blast_radius") or {})

    with st.expander("Raw runtime response"):
        st.json(result)


def render_scenario_card(scn: dict, invoke_fn: Callable[[dict], tuple[dict, float]]) -> None:
    """Render a single scenario card with a Run button."""
    with st.container(border=True):
        header = f"**{scn['title']}**"
        st.markdown(header)
        st.caption(scn["summary"])

        with st.expander("Scenario details", expanded=False):
            _render_narrative(scn)

        run_key = f"run-{scn['id']}"
        col1, col2 = st.columns([1, 4])
        with col1:
            clicked = st.button("Run scenario", key=run_key, type="primary")
        with col2:
            st.caption(f"OWASP: {scn['owasp']}  |  MITRE: {scn['mitre']}")

        if clicked:
            with st.spinner("executing attack path…"):
                try:
                    result, elapsed = invoke_fn({"mode": "scenario", "scenario": scn["id"]})
                except Exception as e:  # noqa: BLE001
                    st.error(f"{type(e).__name__}: {e}")
                    return
            if "error" in result and not result.get("steps"):
                st.error(result.get("error", "unknown error"))
                if "trace" in result:
                    st.code(result["trace"], language="text")
                return
            _render_result(result, scn, elapsed)


# ----------------------------------------------------------------------------
# Drift scenario (UI-side execution)
# ----------------------------------------------------------------------------

def _render_drift_result(contained: bool, err: str, elapsed: float) -> None:
    badge = _verdict_badge(contained)
    st.markdown(
        f"<div style='display:flex;align-items:center;gap:12px;margin:8px 0;'>"
        f"{badge} <span style='color:#64748b;font-size:0.85rem;'>round-trip {elapsed:.1f}s</span>"
        f"<span style='color:#64748b;font-size:0.85rem;'>| Control: "
        f"<code>IAM policy agentcore-vca-agentcore-vpc-mode-guardrail</code></span></div>",
        unsafe_allow_html=True,
    )
    color = "#16a34a" if contained else "#dc2626"
    marker = "✓ IAM AccessDenied" if contained else "✗ runtime created"
    detail = err if contained else "A PUBLIC-mode runtime now exists outside DCF's visibility."
    st.markdown(
        f"<div style='border-left:3px solid {color};padding:4px 10px;margin:4px 0;'>"
        f"<div style='font-size:0.88rem;'><span style='color:{color};font-weight:600;'>{marker}</span> "
        f"bedrock-agentcore-control:CreateAgentRuntime attempt</div>"
        f"<pre style='margin:4px 0;font-size:0.78rem;overflow-x:auto;white-space:pre-wrap;'>{detail}</pre>"
        f"</div>",
        unsafe_allow_html=True,
    )


def render_drift_card(
    scn: dict,
    region: str,
    runtime_role_arn: str,
    image_uri: str,
) -> None:
    with st.container(border=True):
        st.markdown(f"**{scn['title']}**")
        st.caption(scn["summary"])
        with st.expander("Scenario details", expanded=False):
            _render_narrative(scn)

        col1, col2 = st.columns([1, 4])
        with col1:
            clicked = st.button("Run scenario", key=f"run-{scn['id']}", type="primary")
        with col2:
            st.caption(f"OWASP: {scn['owasp']}  |  MITRE: {scn['mitre']}")

        if not clicked:
            return

        with st.spinner("invoking bedrock-agentcore-control…"):
            client = boto3.client("bedrock-agentcore-control", region_name=region)
            # Name must match [a-zA-Z][a-zA-Z0-9_]{0,47}
            name = f"drift_demo_{int(time.time())}"
            start = time.perf_counter()
            try:
                client.create_agent_runtime(
                    agentRuntimeName=name,
                    agentRuntimeArtifact={
                        "containerConfiguration": {"containerUri": image_uri},
                    },
                    roleArn=runtime_role_arn,
                    networkConfiguration={"networkMode": "PUBLIC"},
                    protocolConfiguration={"serverProtocol": "HTTP"},
                )
                elapsed = time.perf_counter() - start
                _render_drift_result(False, f"runtime '{name}' was created - BREACH", elapsed)
            except ClientError as e:
                elapsed = time.perf_counter() - start
                contained = e.response.get("Error", {}).get("Code") in (
                    "AccessDeniedException",
                    "AccessDenied",
                    "UnauthorizedOperation",
                )
                _render_drift_result(contained, str(e), elapsed)
            except Exception as e:  # noqa: BLE001
                elapsed = time.perf_counter() - start
                _render_drift_result(False, f"{type(e).__name__}: {e}", elapsed)
