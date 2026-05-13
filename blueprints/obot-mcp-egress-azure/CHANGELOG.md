# Changelog

## 2026-05-13

- Add: `k8s-firewall` Helm chart (AviatrixSystems/k8s-firewall-charts v9.0.0) installs `firewallpolicies.networking.aviatrix.com` and `webgrouppolicies.networking.aviatrix.com` CRDs before NPC starts; NPC crashes without them (ported from obot-mcp-egress-aws fix)
- Fix: `obot_system_pods` SmartGroup converted from CIDR `/32` workaround to K8s namespace selector (`type = "k8s"`, `k8s_namespace = var.obot_namespace`). V1 policy list accepts K8s namespace SmartGroups as `src_smart_groups` when the selector includes cluster and namespace — no CIDR tracking required.
- Remove: `obot_system_pod_cidrs` variable, `obot_system_pod_cidrs_effective` local, and the two-step deploy pattern. Single-apply deploy restored.
- Add: full MCP server create+launch workflow to test scenarios with SERVER_ID/POD variable setup and container selector pattern
- Add: namespace finalizer cleanup instructions to Cleanup section

## 2026-05-01

- Initial release
- Tested with Controller 8.2.x, Aviatrix provider 8.2.0, Obot 0.21.0
- Azure / AKS only (v1). AWS/GKE variants planned as separate blueprints.
