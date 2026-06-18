# Changelog

## 2026-05-13

- Add: `k8s-firewall` Helm chart (AviatrixSystems/k8s-firewall-charts v9.0.0) installs `firewallpolicies.networking.aviatrix.com` and `webgrouppolicies.networking.aviatrix.com` CRDs; NPC crashes on startup without these
- Fix: corrected EKS access entry principal from `aviatrix-role-ec2` to `aviatrix-role-app`; `aviatrix-role-app` is the role CoPilot assumes for K8s API calls (not the EC2 instance profile)
- Fix: EKS access policy set to `AmazonEKSClusterAdminPolicy`; `AmazonEKSViewPolicy` alone is insufficient — CoPilot needs write access to list cluster metadata; access entry created before `aviatrix_kubernetes_cluster` to prevent Fail state
- Add: `view-nodes` ClusterRole and ClusterRoleBinding for node enumeration (CoPilot requires this beyond the EKS managed policy scope)
- Add: `aviatrix-crd-view` ClusterRole granting `get/list/watch` on `networking.aviatrix.com` CRDs (required for CoPilot to display NPC-reconciled policy status)
- Remove: `aviatrix_kubernetes_cluster` Terraform resource — controller auto-discovers EKS clusters in onboarded accounts; explicit registration always fails with HTTP 409 conflicting configuration
- Rename: variable `aviatrix_controller_role_arn` → `aviatrix_app_role_arn` (clearer distinction from EC2 instance profile role)
- Fix: `node_desired_size` default restored to `2` (was incorrectly set to `0`, which blocked CoreDNS and caused IRSA/STS failures for EBS CSI driver)

## 2026-05-12

- Initial release
- Tested with Controller 8.2.x, Aviatrix provider 8.2.0, Obot 0.21.0, EKS 1.32
- AWS / EKS implementation of the obot-mcp-egress pattern (companion to obot-mcp-egress-azure)
- Known limitation: K8s label SmartGroups register as Partial on EKS; V1 CIDR /32 workaround required for per-pod deny enforcement. Tracked in docs/stp-eks-dcf-per-pod-enforcement.md.
