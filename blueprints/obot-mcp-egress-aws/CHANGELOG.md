# Changelog

## 2026-05-12

- Initial release
- Tested with Controller 8.2.x, Aviatrix provider 8.2.0, Obot 0.21.0, EKS 1.32
- AWS / EKS implementation of the obot-mcp-egress pattern (companion to obot-mcp-egress-azure)
- Known limitation: K8s label SmartGroups register as Partial on EKS; V1 CIDR /32 workaround required for per-pod deny enforcement. Tracked in docs/stp-eks-dcf-per-pod-enforcement.md.
