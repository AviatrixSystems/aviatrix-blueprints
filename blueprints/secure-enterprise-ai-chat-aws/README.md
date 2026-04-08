# Secure Enterprise AI Chat (AWS)

Deploys a secure AI chat platform using LibreChat and LiteLLM on AWS EKS, with Aviatrix Distributed Cloud Firewall (DCF) controlling egress to approved AI backends.

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │                 AWS VPC (10.1.0.0/16)          │
                    │                                                 │
  Internet ───────► │  ┌──────────┐     ┌──────────────────────┐     │
       (HTTP/80)    │  │   ALB    │────►│   EKS Cluster        │     │
                    │  │ (public) │     │                      │     │
                    │  └──────────┘     │  ┌─────────────┐     │     │
                    │                   │  │  LibreChat   │     │     │
                    │                   │  │  (frontend)  │     │     │
                    │                   │  └──────┬───────┘     │     │
                    │                   │         │             │     │
                    │                   │  ┌──────▼───────┐     │     │
                    │                   │  │   LiteLLM    │     │     │
                    │                   │  │ (AI gateway)  │     │     │
                    │                   │  └──────┬───────┘     │     │
                    │                   │         │ IRSA        │     │
                    │                   └─────────┼─────────────┘     │
                    │                             │                   │
                    │  ┌──────────────────────────▼──────────────┐   │
                    │  │     Aviatrix Spoke Gateway (HA pair)     │   │
                    │  │     DCF: Egress filtering via WebGroups  │   │
                    │  └──────────────────────┬──────────────────┘   │
                    └─────────────────────────┼──────────────────────┘
                                              │
                    ┌─────────────────────────▼──────────────────────┐
                    │        Aviatrix Transit Gateway                 │
                    └─────────────────────────┬──────────────────────┘
                                              │
                              ┌───────────────▼───────────────┐
                              │     AWS Bedrock (Claude)       │
                              │  bedrock-runtime.*.amazonaws   │
                              └───────────────────────────────┘
```

## Traffic Flow

1. User accesses LibreChat via public ALB
2. LibreChat sends AI requests to LiteLLM (in-cluster)
3. LiteLLM authenticates to Bedrock using IRSA (IAM role for service account)
4. Egress traffic flows through Aviatrix spoke gateway
5. DCF evaluates egress against WebGroups - only approved destinations (Bedrock, ECR, etc.) are permitted

## DCF Egress Policy

| Priority | Rule | Action | WebGroup |
|----------|------|--------|----------|
| 0 | Block GeoBlocked Countries | DENY | - |
| 1 | Block Threat Intel IPs | DENY | - |
| 10 | EKS Required AWS Services | PERMIT | ECR, STS, EKS API, etc. |
| 11 | Container Registries | PERMIT | GHCR, Docker Hub |
| 20 | AWS Bedrock | PERMIT (watch) | bedrock-runtime.*.amazonaws.com |
| 50-99 | K8s CRD Policies | (placeholder) | Managed via Aviatrix K8s CRD |

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- Aviatrix Controller with AWS account onboarded
- `kubectl` installed
- AWS Bedrock model access enabled (Claude models)

## Deployment

### Layer 1: Infrastructure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

### Layer 2: Applications

```bash
cd ../apps

# Configure kubectl
aws eks update-kubeconfig --name $(cd ../infra && terraform output -raw cluster_name) --region $(cd ../infra && terraform output -raw aws_region)

terraform init
terraform plan
terraform apply
```

### Access LibreChat

```bash
cd apps
echo "LibreChat URL: http://$(terraform output -raw librechat_ingress_hostname)"
```

## Destroy

Destroy in reverse order:

```bash
cd apps && terraform destroy
cd ../infra && terraform destroy
```

## Resources Created

| Resource | Type | Estimated Cost |
|----------|------|---------------|
| Aviatrix Transit Gateway | t3.medium | ~$0.05/hr |
| Aviatrix Spoke Gateway (HA pair) | t3.medium x2 | ~$0.10/hr |
| EKS Cluster | Managed | $0.10/hr |
| EKS Node Group | t3.large x2 | ~$0.17/hr |
| Application Load Balancer | ALB | ~$0.02/hr |
| VPC + Subnets | Networking | minimal |
| **Total** | | **~$0.44/hr (~$317/mo)** |

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `name_prefix` | Prefix for all resource names | `ai-chat` |
| `aviatrix_aws_account_name` | AWS account name in Aviatrix Controller | (required) |
| `aws_region` | AWS region | `us-east-2` |
| `vpc_cidr` | VPC CIDR block | `10.1.0.0/16` |
| `transit_cidr` | Transit VPC CIDR | `10.0.0.0/20` |
| `kubernetes_version` | EKS version | `1.31` |
| `node_group_config` | Node group sizing | 2x t3.large ON_DEMAND |
| `aviatrix_controller_role_arn` | Controller IAM role for K8s onboarding | `""` |

## Extending with K8s CRDs

The Aviatrix K8s Firewall CRD is installed in the cluster. You can add namespace-level egress policies:

```yaml
apiVersion: networking.aviatrix.com/v1alpha1
kind: FirewallPolicy
metadata:
  name: allow-openai
  namespace: default
spec:
  priority: 50
  action: PERMIT
  protocol: TCP
  logging: true
  dst_smart_groups:
    - "def000ad-0000-0000-0000-000000000001"  # Public Internet
  web_groups:
    - name: "wg-openai"
      snifilters:
        - "api.openai.com"
  port_ranges:
    - lo: 443
```

## Tested With

| Component | Version |
|-----------|---------|
| Terraform | >= 1.5 |
| Aviatrix Provider | ~> 8.2 |
| AWS Provider | ~> 6.0 |
| EKS Module | ~> 21.9 |
| Kubernetes | 1.31 |
