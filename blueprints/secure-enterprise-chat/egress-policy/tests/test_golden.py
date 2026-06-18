from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))
import generate  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"
CATALOG = Path(__file__).parent.parent / "egress-catalog.yaml"

# Golden files are frozen output. To update one after an intentional change:
#   python generate.py --config tests/fixtures/<case>/librechat.yaml \
#     --output tests/fixtures/<case>/expected-firewall-policy.yaml \
#     --namespace librechat --pod-label app=librechat [--env ... | --env-keys ...]
# then review the diff.


def _run(case_dir, extra_args, tmp_path):
    out = tmp_path / "actual-firewall-policy.yaml"
    argv = [
        "--config", str(case_dir / "librechat.yaml"),
        "--output", str(out),
        "--catalog", str(CATALOG),
        "--namespace", "librechat",
        "--pod-label", "app=librechat",
    ] + extra_args
    rc = generate.main(argv)
    actual = out.read_text() if out.exists() else ""
    return rc, actual


def test_golden_minimal(tmp_path):
    rc, actual = _run(FIXTURES / "minimal", ["--env-keys", ""], tmp_path)
    expected = (FIXTURES / "minimal" / "expected-firewall-policy.yaml").read_text()
    assert actual == expected
    assert rc == 0


def test_golden_full(tmp_path):
    rc, actual = _run(FIXTURES / "full", ["--env", str(FIXTURES / "full" / "env.sample")], tmp_path)
    expected = (FIXTURES / "full" / "expected-firewall-policy.yaml").read_text()
    assert actual == expected
    assert rc == 0


def test_golden_subprocess(tmp_path):
    rc, actual = _run(FIXTURES / "subprocess", ["--env-keys", "", "--strict"], tmp_path)
    expected = (FIXTURES / "subprocess" / "expected-firewall-policy.yaml").read_text()
    assert actual == expected
    assert rc == 1  # --strict + subprocess MCP present
