# Aviatrix DCF Kubernetes CRD Policies

This directory contains example Kubernetes CRD-based policies for Aviatrix Distributed Cloud Firewall (DCF).

## Overview

While base DCF policies are managed via Terraform (see `network-aviatrix/dcf.tf`), K8s CRD-based policies allow:

- **Namespace-level control**: Apply policies scoped to specific namespaces
- **Pod-label targeting**: Target pods by labels without needing Aviatrix-registered K8s clusters
- **Self-service**: Allow dev teams to manage their own egress rules
- **Temporary policies**: Quick changes without Terraform apply cycles

## Prerequisites

Install the Aviatrix K8s Firewall CRDs:

```bash
helm install --repo https://aviatrixsystems.github.io/k8s-firewall-charts k8s-firewall k8s-firewall
```

Verify CRD installation:

```bash
kubectl get crds | grep aviatrix
```

Expected output:
```
firewallpolicies.networking.aviatrix.com        2025-01-27T00:00:00Z
webgrouppolicies.networking.aviatrix.com        2025-01-27T00:00:00Z
```

## Available CRDs

### FirewallPolicy

Full-featured firewall policy with SmartGroups and WebGroups defined inline.

```yaml
apiVersion: networking.aviatrix.com/v1alpha1
kind: FirewallPolicy
metadata:
  name: my-policy
  namespace: my-namespace
spec:
  rules:
    - name: rule-name
      selector:
        matchLabels:
          app: my-app
      action: permit
      protocol: tcp
      ports:
        - "443"
      destinationSmartGroups:
        - name: my-smartgroup
      webGroups:
        - name: my-webgroup

  webGroups:
    - name: my-webgroup
      domains:
        - "example.com"

  smartGroups:
    - name: my-smartgroup
      selectors:
        - cidr: 0.0.0.0/0
```

### WebGroupPolicy

Simplified policy for web/HTTPS egress filtering.

```yaml
apiVersion: networking.aviatrix.com/v1alpha1
kind: WebGroupPolicy
metadata:
  name: my-web-policy
  namespace: my-namespace
spec:
  selector:
    matchLabels:
      app: my-app
  action: permit
  protocol: tcp
  ports:
    - "443"
  domains:
    - "api.example.com"
```

## Examples in This Directory

| File | Purpose |
|------|---------|
| `firewallpolicy-infosec.yaml` | Allow infosec pods to access VirusTotal |
| `webgrouppolicy-dev.yaml` | Allow dev namespace to access package registries |

## Applying Policies

```bash
# Apply to frontend cluster
kubectl config use-context frontend-cluster
kubectl apply -f firewallpolicy-infosec.yaml

# Apply to backend cluster
kubectl config use-context backend-cluster
kubectl apply -f webgrouppolicy-dev.yaml
```

## Verifying Policies

```bash
# Check policy status
kubectl get firewallpolicies -A
kubectl get webgrouppolicies -A

# Check events for policy sync status
kubectl get events -n <namespace> --field-selector reason=CreatePolicySuccess
```

## Policy Priority

CRD-based policies are inserted at priority 50-99 in the DCF ruleset hierarchy:

| Priority | Policy Type |
|----------|-------------|
| 0-9 | Threat Prevention (Terraform) |
| 10-29 | Inter-VPC East-West (Terraform) |
| 20-29 | EKS Required Services (Terraform) |
| 30-49 | Explicit Egress Allow (Terraform) |
| **50-99** | **K8s CRD Policies** |
| 1000 | Default Deny (Terraform) |

## Cleanup

```bash
kubectl delete -f firewallpolicy-infosec.yaml
kubectl delete -f webgrouppolicy-dev.yaml
```
