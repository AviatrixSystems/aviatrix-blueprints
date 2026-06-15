from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))
import generate  # noqa: E402


def test_load_catalog_has_required_sections(catalog_path):
    catalog = generate.load_catalog(catalog_path)
    assert set(catalog.keys()) >= {"always_on", "env_gated", "subprocess_mcp"}
    assert "registry.librechat.ai" in catalog["always_on"]["image_registry"]["domains"]
    assert catalog["subprocess_mcp"]["uvx"]["domains"] == ["pypi.org", "files.pythonhosted.org"]


def test_parse_config_bedrock_custom_and_mcp(tmp_path):
    cfg_text = """
version: 1.2.8
endpoints:
  bedrock:
    availableRegions:
      - us-east-1
      - us-west-2
  custom:
    - name: groq
      baseURL: https://api.groq.com/openai/v1/
    - name: OpenRouter
      baseURL: https://openrouter.ai/api/v1
mcpServers:
  remote-sse:
    type: sse
    url: https://mcp.example.com/sse
  local-fetch:
    type: stdio
    command: uvx
    args: ["mcp-server-fetch"]
"""
    p = tmp_path / "librechat.yaml"
    p.write_text(cfg_text)
    cfg = generate.parse_config(p)
    assert cfg.bedrock_regions == ["us-east-1", "us-west-2"]
    assert cfg.custom_base_urls == ["https://api.groq.com/openai/v1/", "https://openrouter.ai/api/v1"]
    assert [s.name for s in cfg.mcp_servers] == ["remote-sse", "local-fetch"]
    assert cfg.mcp_servers[0].type == "sse" and cfg.mcp_servers[0].url == "https://mcp.example.com/sse"
    assert cfg.mcp_servers[1].command == "uvx"


def test_parse_config_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        generate.parse_config(tmp_path / "nope.yaml")


def test_parse_config_empty_sections(tmp_path):
    p = tmp_path / "librechat.yaml"
    p.write_text("version: 1.2.8\n")
    cfg = generate.parse_config(p)
    assert cfg.bedrock_regions == []
    assert cfg.custom_base_urls == []
    assert cfg.mcp_servers == []


def test_is_set_rules():
    assert generate.is_set("sk-real-key") is True
    assert generate.is_set("") is False
    assert generate.is_set("   ") is False
    assert generate.is_set("your_api_key") is False
    assert generate.is_set("YOUR_KEY") is False
    assert generate.is_set("<replace-me>") is False


def test_parse_env_file_strips_quotes_and_comments(tmp_path):
    env = tmp_path / ".env"
    env.write_text(
        "# comment line\n"
        "TAVILY_API_KEY=tvly-123\n"
        'WOLFRAM_APP_ID="wolf-456"\n'
        "EMPTY=\n"
        "export GITHUB_CLIENT_ID=gh-789\n"
    )
    values = generate.parse_env_file(env)
    assert values["TAVILY_API_KEY"] == "tvly-123"
    assert values["WOLFRAM_APP_ID"] == "wolf-456"
    assert values["EMPTY"] == ""
    assert values["GITHUB_CLIENT_ID"] == "gh-789"


def test_resolve_env_from_file(tmp_path):
    env = tmp_path / ".env"
    env.write_text("TAVILY_API_KEY=tvly-123\nWOLFRAM_APP_ID=your_app_id\nBEDROCK_AWS_DEFAULT_REGION=eu-west-1\n")
    set_keys, env_values = generate.resolve_env(env, None)
    assert "TAVILY_API_KEY" in set_keys
    assert "WOLFRAM_APP_ID" not in set_keys  # placeholder
    assert env_values["BEDROCK_AWS_DEFAULT_REGION"] == "eu-west-1"


def test_resolve_env_from_keys_arg_overrides_file():
    set_keys, env_values = generate.resolve_env(None, "TAVILY_API_KEY, GITHUB_CLIENT_ID")
    assert set_keys == {"TAVILY_API_KEY", "GITHUB_CLIENT_ID"}
    assert env_values == {}  # values unknown in --env-keys mode
