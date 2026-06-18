#!/usr/bin/env python3
"""Generate an Aviatrix FirewallPolicy CRD for least-privilege LibreChat egress.

Reads librechat.yaml (+ env-key signals) and a static domain catalog, resolves the
set of domains the current config actually requires, and renders a FirewallPolicy CRD.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
from urllib.parse import urlparse

import yaml

DEFAULT_CATALOG = Path(__file__).parent / "egress-catalog.yaml"
INTERNAL_HOSTS = {"localhost", "127.0.0.1", "host.docker.internal"}
PLACEHOLDER_PREFIXES = ("your_", "YOUR_", "<")


def load_catalog(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


@dataclass(frozen=True)
class McpServer:
    name: str
    type: Optional[str]
    url: Optional[str]
    command: Optional[str]


@dataclass
class LibreChatConfig:
    bedrock_regions: List[str] = field(default_factory=list)
    custom_base_urls: List[str] = field(default_factory=list)
    mcp_servers: List[McpServer] = field(default_factory=list)


def parse_config(path: Path) -> LibreChatConfig:
    if not path.exists():
        raise FileNotFoundError(f"librechat config not found: {path}")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    except yaml.YAMLError as exc:
        raise ValueError(f"malformed YAML in {path}: {exc}") from exc

    endpoints = data.get("endpoints") or {}
    bedrock = endpoints.get("bedrock") or {}
    bedrock_regions = list(bedrock.get("availableRegions") or [])

    custom_base_urls = [
        c["baseURL"]
        for c in (endpoints.get("custom") or [])
        if isinstance(c, dict) and c.get("baseURL")
    ]

    mcp_servers: List[McpServer] = []
    for name, spec in (data.get("mcpServers") or {}).items():
        spec = spec or {}
        mcp_servers.append(
            McpServer(
                name=name,
                type=spec.get("type"),
                url=spec.get("url"),
                command=spec.get("command"),
            )
        )

    return LibreChatConfig(
        bedrock_regions=bedrock_regions,
        custom_base_urls=custom_base_urls,
        mcp_servers=mcp_servers,
    )


def is_set(value: str) -> bool:
    value = (value or "").strip()
    if not value:
        return False
    return not value.startswith(PLACEHOLDER_PREFIXES)


def parse_env_file(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):]
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            values[key] = val
    return values


def extract_hostname(url: str) -> Optional[str]:
    try:
        parsed = urlparse(url)
    except (ValueError, AttributeError):
        return None
    if not parsed.scheme or not parsed.hostname:
        return None
    return parsed.hostname


def classify_mcp(server: McpServer) -> str:
    is_stdio = server.type == "stdio" or (server.type is None and server.command)
    if is_stdio:
        cmd = (server.command or "").strip()
        if cmd in ("uvx", "npx"):
            return f"stdio:{cmd}"
        return "stdio:other"

    # remote (sse / streamable-http / websocket, or untyped with url)
    if not server.url:
        return "unparseable"
    host = extract_hostname(server.url)
    if host is None:
        return "unparseable"
    if host in INTERNAL_HOSTS:
        return "internal"
    return "remote"


@dataclass
class DomainGroup:
    comment: str
    domains: List[str] = field(default_factory=list)


@dataclass
class ResolveResult:
    groups: List[DomainGroup] = field(default_factory=list)
    notes: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    has_subprocess_mcp: bool = False


def format_warning(name: str, command: str, domains: List[str]) -> str:
    added = ", ".join(domains) if domains else "(none)"
    return (
        f"WARNING: mcpServers.{name} uses '{command}' (subprocess). "
        f"Package registry egress required.\n"
        f"  Added domains: {added}\n"
        f"  Recommendation: Deploy as a standalone workload via Aviatrix OBOT VCA "
        f"for workload-level isolation.\n"
        f"  Reference: https://docs.aviatrix.com/docs/enterprise/8.2/guides/security/"
        f"egress/mcp-egress-containment-self-hosted"
    )


def resolve_domains(
    config: LibreChatConfig,
    catalog: dict,
    set_keys: Set[str],
    env_values: Dict[str, str],
) -> ResolveResult:
    result = ResolveResult()
    seen: Set[str] = set()

    def add_group(comment: str, domains: List[str]) -> None:
        deduped = [d for d in domains if d and d not in seen]
        for d in deduped:
            seen.add(d)
        if deduped:
            result.groups.append(DomainGroup(comment=comment, domains=deduped))

    # 1. Bedrock. The LibreChat pod has no unconditional egress, so nothing is
    #    "always on" — image-registry pulls happen on the node (kubelet), not
    #    from the pod, so they are NOT governed by this pod-scoped policy.
    #    STS is required only for Bedrock (IRSA token exchange), so it is gated
    #    on Bedrock actually being enabled rather than emitted unconditionally.
    bedrock_domains = [f"bedrock-runtime.{r}.amazonaws.com" for r in config.bedrock_regions]
    default_region = env_values.get("BEDROCK_AWS_DEFAULT_REGION")
    if default_region:
        candidate = f"bedrock-runtime.{default_region}.amazonaws.com"
        if candidate not in bedrock_domains:
            bedrock_domains.append(candidate)
    if bedrock_domains:
        sts_domains = list((catalog.get("bedrock") or {}).get("sts_domains") or [])
        add_group("bedrock sts (IRSA)", sts_domains)
    add_group("bedrock runtime", bedrock_domains)

    # 3. custom endpoints
    custom_hosts = [h for h in (extract_hostname(u) for u in config.custom_base_urls) if h]
    add_group("custom endpoints", custom_hosts)

    # 4. remote MCP servers
    remote_hosts: List[str] = []
    for server in config.mcp_servers:
        kind = classify_mcp(server)
        if kind == "remote":
            host = extract_hostname(server.url)
            if host:
                remote_hosts.append(host)
        elif kind == "internal":
            result.notes.append(f"(skipped internal MCP {server.name}: {server.url})")
        elif kind == "unparseable":
            result.warnings.append(
                f"WARNING: mcpServers.{server.name} has an unparseable url "
                f"({server.url!r}); skipped."
            )
    add_group("remote mcp servers", remote_hosts)

    # 5. subprocess MCP package registries
    subprocess_domains: List[str] = []
    subprocess_catalog = catalog.get("subprocess_mcp") or {}
    for server in config.mcp_servers:
        kind = classify_mcp(server)
        if not kind.startswith("stdio:"):
            continue
        result.has_subprocess_mcp = True
        cmd = kind.split(":", 1)[1]
        entry = subprocess_catalog.get(cmd)
        domains = list(entry["domains"]) if entry else []
        subprocess_domains.extend(domains)
        display_command = server.command or "(unspecified command)"
        result.warnings.append(format_warning(server.name, display_command, domains))
    add_group("subprocess mcp package registries", subprocess_domains)

    # 6. env-gated
    env_gated_domains: List[str] = []
    for key, body in (catalog.get("env_gated") or {}).items():
        if key in set_keys:
            env_gated_domains.extend(body.get("domains") or [])
    add_group("env-gated", env_gated_domains)

    return result


def file_sha(path: Optional[Path]) -> str:
    if path is None or not path.exists():
        return "absent"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return digest[:12]


def parse_pod_label(s: str) -> Tuple[str, str]:
    if "=" not in s:
        raise ValueError(f"--pod-label must be key=value, got: {s!r}")
    key, _, value = s.partition("=")
    return key.strip(), value.strip()


def render_policy(
    result: ResolveResult,
    namespace: str,
    pod_label: Tuple[str, str],
    config_sha: str,
    env_sha: str,
    default_deny: bool = True,
) -> str:
    label_key, label_value = pod_label
    lines: List[str] = []

    # Header
    lines.append("# Generated by utils/egress-policy/generate.py")
    lines.append(f"# Source: librechat.yaml (sha: {config_sha}), .env (sha: {env_sha})")
    lines.append(
        f"# Regenerate: python utils/egress-policy/generate.py "
        f"--namespace {namespace} --pod-label {label_key}={label_value}"
    )
    lines.append("# DO NOT EDIT - changes will be overwritten on next git push")
    lines.append("")

    # CRD body
    lines.append("apiVersion: networking.aviatrix.com/v1alpha1")
    lines.append("kind: FirewallPolicy")
    lines.append("metadata:")
    lines.append("  name: librechat-egress")
    lines.append(f"  namespace: {namespace}")
    lines.append("spec:")
    lines.append("  rules:")
    lines.append("    - name: allow-librechat-egress")
    lines.append("      selector:")
    lines.append("        matchLabels:")
    lines.append(f"          {label_key}: {label_value}")
    lines.append("      action: permit")
    lines.append("      protocol: tcp")
    lines.append("      port: 443")
    lines.append("      destinationSmartGroups:")
    lines.append("        - name: anywhere")
    lines.append("      webGroups:")
    lines.append("        - name: librechat-allowed-domains")
    lines.append("      logging: true")
    # Trailing per-pod default-deny: makes the policy self-enforcing instead of
    # relying on a fabric-wide default-deny. First-match ordering means the
    # permit above wins for allowed FQDNs; everything else from these pods on
    # 443 is denied. Consistent with the HTTPS-only egress model.
    if default_deny:
        lines.append("    - name: deny-other-egress")
        lines.append("      selector:")
        lines.append("        matchLabels:")
        lines.append(f"          {label_key}: {label_value}")
        lines.append("      action: deny")
        lines.append("      protocol: tcp")
        lines.append("      port: 443")
        lines.append("      destinationSmartGroups:")
        lines.append("        - name: anywhere")
        lines.append("      logging: true")
    lines.append("  smartGroups:")
    lines.append("    - name: anywhere")
    lines.append("      selectors:")
    lines.append("        - cidr: 0.0.0.0/0")
    lines.append("  webGroups:")
    lines.append("    - name: librechat-allowed-domains")
    lines.append("      domains:")
    if not result.groups:
        lines.append("        # (no domains resolved — this policy permits no egress)")
    for group in result.groups:
        lines.append(f"        # --- {group.comment} ---")
        for domain in group.domains:
            lines.append(f'        - "{domain}"')
    if result.notes:
        lines.append("      # notes:")
        for note in result.notes:
            lines.append(f"      # {note}")

    return "\n".join(lines) + "\n"


def resolve_env(
    env_path: Optional[Path], env_keys_arg: Optional[str]
) -> Tuple[Set[str], Dict[str, str]]:
    # --env-keys overrides --env for gating; values are unknown (CI-friendly).
    if env_keys_arg is not None:
        set_keys = {k.strip() for k in env_keys_arg.split(",") if k.strip()}
        return set_keys, {}
    if env_path is None or not env_path.exists():
        return set(), {}
    env_values = parse_env_file(env_path)
    set_keys = {k for k, v in env_values.items() if is_set(v)}
    return set_keys, env_values


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate an Aviatrix FirewallPolicy CRD for LibreChat egress."
    )
    parser.add_argument("--config", default="librechat.yaml", help="Path to LibreChat config file")
    parser.add_argument("--env", default=".env", help="Path to env file (optional)")
    parser.add_argument(
        "--env-keys", default=None,
        help="Comma-separated env key names that are set; overrides --env for gating",
    )
    parser.add_argument(
        "--output", default="utils/egress-policy/firewall-policy.yaml", help="Output path"
    )
    parser.add_argument("--namespace", default="librechat", help="Kubernetes namespace")
    parser.add_argument("--pod-label", default="app=librechat", help="LibreChat pod label (key=value)")
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG), help="Path to egress-catalog.yaml")
    parser.add_argument(
        "--strict", action="store_true",
        help="Exit 1 if any subprocess MCP servers are present",
    )
    parser.add_argument(
        "--no-default-deny", dest="default_deny", action="store_false",
        help="Omit the trailing per-pod deny rule (rely on a fabric-wide default-deny instead)",
    )
    parser.set_defaults(default_deny=True)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    config_path = Path(args.config)
    catalog_path = Path(args.catalog)
    output_path = Path(args.output)
    env_path = Path(args.env) if args.env else None

    try:
        pod_label = parse_pod_label(args.pod_label)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    try:
        config = parse_config(config_path)
        catalog = load_catalog(catalog_path)
        set_keys, env_values = resolve_env(env_path, args.env_keys)
    except (ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.env_keys is None and (env_path is None or not env_path.exists()):
        print(f"NOTICE: {args.env} not found; env-gated domains skipped.", file=sys.stderr)

    result = resolve_domains(config, catalog, set_keys, env_values)

    config_sha = file_sha(config_path)
    env_sha = file_sha(env_path) if args.env_keys is None else "env-keys"
    rendered = render_policy(
        result,
        namespace=args.namespace,
        pod_label=pod_label,
        config_sha=config_sha,
        env_sha=env_sha,
        default_deny=args.default_deny,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered, encoding="utf-8")

    for warning in result.warnings:
        print(warning, file=sys.stderr)

    if args.strict and result.has_subprocess_mcp:
        print("ERROR: --strict set and subprocess MCP servers present.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
