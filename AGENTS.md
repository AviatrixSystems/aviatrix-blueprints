# Agent Context: Aviatrix Blueprints

This repository contains production-ready Terraform lab environments ("blueprints") for the Aviatrix Cloud Native Security Fabric (CNSF) — Distributed Cloud Firewall (DCF), workload segmentation, and Zero Trust enforcement. Each blueprint is self-contained and deployable.

This file is the agent-agnostic entry point (Cursor, Claude Code, and other AGENTS.md-aware tools). **`CLAUDE.md` is the full source of truth** for repository conventions — read it before making changes.

## Fast Orientation

- **Blueprints live in** `blueprints/<name>/`. Copy `blueprints/_template/` to start a new one.
- **Per-blueprint `AGENTS.md`** gives the fast path for autonomous deployment (Required Variables, Deploy Sequence, Verification, Common Errors, Constraints).
- **State is local only.** Never add a remote backend (`backend "s3"`, etc.) to a blueprint.
- **Standards:** `docs/blueprint-standards.md` defines required README sections; `CONTRIBUTING.md` defines the workflow.

## Non-Negotiable Conventions

- Use `var.name_prefix` for resource naming; never hardcode regions, account IDs, or credentials.
- Mark secrets with `sensitive = true`.
- Pin provider versions in `versions.tf` (Aviatrix provider source: `AviatrixSystems/aviatrix`).
- Aviatrix cloud type codes: `1`=AWS, `2`=GCP, `4`=Azure, `8`=OCI.
- Multi-layer blueprints deploy foundation → dependent layers, and **destroy in reverse order**.

## Validate Before Committing

```bash
cd blueprints/<name>
terraform fmt -recursive
terraform init -backend=false
terraform validate
```

## Recommended Tooling

- **MCP servers** (Terraform registry, GitHub, Serena): see `.claude/mcp-servers.example.json` (Claude Code) or `.cursor/mcp.json` (Cursor).
- **Browser-based verification**: use the `agent-browser` skill for driving the Aviatrix CoPilot/Controller UI. The Playwright MCP server is an optional alternative.

See `CONTRIBUTING.md` for the full contribution workflow (clone vs. fork, branching, PRs).
