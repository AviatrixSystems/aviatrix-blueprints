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
                    │  │     Aviatrix Spoke Gateway               │   │
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
5. DCF evaluates egress against WebGroups - only approved destinations are permitted
6. All other egress is denied by default (zero-trust)

## DCF Egress Policy

| Priority | Rule | Action | Source | WebGroup |
|----------|------|--------|--------|----------|
| 0 | Block GeoBlocked Countries | DENY | VPC | - |
| 1 | Block Threat Intel IPs | DENY | VPC | - |
| 10 | EKS Required AWS Services | PERMIT | VPC | ECR, STS, EKS, ELB APIs |
| 11 | Container Registries | PERMIT | VPC | GHCR, Docker Hub |
| 20 | AWS Bedrock (LiteLLM only) | PERMIT (watch) | K8s: litellm | bedrock-runtime.*.amazonaws.com |
| 50-99 | K8s CRD Policies | (placeholder) | Managed via Aviatrix K8s CRD |
| 100 | Default Deny All Egress | DENY | VPC | - |

### SmartGroup Types

- **VPC-type** (`sg-ai-chat-vpc`): Matches the AI VPC by cloud resource ID
- **K8s-type** (`sg-ai-chat-k8s-litellm`): Matches LiteLLM pods by cluster/namespace/service
- **K8s-type** (`sg-ai-chat-k8s-librechat`): Matches LibreChat pods by cluster/namespace/service

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- Aviatrix Controller with AWS account onboarded
- `kubectl` installed
- AWS Bedrock model access enabled (Claude Sonnet 4.6, Claude Haiku 4.5)

### Docker Credential Helper (Known Issue)

The MongoDB Helm chart uses an OCI registry (`oci://registry-1.docker.io/bitnamicharts`). If your machine has a stale Docker Desktop configuration in `~/.docker/config.json` with `"credsStore": "desktop"` but the `docker-credential-desktop` binary is not in your PATH, Terraform will fail to pull the chart.

**Workaround:**

```bash
# Create a temporary Docker config without credsStore
mkdir -p /tmp/docker-config
echo '{}' > /tmp/docker-config/config.json

# Prefix all terraform commands in the apps layer with:
DOCKER_CONFIG=/tmp/docker-config terraform apply
```

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
aws eks update-kubeconfig \
  --name $(cd ../infra && terraform output -raw cluster_name) \
  --region $(cd ../infra && terraform output -raw aws_region)

terraform init
terraform plan
terraform apply
```

### Access LibreChat

```bash
cd apps
echo "LibreChat URL: http://$(terraform output -raw librechat_ingress_hostname)"
```

Register a new account and start chatting. Models available: `claude-sonnet` (Sonnet 4.6) and `claude-haiku` (Haiku 4.5).

## Destroy

Destroy in **reverse order** (apps first, then infra):

```bash
# Layer 2: Applications
cd apps
terraform destroy

# Layer 1: Infrastructure
cd ../infra
terraform destroy
```

## Troubleshooting

### Default deny blocking traffic

The DCF ruleset includes a default deny rule at priority 100. If something stops working after deployment, check CoPilot FlowIQ for denied flows and add a PERMIT rule above priority 100.

### LiteLLM Bedrock errors

- **"Invocation of model ID ... with on-demand throughput isn't supported"**: The model IDs must use cross-region inference profiles (e.g., `us.anthropic.claude-sonnet-4-6`), not direct foundation model IDs.
- **"not authorized to perform bedrock:InvokeModelWithResponseStream"**: The IRSA IAM policy must include both `arn:aws:bedrock:*::foundation-model/*` and `arn:aws:bedrock:*:*:inference-profile/*` in the Resource array.

### LibreChat login errors

- **"JwtStrategy requires a secret or key"**: LibreChat needs `JWT_SECRET`, `JWT_REFRESH_SECRET`, `CREDS_KEY`, and `CREDS_IV` environment variables. These are auto-generated by `random_password` resources.

### MongoDB pod pending

If the MongoDB pod is stuck in `Pending`, check for PVC issues. This blueprint runs MongoDB with `persistence.enabled=false` (ephemeral storage) to avoid requiring the EBS CSI driver. Data is lost on pod restart.

### Spoke gateway HA

HA is currently disabled (`ha_gw = false`) due to a known controller issue. To re-enable, set `ha_gw = true` in `infra/aviatrix.tf`.

## Resources Created

| Resource | Type | Estimated Cost |
|----------|------|---------------|
| Aviatrix Transit Gateway | t3.medium | ~$0.05/hr |
| Aviatrix Spoke Gateway | t3.medium | ~$0.05/hr |
| EKS Cluster | Managed | $0.10/hr |
| EKS Node Group | t3.large x2 | ~$0.17/hr |
| Application Load Balancer | ALB | ~$0.02/hr |
| VPC + Subnets | Networking | minimal |
| **Total** | | **~$0.39/hr (~$281/mo)** |

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
| LibreChat | v0.8.4 |
| LiteLLM | v1.82.3-stable.patch.2 |
| ALB Controller Chart | 3.1.0 |
| MongoDB Chart | 18.6.22 |
