"""Smoke tests for FastAPI routes."""
from __future__ import annotations


def test_healthz_returns_200(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "healthy"}


def test_static_assets_served(client):
    for asset in ["/static/tokens.css", "/static/sora.css", "/static/htmx.min.js", "/static/aviatrix.svg"]:
        r = client.get(asset)
        assert r.status_code == 200, f"{asset} returned {r.status_code}"


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
