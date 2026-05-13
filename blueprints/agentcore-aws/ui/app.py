"""Streamlit UI for the Aviatrix AgentCore VCA.

Threat-model-centric layout. The main tab is Scenarios - five cards
covering four OWASP LLM attack patterns + one control-plane drift case.
Chat / Tool / MCP remain as hands-on modes that demonstrate the
"positive" agent behaviors DCF permits.
"""
from __future__ import annotations

import json
import os
import secrets
import socket
import time

import boto3
import streamlit as st
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from scenarios import load_scenarios, render_drift_card, render_scenario_card

REGION = os.environ.get("AWS_REGION", "us-east-2")
RUNTIME_ARN = os.environ.get("AGENTCORE_RUNTIME_ARN", "")
RUNTIME_ROLE_ARN = os.environ.get("AGENTCORE_RUNTIME_ROLE_ARN", "")
AGENT_IMAGE_URI = os.environ.get("AGENTCORE_AGENT_IMAGE_URI", "")
DATA_HOST = os.environ.get(
    "AGENTCORE_DATA_HOST",
    f"bedrock-agentcore.{REGION}.amazonaws.com",
)

st.set_page_config(page_title="AgentCore VCA", page_icon="🛡️", layout="wide")

_client = boto3.client(
    "bedrock-agentcore",
    region_name=REGION,
    config=Config(connect_timeout=10, read_timeout=180, retries={"max_attempts": 1}),
)


def resolve_host(hostname: str) -> str:
    try:
        addrs = sorted({x[4][0] for x in socket.getaddrinfo(hostname, 443, proto=socket.IPPROTO_TCP)})
        return ", ".join(addrs) if addrs else "(no answer)"
    except socket.gaierror as e:
        return f"(resolve failed: {e})"


def invoke(payload: dict) -> tuple[dict, float]:
    start = time.perf_counter()
    sid = f"ui-{int(time.time())}-{secrets.token_hex(16)}"
    resp = _client.invoke_agent_runtime(
        agentRuntimeArn=RUNTIME_ARN,
        runtimeSessionId=sid,
        payload=json.dumps(payload).encode(),
    )
    raw = resp["response"].read()
    return json.loads(raw), time.perf_counter() - start


# ----------------------------------------------------------------------------
# Scenarios tab
# ----------------------------------------------------------------------------

def scenarios_tab() -> None:
    st.caption(
        "Each card runs a named attack path end-to-end. Verdict is **CONTAINED** when "
        "Aviatrix DCF (or IAM, for the drift case) blocks the attack; **BREACH** otherwise."
    )
    scenarios = load_scenarios()
    for scn in scenarios:
        if scn["id"] == "drift_public_mode":
            render_drift_card(
                scn, region=REGION,
                runtime_role_arn=RUNTIME_ROLE_ARN,
                image_uri=AGENT_IMAGE_URI,
            )
        else:
            render_scenario_card(scn, invoke_fn=invoke)


# ----------------------------------------------------------------------------
# Chat tab
# ----------------------------------------------------------------------------

def chat_tab() -> None:
    st.caption("Every turn traverses the allowed-models WebGroup (rule `-30-`).")
    if "chat_messages" not in st.session_state:
        st.session_state.chat_messages = []
    for m in st.session_state.chat_messages:
        with st.chat_message(m["role"]):
            st.markdown(m["content"])
    prompt = st.chat_input("Message the agent…")
    if prompt:
        st.session_state.chat_messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)
        with st.chat_message("assistant"):
            ph = st.empty()
            with st.spinner("thinking…"):
                try:
                    result, elapsed = invoke({"mode": "chat", "messages": st.session_state.chat_messages})
                except (BotoCoreError, ClientError) as e:
                    ph.error(f"{type(e).__name__}: {e}")
                    return
            if not result.get("ok"):
                err = result.get("error") or f"runtime returned: {json.dumps(result)[:400]}"
                ph.error(err)
                return
            reply = result.get("reply", "")
            ph.markdown(reply)
            usage = result.get("usage", {})
            st.caption(f"{elapsed:.1f}s | in={usage.get('inputTokens','?')} "
                       f"out={usage.get('outputTokens','?')} stop={result.get('stop_reason','?')}")
            st.session_state.chat_messages.append({"role": "assistant", "content": reply})
    if st.button("Reset chat", key="chat-reset"):
        st.session_state.chat_messages = []
        st.rerun()


# ----------------------------------------------------------------------------
# Tool tab
# ----------------------------------------------------------------------------

def tool_tab() -> None:
    st.caption("Claude decides when to call `github_search_issues` -> `api.github.com`. "
               "Watch DCF rule `-31-` (allowed-tools).")
    default_q = "Find recent open GitHub issues mentioning Bedrock AgentCore in the past month."
    query = st.text_area("User prompt", value=default_q, height=80, key="tool-q")
    if st.button("Send to agent", type="primary", key="tool-run"):
        with st.spinner("Tool-use loop running…"):
            try:
                result, elapsed = invoke({"mode": "tool", "query": query})
            except (BotoCoreError, ClientError) as e:
                st.error(f"{type(e).__name__}: {e}")
                return
        st.caption(f"Round-trip: {elapsed:.1f}s")
        if not result.get("ok"):
            st.error(result.get("error", "unknown error"))
        else:
            st.markdown("**Reply**")
            st.markdown(result.get("reply", "(empty)"))
            usage = result.get("usage", {})
            st.caption(f"in={usage.get('inputTokens','?')} out={usage.get('outputTokens','?')}")
        with st.expander("Tool-use trace"):
            st.json(result.get("trace", []))
        with st.expander("Raw response"):
            st.json(result)


# ----------------------------------------------------------------------------
# MCP tab
# ----------------------------------------------------------------------------

def mcp_tab() -> None:
    st.caption("Connects to a remote MCP server via streamable-http. Allowed servers "
               "match the `allowed-mcp-servers` WebGroup (rule `-33-`).")
    preset = st.radio(
        "Server", options=["DeepWiki (allowed)", "Adversary MCP (allowed, compromised)",
                            "mcp.example.com (deny test)", "Custom"],
        horizontal=True, key="mcp-preset",
    )
    adversary_url = os.environ.get("ADVERSARY_MCP_URL", "")
    if preset == "DeepWiki (allowed)":
        url = "https://mcp.deepwiki.com/mcp"
        st.code(url, language="text")
    elif preset == "Adversary MCP (allowed, compromised)":
        url = adversary_url or "(ADVERSARY_MCP_URL not set)"
        st.code(url, language="text")
        st.warning("This is the LLM05 scenario's MCP source. Allowlisted but hostile - "
                   "tool descriptions carry injection pointing at evil.attacker.example.")
    elif preset == "mcp.example.com (deny test)":
        url = "https://mcp.example.com/mcp"
        st.code(url, language="text")
        st.info("Expected: TLS UNEXPECTED_EOF or timeout - DCF closes on SNI.")
    else:
        url = st.text_input("MCP server URL", value="https://", key="mcp-url-custom")

    tool = st.text_input("Tool to call (optional; leave blank for list-only)",
                         value="", key="mcp-tool")
    args_str = st.text_area("Tool args (JSON)", value="{}", height=80,
                            key="mcp-args", disabled=not tool)
    if st.button("Call MCP server", type="primary", key="mcp-run"):
        try:
            args = json.loads(args_str) if args_str.strip() else {}
        except json.JSONDecodeError as e:
            st.error(f"args not valid JSON: {e}")
            return
        with st.spinner("Talking to MCP server…"):
            try:
                result, elapsed = invoke({
                    "mode": "mcp", "server_url": url,
                    "tool": tool or None, "args": args,
                })
            except (BotoCoreError, ClientError) as e:
                st.error(f"{type(e).__name__}: {e}")
                return
        st.caption(f"Round-trip: {elapsed:.1f}s")
        if not result.get("ok"):
            st.error(result.get("error", "unknown error"))
            st.caption("If the server isn't in `allowed_mcp_server_domains`, you'll see "
                       "TLS UNEXPECTED_EOF here - that's DCF closing the SNI.")
        else:
            srv = result.get("server", {})
            st.success(f"Connected to **{srv.get('name') or 'unknown'}** "
                       f"v{srv.get('version') or '?'} (MCP {srv.get('protocolVersion')})")
            tools = result.get("tools", [])
            st.markdown(f"**{len(tools)} tools available**")
            for t in tools:
                st.markdown(f"- `{t['name']}` - {t['description']}")
            if "called" in result:
                st.markdown("**Tool invocation result**")
                st.json(result["called"])
        with st.expander("Raw response"):
            st.json(result)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main() -> None:
    st.title("🛡️ AgentCore VCA")
    st.caption("Threat-model-centric demo of Aviatrix containment for Bedrock AgentCore.")

    with st.sidebar:
        st.subheader("Environment")
        st.code(f"region:       {REGION}\nruntime_arn:  {RUNTIME_ARN}\ndata_host:    {DATA_HOST}",
                language="text")
        st.subheader("DNS resolution")
        st.code(f"{DATA_HOST}\n  -> {resolve_host(DATA_HOST)}", language="text")
        st.caption("10.50.20.x confirms the shared R53 PHZ is steering to the PrivateLink endpoint.")
        st.subheader("DCF rules in play")
        st.markdown("""
- **-30-** allowed-models (Bedrock egress)
- **-31-** allowed-tools (GitHub, etc.)
- **-33-** allowed-mcp-servers
- **-50-** DNS-exfil deny
- **-100-** default-deny (catches attacker domains)
""")
        st.subheader("Prevention layers")
        st.markdown("""
- **IAM guardrail**: `agentcore-vca-agentcore-vpc-mode-guardrail` blocks
  runtime creation outside VPC mode (drift scenario).
- **DCF**: SmartGroup+WebGroup enforcement on egress.
""")

    if not RUNTIME_ARN:
        st.error("AGENTCORE_RUNTIME_ARN not set in /etc/agentcore-ui.env")
        return

    scenarios_t, chat_t, tool_t, mcp_t = st.tabs(
        ["Scenarios", "Chat", "Tool (GitHub)", "MCP"]
    )
    with scenarios_t:
        scenarios_tab()
    with chat_t:
        chat_tab()
    with tool_t:
        tool_tab()
    with mcp_t:
        mcp_tab()


if __name__ == "__main__":
    main()
