# Pattern B: Namespace-as-a-Service — In-Cluster DCF CRDs (AWS/EKS)

## Overview

This directory contains Kubernetes manifests for namespace setup and Aviatrix DCF CRD examples for the **Namespace-as-a-Service** pattern on AWS EKS.

All teams share a single EKS cluster. Network isolation between namespaces is enforced by **Aviatrix Distributed Cloud Firewall (DCF)** via K8s namespace SmartGroups, **not** by Kubernetes RBAC alone.

## Files

| File | Description |
|------|-------------|
| `namespace-setup.yaml` | Creates team namespaces (team-a, team-b, team-c) + shared namespaces (monitoring, istio-system, cert-manager) with RBAC bindings |
| `firewallpolicy-team-a.yaml` | Team A self-service egress rules (Stripe, SendGrid APIs) |
| `firewallpolicy-team-b.yaml` | Team B self-service egress rules (CDN, analytics APIs) |
| `webgrouppolicy-team-b.yaml` | Team B reusable domain groups for CDN and static assets |

## How It Works

1. **Platform team** manages the baseline DCF ruleset via Terraform (priorities 0-60)
2. **App teams** extend their own namespace policies via CRDs deployed through GitOps (priorities 70-99)
3. The `k8s-firewall` Helm chart (installed in Layer 3) provides the CRD controller
4. CRD policies are namespace-scoped — teams can only manage rules for their own namespace

## Priority Layout

| Priority | Owner | Description |
|----------|-------|-------------|
| 0-1 | Platform | Geo-block + ThreatIQ |
| 5 | Platform | Monitoring scrape permissions |
| 10 | Platform | Approved cross-namespace calls |
| 50-55 | Platform | Namespace isolation (deny rules) |
| 60 | Platform | Egress via WebGroups (EKS required) |
| 70-99 | App Teams | CRD-managed self-service rules |

## Important

- **RBAC is NOT a hard security boundary** — it prevents accidental access but can be bypassed. DCF enforces network isolation at the infrastructure level.
- `k8s_cluster_id` is required alongside `k8s_namespace` in SmartGroups to prevent cross-cluster namespace collisions.

## Optional Hardening

The nodes layer includes opt-in recommendation toggles that complement DCF:

```hcl
# nodes/shared/terraform.tfvars
enable_network_policy   = true   # Calico NetworkPolicy (defense-in-depth alongside DCF)
enable_gatekeeper       = true   # OPA Gatekeeper (enforce image policies, resource limits)
enable_external_secrets = true   # Sync secrets from AWS Secrets Manager
enable_falco            = true   # Runtime threat detection
enable_prometheus_stack = true   # Monitoring (Prometheus + Grafana)
enable_fluent_bit       = true   # Log aggregation to CloudWatch
```

See `ARCHITECTURE-ANALYSIS.md` for full toggle reference and rationale.
