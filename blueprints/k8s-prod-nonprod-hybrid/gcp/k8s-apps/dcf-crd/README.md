# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — GCP CRDs

## Overview

This directory contains Kubernetes manifests for the two-layer DCF (Distributed Cloud Firewall) pattern on GCP GKE.

## Architecture

```
Production Cluster (GKE)          Non-Production Cluster (GKE)
├── team-a-prod                   ├── team-a-dev
├── team-b-prod                   ├── team-b-staging
└── monitoring                    ├── sandbox (relaxed egress)
                                  └── monitoring
```

## Two-Layer DCF

- **Layer 1 (VPC SmartGroups):** Environment isolation — prod VPC and nonprod VPC cannot communicate in either direction. DB spoke only reachable from prod VPC.
- **Layer 2 (K8s Namespace SmartGroups):** Team isolation within each cluster — teams are isolated by default with explicit allow rules via CRDs.

## GCP-Specific Notes

- Different `master_ipv4_cidr_block` per cluster: prod=172.16.0.0/28, nonprod=172.16.0.16/28
- `deletion_protection = false` for Terraform management
- Cloud DNS `network_url` uses GCP self-link for Aviatrix transit VPC
- Gateway API for ingress (GKE native)
- ExternalDNS with Cloud DNS + Workload Identity Federation

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

The AWS implementation includes opt-in recommendation toggles (Calico, Gatekeeper, Falco, Prometheus, Velero, etc.) in the nodes and clusters layers. GCP variants can follow the same pattern using the shared module at `modules/recommendations/`. See `ARCHITECTURE-ANALYSIS.md` for the full toggle reference.
