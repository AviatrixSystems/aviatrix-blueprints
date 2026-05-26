"""FastAPI application for the AgentCore VCA simulation UI.

Replaces the previous Streamlit implementation. See
docs/superpowers/specs/2026-05-26-agentcore-aws-ui-redesign-design.md
for the full design.
"""
from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

app = FastAPI(title="AgentCore VCA — AI Attack Simulation")

STATIC_DIR = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "healthy"}
