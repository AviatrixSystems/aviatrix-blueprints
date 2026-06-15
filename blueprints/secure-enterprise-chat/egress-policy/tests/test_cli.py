from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))
import generate  # noqa: E402

MINIMAL = """
endpoints:
  bedrock:
    availableRegions: [us-east-1]
mcpServers:
  remote:
    type: streamable-http
    url: https://mcp.example.com/
"""

SUBPROC = """
mcpServers:
  py:
    type: stdio
    command: uvx
    args: ["mcp-server-fetch"]
"""


def _write(tmp_path, text):
    p = tmp_path / "librechat.yaml"
    p.write_text(text)
    return p


def test_main_writes_output_and_returns_zero(tmp_path, capsys):
    cfg = _write(tmp_path, MINIMAL)
    out = tmp_path / "firewall-policy.yaml"
    rc = generate.main([
        "--config", str(cfg), "--output", str(out),
        "--catalog", str(Path(__file__).parent.parent / "egress-catalog.yaml"),
        "--namespace", "librechat", "--pod-label", "app=librechat",
    ])
    assert rc == 0
    body = out.read_text()
    assert "bedrock-runtime.us-east-1.amazonaws.com" in body
    assert "mcp.example.com" in body


def test_main_missing_config_returns_one(tmp_path, capsys):
    rc = generate.main(["--config", str(tmp_path / "nope.yaml"),
                        "--output", str(tmp_path / "o.yaml"),
                        "--catalog", str(Path(__file__).parent.parent / "egress-catalog.yaml")])
    assert rc == 1
    assert "not found" in capsys.readouterr().err


def test_main_strict_with_subprocess_returns_one(tmp_path, capsys):
    cfg = _write(tmp_path, SUBPROC)
    out = tmp_path / "o.yaml"
    rc = generate.main([
        "--config", str(cfg), "--output", str(out), "--strict",
        "--catalog", str(Path(__file__).parent.parent / "egress-catalog.yaml"),
    ])
    assert rc == 1
    err = capsys.readouterr().err
    assert "uvx" in err
    # Output is still written even under strict
    assert out.exists() and "pypi.org" in out.read_text()


def test_main_env_keys_gates_domains(tmp_path):
    cfg = _write(tmp_path, MINIMAL)
    out = tmp_path / "o.yaml"
    rc = generate.main([
        "--config", str(cfg), "--output", str(out),
        "--catalog", str(Path(__file__).parent.parent / "egress-catalog.yaml"),
        "--env-keys", "TAVILY_API_KEY",
    ])
    assert rc == 0
    assert "api.tavily.com" in out.read_text()


def test_main_bad_pod_label_returns_one(tmp_path, capsys):
    cfg = _write(tmp_path, MINIMAL)
    rc = generate.main([
        "--config", str(cfg), "--output", str(tmp_path / "o.yaml"),
        "--catalog", str(Path(__file__).parent.parent / "egress-catalog.yaml"),
        "--pod-label", "noequals",
    ])
    assert rc == 1
    assert "pod-label" in capsys.readouterr().err


def test_main_absent_env_prints_notice(tmp_path, capsys):
    cfg = _write(tmp_path, MINIMAL)
    rc = generate.main([
        "--config", str(cfg), "--output", str(tmp_path / "o.yaml"),
        "--catalog", str(Path(__file__).parent.parent / "egress-catalog.yaml"),
        "--env", str(tmp_path / "nonexistent.env"),
    ])
    assert rc == 0
    assert "NOTICE" in capsys.readouterr().err


def test_main_no_default_deny_flag(tmp_path):
    cfg = _write(tmp_path, MINIMAL)
    out = tmp_path / "o.yaml"
    rc = generate.main([
        "--config", str(cfg), "--output", str(out),
        "--catalog", str(Path(__file__).parent.parent / "egress-catalog.yaml"),
        "--env-keys", "", "--no-default-deny",
    ])
    assert rc == 0
    assert "deny-other-egress" not in out.read_text()
