# Changelog

## 2026-05-15

- Confirm: K8S_POLICY_LIST per-pod enforcement works on AKS **1.34.4**, broken on AKS **1.34.7**. Root cause: AKS 1.34.7 `ListClusterUserCredentials` returns exec-based kubeconfig; Aviatrix CAI rejects exec credentials (`"exec and auth provider are not supported"`). AKS 1.34.4 returns cert-based kubeconfig; CAI accepts it and starts K8s watcher. Same controller build `8.2.0-1000.2196` on both. Tested: `httpbin.org` (egressDomains) → HTTP:200; `example.com` (blocked) → exit:35.
- Add: `aks_kubernetes_version` variable (optional, default `null`). Set to `"1.34.4"` in tfvars as workaround for AKS 1.34.7 exec-creds bug (AVX-76221 related). Pending Aviatrix fix to switch `ListClusterUserCredentials` → `ListClusterAdminCredentials`.
- Note: `aks_kube_config` variable (explicit kubeconfig workaround) NOT required when using AKS 1.34.4. Retained as fallback option for operators who cannot downgrade AKS version.

## 2026-05-14 (update 2)

- Add: `aks_kube_config` variable for explicit K8s admin kubeconfig. Required for K8S_POLICY_LIST per-pod enforcement. Aviatrix controller kubeconfig validation schema requires `preferences: {}` field which `az aks get-credentials` omits — add it manually before use. Without this, the Aviatrix CAI service uses `ListClusterUserCredentials` which returns exec-based credentials rejected by CAI ("exec and auth provider are not supported") on AKS 1.24+.
- Fix: `aviatrix_kubernetes_cluster.aks` now supports both `use_csp_credentials` (when `aks_kube_config` is empty) and explicit kubeconfig (when set). Kubeconfig path uses `internal/k8s/client/kubeconfig/client.go` in the CAI — cert-based, no exec dependency.
- Note: K8S_POLICY_LIST enforcement confirmed broken on AKS 1.34.7 without explicit kubeconfig. Lab cluster (`8.2.0-1000.2196`) works via cert-based path. Blueprint test controller may require Aviatrix support to verify CAI watcher startup after cluster re-registration.

## 2026-05-14

- Fix: `aviatrix_kubernetes_cluster.aks` cluster_id no longer lowercased (`lower()` caused CoPilot Kubernetes Clusters onboard API to return HTTP 500, blocking K8S_POLICY_LIST enforcement)
- Fix: `aviatrix_kubernetes_cluster.aks` switched from `use_csp_credentials = true` to `kube_config = azurerm_kubernetes_cluster.obot.kube_admin_config_raw` for explicit kubeconfig-based authentication
- Add: `azurerm_role_assignment.aviatrix_aks_admin` — grants Aviatrix ARM service principal `Azure Kubernetes Service Cluster Admin Role` on the AKS cluster; required for kube_admin_config_raw retrieval and CoPilot Kubernetes Clusters onboarding
- Add: `arm_account_principal_id` variable (Azure AD Object ID of Aviatrix ARM SP)
- Fix: `null_resource.k8s_dcf_features` reverted to 5 flags (removed erroneous `k8s_enforcement` addition); triggers block simplified back to controller_ip only
- Add: Step 4.3 (Kubernetes Clusters Onboard) to README deployment guide
- Add: `arm_account_principal_id` to README Variables table
- Docs: TESTING.md updated with arm_account_principal_id instructions, Step 6 for K8s workload discovery verification, new failure points for AKS-specific issues

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
