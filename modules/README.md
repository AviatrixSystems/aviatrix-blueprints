# Shared Modules

Reusable Terraform modules shared across blueprint patterns.

## Recommendations Module

**Path:** `recommendations/`

Optional production-hardening add-ons deployed as Helm charts with IRSA (IAM Roles for Service Accounts). All toggles default to `false` -- zero impact unless explicitly enabled.

### Security

| Toggle | What It Deploys | Namespace |
|--------|----------------|-----------|
| `enable_network_policy` | Calico CNI + NetworkPolicy support | `tigera-operator` |
| `enable_gatekeeper` | OPA Gatekeeper admission controller (image allowlists, resource limits, privilege escalation prevention) | `gatekeeper-system` |
| `enable_external_secrets` | External Secrets Operator (AWS Secrets Manager/SSM into K8s Secrets) | `external-secrets` |
| `enable_falco` | Falco runtime threat detection (eBPF-based syscall monitoring, container drift, file integrity) | `falco` |

### Observability

| Toggle | What It Deploys | Namespace |
|--------|----------------|-----------|
| `enable_prometheus_stack` | kube-prometheus-stack (Prometheus + Grafana + Alertmanager + K8s dashboards) | `monitoring` |
| `enable_fluent_bit` | Fluent Bit log aggregation to CloudWatch Logs | `logging` |

### Resilience

| Toggle | What It Deploys | Namespace |
|--------|----------------|-----------|
| `enable_node_termination_handler` | AWS Node Termination Handler (graceful drain on SPOT interruptions) | `kube-system` |
| `enable_cluster_autoscaler` | Cluster Autoscaler (dynamic node scaling based on pending pods) | `kube-system` |
| `enable_velero` | Velero backup/restore (cluster resources + persistent volumes to S3, daily schedule) | `velero` |

### IRSA

Each add-on gets a dedicated IAM role scoped to its service account with least-privilege permissions. Roles are defined in `irsa.tf` and trust the EKS OIDC provider.

### Suggested Profiles

| Profile | Toggles |
|---------|---------|
| **Demo/Lab** | All `false` -- fast deploy, no extras |
| **Minimum Prod** | `enable_control_plane_logging`, `enable_network_policy`, `enable_node_termination_handler`, `enable_cluster_autoscaler` |
| **Full Hardening** | All `true` |

### Usage

Set toggles in `terraform.tfvars` or via environment variables:

```hcl
# nodes/{target}/terraform.tfvars
enable_network_policy   = true
enable_prometheus_stack = true
enable_cluster_autoscaler = true
```

```bash
# Or via CI/CD
export TF_VAR_enable_network_policy=true
```

### Files

| File | Contents |
|------|----------|
| `security.tf` | Calico, Gatekeeper, External Secrets, Falco |
| `observability.tf` | Prometheus stack, Fluent Bit |
| `resilience.tf` | Node Termination Handler, Cluster Autoscaler, Velero |
| `irsa.tf` | IAM role definitions for all add-ons |
