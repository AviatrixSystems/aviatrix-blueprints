# Changelog

## 2026-05-13

- Fix: `obot_system_pods` SmartGroup converted from CIDR `/32` workaround to K8s namespace selector (`type = "k8s"`, `k8s_namespace = var.obot_namespace`). V1 policy list accepts K8s namespace SmartGroups as `src_smart_groups` when the selector includes cluster and namespace — no CIDR tracking required.
- Remove: `obot_system_pod_cidrs` variable, `obot_system_pod_cidrs_effective` local, and the two-step deploy pattern. Single-apply deploy restored.

## 2026-05-01

- Initial release
- Tested with Controller 8.2.x, Aviatrix provider 8.2.0, Obot 0.21.0
- Azure / AKS only (v1). AWS/GKE variants planned as separate blueprints.
