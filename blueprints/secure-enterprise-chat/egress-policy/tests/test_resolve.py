from pathlib import Path
import sys
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))
import generate  # noqa: E402


def test_extract_hostname():
    assert generate.extract_hostname("https://mcp.example.com/sse") == "mcp.example.com"
    assert generate.extract_hostname("https://api.groq.com/openai/v1/") == "api.groq.com"
    assert generate.extract_hostname("http://host.docker.internal:3001/mcp") == "host.docker.internal"
    assert generate.extract_hostname("not a url") is None
    assert generate.extract_hostname("https://[::1]:443/x") == "::1"


def test_classify_mcp_by_type():
    assert generate.classify_mcp(generate.McpServer("a", "sse", "https://x.com/sse", None)) == "remote"
    assert generate.classify_mcp(generate.McpServer("b", "streamable-http", "https://x.com/", None)) == "remote"
    assert generate.classify_mcp(generate.McpServer("c", "stdio", None, "uvx")) == "stdio:uvx"
    assert generate.classify_mcp(generate.McpServer("d", "stdio", None, "npx")) == "stdio:npx"
    assert generate.classify_mcp(generate.McpServer("e", "stdio", None, "python")) == "stdio:other"


def test_classify_mcp_internal_and_unparseable():
    assert generate.classify_mcp(generate.McpServer("f", "sse", "http://localhost:3001/mcp", None)) == "internal"
    assert generate.classify_mcp(generate.McpServer("g", None, "http://host.docker.internal:9121/mcp", None)) == "internal"
    assert generate.classify_mcp(generate.McpServer("h", "sse", "garbage", None)) == "unparseable"


def test_classify_mcp_falls_back_to_url_command_when_type_absent():
    assert generate.classify_mcp(generate.McpServer("i", None, "https://x.com/sse", None)) == "remote"
    assert generate.classify_mcp(generate.McpServer("j", None, None, "uvx")) == "stdio:uvx"


@pytest.fixture
def catalog():
    return generate.load_catalog(Path(__file__).parent.parent / "egress-catalog.yaml")


def _flat(result):
    return [d for g in result.groups for d in g.domains]


def test_resolve_orders_and_dedupes(catalog):
    cfg = generate.LibreChatConfig(
        bedrock_regions=["us-east-1", "us-west-2"],
        custom_base_urls=["https://api.groq.com/openai/v1/"],
        mcp_servers=[
            generate.McpServer("remote", "sse", "https://mcp.example.com/sse", None),
            generate.McpServer("internal", "sse", "http://host.docker.internal:3001/mcp", None),
            generate.McpServer("py", "stdio", None, "uvx"),
        ],
    )
    result = generate.resolve_domains(cfg, catalog, {"TAVILY_API_KEY"}, {})
    flat = _flat(result)
    # Bedrock is enabled, so STS (IRSA) leads, then the runtime endpoints.
    assert flat[0] == "sts.amazonaws.com"
    # Container image-registry domains are NOT in a pod-scoped policy.
    assert "registry.librechat.ai" not in flat
    assert "bedrock-runtime.us-east-1.amazonaws.com" in flat
    assert "bedrock-runtime.us-west-2.amazonaws.com" in flat
    assert "api.groq.com" in flat
    assert "mcp.example.com" in flat
    assert "pypi.org" in flat and "files.pythonhosted.org" in flat
    assert "api.tavily.com" in flat
    assert "api.openweathermap.org" not in flat
    assert "host.docker.internal" not in flat
    assert any("host.docker.internal" in n for n in result.notes)
    assert result.has_subprocess_mcp is True
    assert any("uvx" in w for w in result.warnings)
    assert len(flat) == len(set(flat))


def test_resolve_bedrock_default_region_from_env(catalog):
    cfg = generate.LibreChatConfig(bedrock_regions=["us-east-1"], custom_base_urls=[], mcp_servers=[])
    result = generate.resolve_domains(cfg, catalog, set(), {"BEDROCK_AWS_DEFAULT_REGION": "eu-west-1"})
    flat = _flat(result)
    assert "bedrock-runtime.us-east-1.amazonaws.com" in flat
    assert "bedrock-runtime.eu-west-1.amazonaws.com" in flat


def test_resolve_unparseable_remote_warns(catalog):
    cfg = generate.LibreChatConfig(
        bedrock_regions=[], custom_base_urls=[],
        mcp_servers=[generate.McpServer("bad", "sse", "::::", None)],
    )
    result = generate.resolve_domains(cfg, catalog, set(), {})
    assert any("bad" in w for w in result.warnings)


def test_resolve_stdio_other_warns_no_domains(catalog):
    cfg = generate.LibreChatConfig(
        bedrock_regions=[], custom_base_urls=[],
        mcp_servers=[generate.McpServer("weird", "stdio", None, "python")],
    )
    result = generate.resolve_domains(cfg, catalog, set(), {})
    flat = _flat(result)
    assert "pypi.org" not in flat and "registry.npmjs.org" not in flat
    assert any("weird" in w for w in result.warnings)
    assert result.has_subprocess_mcp is True


def test_resolve_stdio_missing_command_warning_is_readable(catalog):
    cfg = generate.LibreChatConfig(
        bedrock_regions=[], custom_base_urls=[],
        mcp_servers=[generate.McpServer("nocmd", "stdio", None, None)],
    )
    result = generate.resolve_domains(cfg, catalog, set(), {})
    assert result.has_subprocess_mcp is True
    joined = "\n".join(result.warnings)
    assert "nocmd" in joined
    assert "uses 'other'" not in joined  # catalog key must not leak as the command


def test_resolve_degenerate_mcp_server_is_safe(catalog):
    cfg = generate.LibreChatConfig(
        bedrock_regions=[], custom_base_urls=[],
        mcp_servers=[generate.McpServer("empty", None, None, None)],
    )
    result = generate.resolve_domains(cfg, catalog, set(), {})
    # a server with no url and no command classifies as unparseable: a warning, no crash
    assert any("empty" in w for w in result.warnings)


def test_resolve_sts_gated_on_bedrock(catalog):
    # No Bedrock -> no STS, and no image-registry domains.
    none = _flat(generate.resolve_domains(
        generate.LibreChatConfig(bedrock_regions=[], custom_base_urls=[], mcp_servers=[]),
        catalog, set(), {}))
    assert "sts.amazonaws.com" not in none
    assert "registry.librechat.ai" not in none
    # Bedrock enabled -> STS present.
    on = _flat(generate.resolve_domains(
        generate.LibreChatConfig(bedrock_regions=["us-east-1"], custom_base_urls=[], mcp_servers=[]),
        catalog, set(), {}))
    assert "sts.amazonaws.com" in on
