# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — AWS CRDs

## Overview

This directory contains Kubernetes manifests for the two-layer DCF (Distributed Cloud Firewall) pattern on AWS EKS.

## Architecture

```
Production Cluster (EKS)          Non-Production Cluster (EKS)
├── team-a-prod                   ├── team-a-dev
├── team-b-prod                   ├── team-b-staging
└── monitoring                    ├── sandbox (relaxed egress)
                                  └── monitoring
```

## Two-Layer DCF

- **Layer 1 (VPC SmartGroups):** Environment isolation — prod VPC and nonprod VPC cannot communicate in either direction. DB spoke only reachable from prod VPC.
- **Layer 2 (K8s Namespace SmartGroups):** Team isolation within each cluster — teams are isolated by default with explicit allow rules via CRDs.

## Files

| File | Target Cluster | Purpose |
|------|---------------|---------|
| `prod-namespaces.yaml` | Production | Namespace definitions for prod |
| `nonprod-namespaces.yaml` | Non-Production | Namespace definitions for nonprod + sandbox |
| `firewallpolicy-prod.yaml` | Production | Strict egress rules, approved APIs only |
| `firewallpolicy-nonprod.yaml` | Non-Production | Relaxed egress, sandbox broader access |

## Applying

```bash
# Production cluster
kubectl --context prod apply -f prod-namespaces.yaml
kubectl --context prod apply -f firewallpolicy-prod.yaml

# Non-production cluster
kubectl --context nonprod apply -f nonprod-namespaces.yaml
kubectl --context nonprod apply -f firewallpolicy-nonprod.yaml
```

## Priority Ranges

| Range | Owner | Purpose |
|-------|-------|---------|
| 0-1 | Platform | Geo-block + ThreatIQ |
| 10-11 | Platform | Environment isolation (Layer 1) |
| 20-21 | Platform | Prod data protection |
| 30-32 | Platform | Namespace isolation (Layer 2) |
| 50-51 | Platform | Egress controls |
| 70-99 | Teams (CRD) | Self-service rules |

## Optional Hardening

The nodes layer for both prod and nonprod includes opt-in recommendation toggles:

```hcl
# nodes/prod/terraform.tfvars (production — full hardening recommended)
enable_network_policy           = true
enable_gatekeeper               = true
enable_external_secrets         = true
enable_falco                    = true
enable_prometheus_stack         = true
enable_fluent_bit               = true
enable_node_termination_handler = true
enable_cluster_autoscaler       = true
enable_velero                   = true

# nodes/nonprod/terraform.tfvars (non-prod — lighter profile)
enable_network_policy   = true
enable_prometheus_stack = true
```

The cluster layer also supports:

```hcl
# clusters/prod/terraform.tfvars
enable_private_endpoint      = true   # Private-only API (recommended for prod)
enable_control_plane_logging = true   # Audit logs to CloudWatch
```

See `ARCHITECTURE-ANALYSIS.md` for full toggle reference and rationale.
