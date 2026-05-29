# Kubernetes Cluster-as-a-Service — AWS

Each team gets a **dedicated EKS cluster in its own VPC**. Workload isolation is enforced by the **Aviatrix Cloud Native Security Fabric (CNSF)** — Distributed Cloud Firewall (DCF) at the VPC boundary — so no team can reach another team's cluster without an explicit PERMIT rule. This blueprint demonstrates VPC-level SmartGroup segmentation, post-SNAT DCF enforcement, GeoBlock/ThreatIQ threat prevention, and egress control via WebGroups.

---

## Architecture Diagram

![Architecture Diagram](../architecture.svg)

**Data flow:** Pods use a shared RFC 6598 overlay CIDR (`100.64.0.0/16`). Each spoke gateway applies custom SNAT, translating pod IPs to the spoke gateway's private IP before traffic enters the Aviatrix transit. DCF evaluates **post-SNAT traffic** — use VPC-type SmartGroups to identify source teams, and hostname-type SmartGroups to identify service destinations. Inter-team traffic that is not explicitly PERMITted is either subject to explicit DENY rules (for fully isolated teams) or falls through to the default internet egress deny.

```
Internet
    │ (blocked by default-deny unless WebGroup permits)
    ▼
Transit GW (10.2.0.0/20)  ◄── DCF evaluates here (post-SNAT)
├── Team-A Spoke (10.10.0.0/20) ── EKS cluster-a  [pods: 100.64.0.0/18]
├── Team-B Spoke (10.11.0.0/20) ── EKS cluster-b  [pods: 100.64.64.0/18]
├── Team-C Spoke (10.12.0.0/20) ── EKS cluster-c  [pods: 100.64.128.0/18]
└── DB Spoke    (10.5.0.0/22)   ── Shared database
```

---

## Prerequisites

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **Aviatrix Controller** | Version compatible with provider ~> 8.2 | Must be deployed and reachable |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **AWS Account Onboarded** | Account registered in Controller | Use the exact account name in `terraform.tfvars` |

### Local Tools

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.5 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| **AWS CLI** | v2 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS authentication and EKS kubeconfig |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster interaction |

### AWS IAM Permissions

The AWS credentials used must have permissions to create and manage:
- **EKS**: Clusters, managed node groups, add-ons, OIDC providers
- **VPC**: VPCs, subnets, route tables, internet gateways, security groups
- **IAM**: Roles and policies (for IRSA, node groups, add-ons)
- **Route53**: Private hosted zones, record sets
- **EC2**: Instances, EIPs, NAT Gateways, ENIs

> **EIP Quota:** This blueprint creates ~12 NAT Gateways plus up to 6 Aviatrix gateway EIPs. AWS default EIP limit is 5 — request an increase to at least 25 before deploying.

### Environment Variables

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<controller-ip-or-hostname>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"

# AWS credentials (choose one method)
export AWS_PROFILE="your-profile"
# or
export AWS_ACCESS_KEY_ID="<access-key>"
export AWS_SECRET_ACCESS_KEY="<secret-key>"
export AWS_REGION="us-west-2"
```

---

## Resources Created

| Resource | Count | Est. Hourly Cost |
|----------|-------|-----------------|
| `aviatrix_transit_gateway` (c5.xlarge) | 1 | $0.17 |
| `aviatrix_spoke_gateway` (t3.medium, no HA) | 3 | $0.04 each |
| `aviatrix_vpc` (transit + 3 team + DB) | 5 | — |
| `aviatrix_spoke_transit_attachment` | 4 | — |
| `aviatrix_gateway_snat` | 3 | — |
| `aviatrix_distributed_firewalling_config` | 0 or 1 | — |
| `aviatrix_k8s_config` | 0 or 1 | — |
| `aviatrix_kubernetes_cluster` | 3 | — |
| `aviatrix_smart_group` | 8 | — |
| `aviatrix_web_group` | 3 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `aws_vpc` (via module) | 4 | — |
| `aws_nat_gateway` | ~12 (~3 per VPC) | $0.045 each |
| `aws_eks_cluster` | 3 | $0.10 each |
| `aws_eks_node_group` (t3.large SPOT) | 3 × 2 nodes | ~$0.025/node |
| `aws_eks_addon` (vpc-cni, coredns, kube-proxy) | 9 | — |
| `aws_iam_openid_connect_provider` | 3 | — |
| `aws_iam_role` (IRSA — ALB + ExternalDNS) | 6+ | — |
| `aws_route53_zone` (private) | 1 | $0.50/month |
| `helm_release` (ALB Controller + ExternalDNS) | 6 | — |
| `kubernetes_config_map` (ENIConfig per AZ) | 3+ | — |

**Estimated total:** ~$0.80/hour at desired state with SPOT nodes (~$580/month).

> Aviatrix licensing costs are separate and depend on your subscription type (PAYG via AWS Marketplace or BYOL).

---

## Deployment Instructions

### Step 1 — Set environment variables

```bash
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"
export AWS_PROFILE="<your-aws-profile>"

# Verify AWS credentials
aws sts get-caller-identity
```

### Step 2 — Deploy Layer 1: Network (~8 min)

```bash
cd aws/network
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aviatrix_aws_account_name and aws_region
vim terraform.tfvars

terraform init
terraform apply
```

**What is created:** Aviatrix transit gateway, 4 VPCs (transit + 3 team + DB), 3 spoke gateways, spoke-to-transit attachments, custom SNAT rules (pod CIDR → spoke GW IP), Route53 private hosted zone, and the DCF ruleset with inter-team + egress policies.

### Step 3 — Deploy Layer 2: EKS Clusters (parallel, ~15 min)

```bash
for team in team-a team-b team-c; do
  cd aws/clusters/$team
  cp terraform.tfvars.example terraform.tfvars
  # Edit terraform.tfvars: set aviatrix_aws_account_name
  terraform init
  terraform apply -auto-approve &
  cd ../../..
done
wait
```

**What is created:** EKS control plane, cluster security groups, OIDC provider for IRSA, IAM roles for ALB Controller and ExternalDNS, VPC CNI addon with custom networking enabled.

> **Note:** No node groups are created in this layer — that comes in Layer 3.

### Step 4 — Deploy Layer 3: Node Groups (parallel, ~8 min)

```bash
for team in team-a team-b team-c; do
  cd aws/nodes/$team
  terraform init
  terraform apply -auto-approve &
  cd ../../..
done
wait
```

**What is created:** ENIConfig resources (one per AZ), EKS managed node groups, CoreDNS addon, AWS Load Balancer Controller (Helm), ExternalDNS (Helm).

**Deployment order within nodes:** ENIConfig → Node Groups → CoreDNS → Helm charts.

### Step 5 — Configure kubectl

```bash
# Configure kubectl for each cluster
for team in team-a team-b team-c; do
  cluster_name=$(terraform -chdir=aws/network output -raw ${team//-/_}_cluster_name)
  aws eks update-kubeconfig --name $cluster_name --alias $team --region us-west-2
done

# Verify all three clusters are accessible
kubectl config get-contexts
kubectl get nodes --context=team-a
kubectl get nodes --context=team-b
kubectl get nodes --context=team-c
```

---

## Variables Reference

### Network (`aws/network/`)

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `aviatrix_aws_account_name` | string | — | yes | AWS account name as registered in Aviatrix Controller |
| `aws_region` | string | `us-west-2` | no | AWS region for all resources |
| `name_prefix` | string | `caas` | no | Prefix for all resource names |
| `transit_cidr` | string | `10.2.0.0/20` | no | CIDR for the Aviatrix transit VPC |
| `team_a_vpc_cidr` | string | `10.10.0.0/20` | no | Primary CIDR for team-a EKS VPC |
| `team_b_vpc_cidr` | string | `10.11.0.0/20` | no | Primary CIDR for team-b EKS VPC |
| `team_c_vpc_cidr` | string | `10.12.0.0/20` | no | Primary CIDR for team-c EKS VPC |
| `db_vpc_cidr` | string | `10.5.0.0/22` | no | CIDR for the database spoke VPC |
| `pod_cidr` | string | `100.64.0.0/16` | no | Overlay CIDR for pod networking (RFC 6598) |
| `private_dns_zone_name` | string | `aws.aviatrixdemo.local` | no | Route53 private hosted zone domain name |
| `db_private_ip` | string | `10.5.0.10` | no | Private IP address of the database (DNS A record) |
| `random_suffix` | bool | `true` | no | Append random hex suffix to all resource names |
| `manage_dcf` | bool | `false` | no | Whether this blueprint manages DCF global enable/disable |
| `controller_ip` | string | `null` | no | Aviatrix Controller IP (overrides env var) |
| `controller_username` | string | `admin` | no | Aviatrix Controller username |
| `controller_password` | string | `null` | no | Aviatrix Controller password (sensitive) |

### Cluster (`aws/clusters/team-*/`)

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `aviatrix_aws_account_name` | string | — | yes | Aviatrix access account name for AWS |
| `kubernetes_version` | string | `1.35` | no | Kubernetes version for the EKS cluster |
| `enable_private_endpoint` | bool | `false` | no | Disable public EKS API server endpoint (requires VPN/bastion) |
| `enable_control_plane_logging` | bool | `false` | no | Enable EKS control plane logging to CloudWatch |
| `controller_ip` | string | `null` | no | Aviatrix Controller IP (overrides env var) |
| `controller_username` | string | `admin` | no | Aviatrix Controller username |
| `controller_password` | string | `null` | no | Aviatrix Controller password (sensitive) |

### Nodes (`aws/nodes/team-*/`)

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `node_group_config` | object | see below | no | EKS managed node group configuration |
| `node_group_config.min_size` | number | `1` | no | Minimum node count for autoscaling |
| `node_group_config.max_size` | number | `3` | no | Maximum node count for autoscaling |
| `node_group_config.desired_size` | number | `2` | no | Desired (initial) node count |
| `node_group_config.instance_type` | string | `t3.large` | no | EC2 instance type for worker nodes |
| `node_group_config.capacity_type` | string | `SPOT` | no | `SPOT` or `ON_DEMAND` |
| `alb_controller_chart_version` | string | `1.8.0` | no | Helm chart version for AWS ALB Controller |
| `external_dns_chart_version` | string | `1.15.0` | no | Helm chart version for ExternalDNS |
| `controller_ip` | string | `null` | no | Aviatrix Controller IP (overrides env var) |
| `controller_username` | string | `admin` | no | Aviatrix Controller username |
| `controller_password` | string | `null` | no | Aviatrix Controller password (sensitive) |

---

## Outputs Reference

### Network (`aws/network/`)

| Output | Description |
|--------|-------------|
| `transit_gateway_name` | Aviatrix transit gateway name (sensitive) |
| `transit_vpc_id` | Transit VPC ID |
| `team_a_vpc_id` | Team-A VPC ID |
| `team_a_private_subnet_ids` | Team-A private subnet IDs for EKS node groups |
| `team_a_pod_subnet_ids` | Team-A pod subnet IDs for VPC CNI custom networking |
| `team_a_spoke_gateway_name` | Team-A spoke gateway name (sensitive) |
| `team_a_spoke_gateway_private_ip` | Team-A spoke gateway private IP for SNAT (sensitive) |
| `team_b_vpc_id` | Team-B VPC ID |
| `team_b_private_subnet_ids` | Team-B private subnet IDs for EKS node groups |
| `team_b_pod_subnet_ids` | Team-B pod subnet IDs for VPC CNI custom networking |
| `team_b_spoke_gateway_name` | Team-B spoke gateway name (sensitive) |
| `team_b_spoke_gateway_private_ip` | Team-B spoke gateway private IP for SNAT (sensitive) |
| `team_c_vpc_id` | Team-C VPC ID |
| `team_c_private_subnet_ids` | Team-C private subnet IDs for EKS node groups |
| `team_c_pod_subnet_ids` | Team-C pod subnet IDs for VPC CNI custom networking |
| `team_c_spoke_gateway_name` | Team-C spoke gateway name (sensitive) |
| `route53_zone_id` | Route53 private hosted zone ID |
| `private_dns_zone_name` | Route53 private hosted zone domain name |
| `team_a_cluster_name` | Team-A EKS cluster name |
| `team_b_cluster_name` | Team-B EKS cluster name |
| `team_c_cluster_name` | Team-C EKS cluster name |
| `aws_region` | AWS region |
| `pod_cidr` | Overlay CIDR for pod networking |
| `dcf_ruleset_uuid` | UUID of the DCF ruleset |

### Cluster (`aws/clusters/team-*/`)

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_arn` | EKS cluster ARN |
| `cluster_endpoint` | EKS cluster API server endpoint |
| `cluster_certificate_authority_data` | Base64 encoded CA certificate (sensitive) |
| `oidc_provider_arn` | OIDC provider ARN for IRSA |
| `alb_controller_role_arn` | IAM role ARN for AWS Load Balancer Controller |
| `external_dns_role_arn` | IAM role ARN for ExternalDNS |

### Nodes (`aws/nodes/team-*/`)

Nodes workspaces expose no outputs — node groups are consumed by Kubernetes directly.

---

## Test Scenarios

### Scenario 1 — Permitted east-west traffic (team-a → team-b on TCP/443)

```bash
# Deploy a test server in team-b
kubectl run --context=team-b server --image=nginx --port=443 --expose

# Test connectivity from team-a (should succeed — DCF PERMIT rule 110)
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k https://team-b.aws.aviatrixdemo.local
# Expected: HTTP response (200 OK or similar)
```

### Scenario 2 — Blocked east-west traffic (team-a → team-c, any port)

```bash
# Test connectivity from team-a to team-c (should be blocked — DCF DENY rule 120)
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k --connect-timeout 5 https://team-c.aws.aviatrixdemo.local
# Expected: connection timeout or refused
```

### Scenario 3 — Permitted egress to EKS required services (ECR, S3, STS)

```bash
# Test egress to ECR registry (should succeed — DCF PERMIT rule 150 + WebGroup)
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k --connect-timeout 5 https://registry.k8s.io
# Expected: HTTP response (not blocked)
```

### Scenario 4 — Default internet deny

```bash
# Test egress to an arbitrary internet site (should be blocked — default deny 200)
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl --connect-timeout 5 https://example.com
# Expected: connection timeout
```

### Scenario 5 — GeoBlock enforcement

Verify in CoPilot → Security → Distributed Cloud Firewall → Traffic Logs that traffic to geo-blocked countries (IR, KP, RU) is logged as DENY with rule `caas-block-geo`.

---

## Cleanup / Destroy

**Destroy in reverse layer order.** Destroying the network layer while clusters still exist will leave orphaned Aviatrix resources.

### Step 1 — Clean up Kubernetes resources (prevent orphaned DNS records)

```bash
for team in team-a team-b team-c; do
  kubectl delete ingress --all -A --context=$team
  kubectl delete svc -A --field-selector spec.type=LoadBalancer --context=$team
done
# Wait ~60 seconds for ExternalDNS to clean up Route53 records before proceeding
```

### Step 2 — Destroy Layer 3: Nodes (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=aws/nodes/$team destroy -auto-approve &
done
wait
```

### Step 3 — Destroy Layer 2: Clusters (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=aws/clusters/$team destroy -auto-approve &
done
wait
```

### Step 4 — Destroy Layer 1: Network

```bash
terraform -chdir=aws/network destroy -auto-approve
```

### Step 5 — Verify cleanup

```bash
# Confirm no Aviatrix gateways remain
# In Controller: check Gateways list is empty for this deployment

# Confirm no EKS clusters remain
aws eks list-clusters --region us-west-2

# Confirm Route53 zone is deleted
aws route53 list-hosted-zones-by-name --dns-name aws.aviatrixdemo.local
```

> **Warning:** If ExternalDNS-managed Route53 records (CNAME/TXT) were not cleaned up in Step 1, they will be orphaned after the hosted zone is deleted. Manually remove them from Route53 before Step 4 if needed.

---

## Troubleshooting

**EIP quota exceeded during apply**

This blueprint creates ~12 NAT Gateways plus up to 6 Aviatrix gateway EIPs per region. The AWS default EIP limit is 5 per region. Request an increase to at least 25 before deploying: AWS Console → Service Quotas → EC2 → Elastic IP addresses.

**`aviatrix_kubernetes_cluster` fails: cluster not found**

The nodes layer must be applied after the EKS cluster is in `ACTIVE` state and the Aviatrix Controller has completed its Kubernetes inventory sync (typically 2–5 min after node groups join). If this fails, wait and re-run `terraform apply` in the nodes layer for the affected team.

**Pods cannot reach external services**

Verify SNAT rules are applied: Aviatrix Controller → Gateways → [spoke gateway] → SNAT. The pod CIDR `100.64.0.0/16` must map to the spoke gateway's private IP. If SNAT rules are missing, re-apply the network layer. Also verify `AWS_VPC_K8S_CNI_EXTERNALSNAT=true` is set on the `aws-node` DaemonSet.

**DCF rules not enforcing**

Check that `aviatrix_distributed_firewalling_config` was applied (either `manage_dcf=true` in this blueprint, or DCF was enabled externally). Verify in CoPilot → Security → Distributed Cloud Firewall that DCF is in `Enabled` state. If DCF is enabled but rules are not matching, confirm the VPC-type SmartGroups are selecting the correct VPCs by name.

**ENIConfig not found for AZ**

If new pods are stuck `Pending` with `no ENIConfig found for AZ`, verify the `kubernetes_config_map` resources (ENIConfig) were applied in the nodes layer before the node groups. Check with: `kubectl get eniconfig -A`. If missing, destroy and re-apply the nodes layer.

**Terraform state conflict between layers**

Each layer uses independent local state. If a layer was partially applied, run `terraform state list` to see what was created, then run `terraform apply` again — Terraform will only create missing resources. Never destroy the network layer before destroying clusters and nodes.

---

## Tested With

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 7.2+ |
| Aviatrix Terraform Provider | ~> 8.2.0 |
| Terraform | >= 1.5 |
| AWS Provider | ~> 5.0 |
| Kubernetes Provider | ~> 2.20 |
| Helm Provider | ~> 2.x |
| Kubernetes | 1.35 (EKS) |
