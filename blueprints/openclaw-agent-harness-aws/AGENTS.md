# AGENTS.md — OpenClaw/Hermes/NemoClaw AWS egress blueprint

## Objective

Deploy an AWS private VM for OpenClaw/Hermes/NemoClaw terminal workflows. Route all outbound traffic through an Aviatrix Spoke Gateway. Enforce egress with Aviatrix Distributed Cloud Firewall using SmartGroups, WebGroups, named policies, logging, and a POST_RULES default action.

## Safe deployment sequence

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Run `./scripts/preflight.sh` and fix missing local prerequisites.
3. Fill in Aviatrix Controller, AWS access account, and optional CoPilot values.
4. Keep `policy_mode = "monitor"` for first apply.
5. Run `terraform init`, `terraform plan`, `terraform apply`.
6. Use the `ssm_start_session` output to access the private VM.
7. Run `/opt/openclaw-vca/install-nemoclaw-openclaw.sh` or `/opt/openclaw-vca/install-openclaw.sh` after reviewing the script.
8. Observe normal destinations in CoPilot FlowIQ filtered by SmartGroup `<name_prefix>-sg-agent-vm-subnet`.
9. Add only approved FQDNs to the relevant variables by pull request.
10. Change `policy_mode = "enforce"` and apply again.
11. Run `POLICY_MODE=enforce /opt/openclaw-vca/verify-egress.sh`.

## Do not do these without changing policy first

- Add a NAT Gateway to the private route table.
- Give the agent VM a public IP.
- Add `0.0.0.0/0` inbound access to the VM.
- Route around Aviatrix with host proxies or alternate gateways.
- Put `*`, URL schemes, ports, or URL paths into WebGroup variables.
- Approve a model provider while it remains in `unapproved_model_provider_domains`.
- Reuse one broad SaaS/package WebGroup for every agent class.

## Agent-class defaults

Use these examples as copy points:

- `examples/agent-classes/locked-down.tfvars` — regulated/sensitive, no packages/reference.
- `examples/agent-classes/coding-agent.tfvars` — terminal/coding default.
- `examples/agent-classes/research-agent.tfvars` — search/reference demo.
- `examples/agent-classes/customer-support-agent.tfvars` — SaaS + MCP gateway.
- `examples/agent-classes/open-demo.tfvars` — workshop only.

## Files that matter

- `dcf.tf`: SmartGroups, WebGroups, DCF policy list, default action, CoPilot logging.
- `spoke.tf`: Aviatrix Spoke Gateway in the VPC.
- `vpc.tf`: AWS VPC, public gateway subnet, private agent subnet, flow logs.
- `vpc_endpoints.tf`: private SSM/CloudWatch Logs/STS/S3 endpoints for reliable no-public-IP operations.
- `compute.tf`: Private OpenClaw/Hermes/NemoClaw VM with SSM access only.
- `policies/openclaw-domain-catalog.yaml`: starting domain catalog and tier notes.
- `DOMAIN_TIERS.md`: reusable domain-tier policy presets.
- `SECURITY.md`: security model and incident workflow.
- `AUDIT.md`: engineering review notes and v2 changes.
- `tests/test-scenarios.md`: permit/deny validation workflow.

## Policy model

Rules are ordered:

1. Shadow model deny.
2. VPC DNS resolver allow.
3. External DNS deny for UDP/TCP 53.
4. AWS infrastructure permit for SSM/bootstrap.
5. Optional HTTPS OS/update permit. Use baked AMIs or private mirrors for strict enforce-from-first-boot.
6. Approved model gateway permit.
7. OpenClaw/NemoClaw core permit.
8. Terminal package/source-control permit.
9. Approved SaaS API permit.
10. Approved MCP/tool gateway permit.
11. Identity/telemetry permit.
12. East-west deny.
13. POST_RULES default action.

## Review checklist for pull requests

- Does the new domain belong in the narrowest WebGroup variable?
- Is the domain exact instead of a broad wildcard?
- Is the request tied to a named agent class and business function?
- If it is a model provider, has it been removed from `unapproved_model_provider_domains`?
- Is `enable_public_reference` still false for sensitive data workflows?
- Is the rollout staying in monitor mode until CoPilot evidence is reviewed?

## v2 guardrails

- Keep `manage_controller_policy = true` only for a dedicated lab controller or when this blueprint is the sole owner of DCF policy resources.
- Set `manage_controller_policy = false` when a central platform module merges DCF policies from multiple blueprints.
- Do not set `auto_run_installer = true` for NemoClaw/Hermes unless `auto_accept_third_party_software = true` and the required `NEMOCLAW_*` variables are supplied.
- Use the example tfvars files under `examples/` as starting points for repeatable agent-class deployments.
