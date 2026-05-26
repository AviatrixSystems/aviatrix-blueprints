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
