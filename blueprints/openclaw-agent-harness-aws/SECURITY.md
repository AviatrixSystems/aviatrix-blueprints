# Security Model

## Boundary

The trusted enforcement boundary is the Aviatrix Spoke Gateway and Distributed Cloud Firewall policy, not the agent runtime. The VM is treated as a potentially compromised non-human operator with delegated access.

## Controls

- No public IP on the agent VM.
- No inbound security group rules.
- SSM Session Manager for access.
- Private route table has no native NAT Gateway or IGW route.
- Default route is programmed through the Aviatrix Spoke Gateway.
- SmartGroup identifies the agent source subnet.
- WebGroups define approved external destinations.
- Explicit shadow-model deny precedes allow rules.
- Explicit VPC DNS allow precedes DNS exfil deny.
- East-west deny limits lateral movement.
- POST_RULES default action catches unknown destinations.
- VPC Flow Logs and CoPilot FlowIQ provide investigation data.
- Instance metadata is hardened: IMDSv2 is required (`http_tokens = "required"`) with `http_put_response_hop_limit = 1`, so a compromised agent or container cannot reach the metadata endpoint (169.254.169.254) to steal the instance role's credentials. (IMDS is link-local and does not traverse the gateway, so this is a host-level control rather than a DCF egress rule.)

## Incident workflow

1. Filter CoPilot FlowIQ by `<name_prefix>-sg-agent-workload`.
2. Identify the named deny/default rule that fired.
3. Confirm whether the destination was expected, malicious, or an attempted bypass.
4. If legitimate, add the exact FQDN to the narrowest WebGroup variable by pull request.
5. If malicious, keep deny in place and rotate any credentials reachable by the agent.

## Hardening recommendations

- Use an enterprise model gateway instead of direct model-provider APIs.
- Disable `enable_package_installs` after bootstrap for regulated workflows.
- Keep `enable_public_reference=false` for sensitive data.
- Use a baked AMI or private HTTPS package mirror for enforce-from-first-boot production.
- Centralize DCF ownership if multiple blueprints share one Aviatrix Controller.
