# Changelog

All notable changes to this Validated Containment Architecture are documented here.

## [v3] — Live validation and workload-aware policy

- **Tag-based source SmartGroup.** The agent source group now matches the workload by CSP tag (`type = "vm"`, `Role = openclaw-agent-harness`) instead of a static subnet CIDR, so policy follows the workload. Configurable via `agent_workload_tag_key` / `agent_workload_tag_value`. The DNS-resolver and east-west groups remain CIDR-based by design.
- **Fixed `user_data` templatefile parsing.** Embedded shell `${...}` expressions are escaped as `$${...}` so `terraform plan`/`apply` no longer fail on bash variables.
- **Fixed SNAT vs. private default route.** `program_private_default_route` now defaults to `false`. With `single_ip_snat = true`, the egress Spoke Gateway already programs the private subnet default route to its own ENI; enabling both is rejected by the controller (`AVXERR-TRANSIT-EDIT-0056`). A plan-time precondition blocks the unsafe combination.
- **Shared-controller safety for the global DCF flag.** `aviatrix_distributed_firewalling_config` is now gated behind `manage_controller_policy`, so a shared-controller deploy never toggles (or, on destroy, disables) Distributed Cloud Firewall controller-wide.
- **Secret hygiene.** `.gitignore` now excludes saved plans (`tfplan*`, `*.bin`), `plan-output.txt`, state files, and `terraform.tfvars` — all of which can contain secrets.
- **VCA framing.** README reframed as a Validated Containment Architecture with an explicit monitor → validate → lock-down adoption workflow, harness-agnostic (OpenClaw / Hermes / NemoClaw / your own).

## [v2] — Production-readiness hardening

- Added private interface VPC endpoints (SSM, SSM Messages, EC2 Messages, CloudWatch Logs, STS) and an optional S3 gateway endpoint for reliable SSM access without internet egress.
- Added explicit VPC DNS resolver allow rules before the external DNS deny rules; blocks both UDP/53 and TCP/53 external resolver paths in enforce mode.
- Added an optional HTTPS OS/update WebGroup; disabled first-boot `apt` by default.
- Added `install_mode = "hermes"` and a dedicated NemoHermes staged installer.
- Added non-interactive NemoClaw/Hermes guardrails (`auto_accept_third_party_software`) and Terraform preconditions.
- Replaced placeholder domains with conditional WebGroups and conditional policy blocks.
- Added `manage_controller_policy` so central platform teams can merge policy instead of clobbering controller-level DCF resources.
- Added Makefile, preflight script, route checker, examples, GitHub Actions static validation, and supporting docs.

## [v1] — Initial reference blueprint

- Private AWS VM for OpenClaw/Hermes/NemoClaw terminal workflows, no public IP, SSM-only access.
- Aviatrix Spoke Gateway in the VPC egress path with Distributed Cloud Firewall.
- SmartGroups, WebGroups, ordered DCF policies, and a POST_RULES default action.
- CoPilot/FlowIQ logging and VPC Flow Logs.
