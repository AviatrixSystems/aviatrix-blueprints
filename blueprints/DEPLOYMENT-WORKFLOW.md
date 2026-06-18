# Aviatrix Kubernetes Multi-Cloud — Deployment Workflow

## Overview

Three deployment patterns, each following a 4-layer sequential workflow.
Layers must be deployed in order (each depends on the previous).
Destruction is reverse order.

```
Layer 1: Network    → Transit GW, Spoke GWs, VPCs, SNAT, DNS, DCF
Layer 2: Clusters   → EKS/AKS/GKE control planes
Layer 3: Nodes      → Node groups, Helm charts (CRDs, ingress, ExternalDNS)
Layer 4: Apps/CRDs  → Namespaces, FirewallPolicy, WebGroupPolicy manifests
```

---

## Prerequisites

### Environment Variables (required for all layers)

```bash
# Aviatrix Controller
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"

# AWS (via SSO or access keys)
aws sso login  # or export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN

# Pattern-specific account name variable
# Pattern A & B:
export TF_VAR_aviatrix_aws_account_name="lab-test-aws"
# Pattern C:
export TF_VAR_aws_account_name="lab-test-aws"
```

### Tool Versions

| Tool | Minimum Version |
|------|----------------|
| Terraform | >= 1.5 |
| AWS CLI | >= 2.61 |
| kubectl | >= 1.28 |
| Helm | >= 3.0 |
| Aviatrix Provider | ~> 8.2 |

### AWS Service Quotas (per region)

| Quota | Pattern A | Pattern B | Pattern C |
|-------|-----------|-----------|-----------|
| VPCs | 6 | 3 | 5 |
| Elastic IPs | 12 | 4 | 10 |
| EKS Clusters | 3 | 1 | 2 |

Request increases before deploying:
```bash
aws service-quotas request-service-quota-increase --service-code vpc --quota-code L-F678F1CE --desired-value 20 --region <region>
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-0263D0A3 --desired-value 20 --region <region>
```

---

## Pattern A: Cluster-as-a-Service

**Region:** us-west-2 (or any region with sufficient quotas)
**Architecture:** 3 dedicated clusters (team-a, team-b, team-c), VPC-level DCF isolation

### Deploy

```bash
cd blueprints/cluster-aas/aws

# Layer 1: Network (~5-8 min)
cd network
terraform init
terraform apply -auto-approve
cd ..

# Layer 2: Clusters (~10-15 min each, run in parallel)
for team in team-a team-b team-c; do
  cd clusters/$team
  terraform init
  terraform apply -auto-approve &
  cd ../..
done
wait

# Add your IAM role to each cluster for kubectl access
for cluster in caas-team-a caas-team-b caas-team-c; do
  ROLE_ARN=$(aws iam list-roles --query 'Roles[?contains(RoleName,`SubAccountAdmin`)].Arn' --output text)
  aws eks create-access-entry --cluster-name $cluster --region us-west-2 --principal-arn "$ROLE_ARN"
  aws eks associate-access-policy --cluster-name $cluster --region us-west-2 \
    --principal-arn "$ROLE_ARN" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster
done

# Layer 3: Nodes (~5-8 min each, run in parallel)
for team in team-a team-b team-c; do
  cd nodes/$team
  terraform init
  terraform apply -auto-approve &
  cd ../..
done
wait

# Layer 4: CRDs (apply via kubectl)
for cluster in caas-team-a caas-team-b caas-team-c; do
  aws eks update-kubeconfig --name $cluster --region us-west-2
done
# No namespace CRDs needed for Pattern A — teams own their clusters
```

### Verify

```bash
# Check all clusters
for cluster in caas-team-a caas-team-b caas-team-c; do
  echo "=== $cluster ==="
  aws eks update-kubeconfig --name $cluster --region us-west-2
  kubectl get nodes
done

# Check DCF in CoPilot: Security > Distributed Cloud Firewall
# Verify SmartGroups show VPC members
```

### Destroy (reverse order)

```bash
cd blueprints/cluster-aas/aws

for team in team-a team-b team-c; do
  cd nodes/$team && terraform destroy -auto-approve && cd ../..
done

for team in team-a team-b team-c; do
  cd clusters/$team && terraform destroy -auto-approve && cd ../..
done

cd network && terraform destroy -auto-approve && cd ..
```

---

## Pattern B: Namespace-as-a-Service

**Region:** us-east-1
**Architecture:** 1 shared cluster, namespace-level DCF isolation + CRD self-service

### Deploy

```bash
cd blueprints/namespace-aas/aws

# Layer 1: Network (~5-8 min)
cd network
terraform init
terraform apply -auto-approve
cd ..

# Layer 2: Cluster (~10-15 min)
cd clusters/shared
terraform init
terraform apply -auto-approve
cd ../..

# Add IAM role for kubectl access
ROLE_ARN=$(aws iam list-roles --query 'Roles[?contains(RoleName,`SubAccountAdmin`)].Arn' --output text)
aws eks create-access-entry --cluster-name naas-shared-eks --region us-east-1 --principal-arn "$ROLE_ARN"
aws eks associate-access-policy --cluster-name naas-shared-eks --region us-east-1 \
  --principal-arn "$ROLE_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

# Layer 3: Nodes (~5-8 min)
cd nodes/shared
terraform init
terraform apply -auto-approve
cd ../..

# Layer 4: Namespaces + CRDs
aws eks update-kubeconfig --name naas-shared-eks --region us-east-1
kubectl apply -f k8s-apps/dcf-crd/namespace-setup.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-team-a.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-team-b.yaml
kubectl apply -f k8s-apps/dcf-crd/webgrouppolicy-team-b.yaml
```

### Verify

```bash
aws eks update-kubeconfig --name naas-shared-eks --region us-east-1
kubectl get nodes
kubectl get ns
kubectl get firewallpolicies -A  # Aviatrix CRDs
kubectl get webgrouppolicies -A

# Check CoPilot:
#   Security > Distributed Cloud Firewall — verify namespace SmartGroups have members
#   Cloud Assets > Kubernetes — verify cluster discovered
```

### Destroy (reverse order)

```bash
cd blueprints/namespace-aas/aws

kubectl delete -f k8s-apps/dcf-crd/ --ignore-not-found
cd nodes/shared && terraform destroy -auto-approve && cd ../..
cd clusters/shared && terraform destroy -auto-approve && cd ../..
cd network && terraform destroy -auto-approve && cd ..
```

---

## Pattern C: Prod/Non-Prod + NS-aaS (Recommended)

**Region:** us-east-2
**Architecture:** Separate prod + nonprod clusters, two-layer DCF (environment + namespace)

### Deploy

```bash
cd blueprints/prod-nonprod-hybrid/aws

# Layer 1: Network (~5-8 min)
cd network
terraform init
terraform apply -auto-approve
cd ..

# Layer 2: Clusters (~10-15 min each, run in parallel)
cd clusters/prod
terraform init
terraform apply -auto-approve &
cd ../..
cd clusters/nonprod
terraform init
terraform apply -auto-approve &
cd ../..
wait

# Add IAM role for kubectl access
ROLE_ARN=$(aws iam list-roles --query 'Roles[?contains(RoleName,`SubAccountAdmin`)].Arn' --output text)
for cluster in pc2-prod pc2-nonprod; do
  aws eks create-access-entry --cluster-name $cluster --region us-east-2 --principal-arn "$ROLE_ARN"
  aws eks associate-access-policy --cluster-name $cluster --region us-east-2 \
    --principal-arn "$ROLE_ARN" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster
done

# Layer 3: Nodes (~5-8 min each, run in parallel)
cd nodes/prod
terraform init
terraform apply -auto-approve &
cd ../..
cd nodes/nonprod
terraform init
terraform apply -auto-approve &
cd ../..
wait

# Layer 4: Namespaces + CRDs
aws eks update-kubeconfig --name pc2-prod --region us-east-2
kubectl apply -f k8s-apps/dcf-crd/prod-namespaces.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-prod.yaml

aws eks update-kubeconfig --name pc2-nonprod --region us-east-2
kubectl apply -f k8s-apps/dcf-crd/nonprod-namespaces.yaml
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-nonprod.yaml
```

### Verify

```bash
# Prod cluster
aws eks update-kubeconfig --name pc2-prod --region us-east-2
kubectl get nodes
kubectl get ns | grep -E "team|monitoring"

# Non-prod cluster
aws eks update-kubeconfig --name pc2-nonprod --region us-east-2
kubectl get nodes
kubectl get ns | grep -E "team|sandbox|monitoring"

# Check CoPilot:
#   Security > DCF — verify two-layer rules (env + namespace)
#   Verify prod<->nonprod traffic is DENIED
#   Verify nonprod cannot reach prod database spoke
```

### Destroy (reverse order)

```bash
cd blueprints/prod-nonprod-hybrid/aws

for env in prod nonprod; do
  cd nodes/$env && terraform destroy -auto-approve && cd ../..
done
for env in prod nonprod; do
  cd clusters/$env && terraform destroy -auto-approve && cd ../..
done
cd network && terraform destroy -auto-approve && cd ..
```

---

## Validation Checklist

### Network Layer
- [ ] Transit Gateway visible in CoPilot
- [ ] All Spoke Gateways attached to transit (green status)
- [ ] SNAT policies active on spoke gateways
- [ ] Route tables programmed (software-defined routing)

### DCF
- [ ] "Enforcement on Kubernetes" shows Enabled in CoPilot
- [ ] SmartGroups created and showing members
- [ ] DCF ruleset active with correct priority ordering
- [ ] WebGroups resolving (EKS required services)
- [ ] Geo-blocking and ThreatIQ SmartGroups active

### Kubernetes
- [ ] EKS clusters ACTIVE
- [ ] Nodes in Ready state
- [ ] k8s-firewall Helm chart installed (CRDs available)
- [ ] Namespaces created (Pattern B and C)
- [ ] FirewallPolicy CRDs applied

### Connectivity Tests
- [ ] Pod-to-pod within same cluster: works
- [ ] Pod-to-service cross-cluster (permitted pair): works via transit
- [ ] Pod-to-service cross-cluster (denied pair): blocked by DCF
- [ ] Pod-to-internet (approved WebGroup): works
- [ ] Pod-to-internet (unapproved): blocked
- [ ] Pattern C: nonprod-to-prod: DENIED (both directions)
- [ ] Pattern C: nonprod-to-prod-db: DENIED

---

## Troubleshooting

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| VPC/VNet name already exists | Orphaned resources from failed run | Delete via Aviatrix API or rename prefix |
| DCF attachment point conflict | Multiple `aviatrix_dcf_ruleset` on same controller | Use `aviatrix_distributed_firewalling_policy_list` instead |
| EKS CoreDNS DEGRADED | No nodes deployed yet | Deploy Layer 3 (nodes) — resolves automatically |
| SmartGroups empty | K8s clusters not discovered | Enable "Enforcement on Kubernetes" + wait for discovery |
| kubectl unauthorized | IAM role not in cluster access | Add via `aws eks create-access-entry` |
| VPC limit exceeded | Default 5 per region | Request increase to 20 via Service Quotas |
| EIP limit exceeded | Default 5 per region | Request increase to 20 via Service Quotas |
| SNAT not working | Pod CIDR not excluded from transit | Add `excluded_advertised_spoke_routes` on transit |
| `enable_segmentation` conflict | Can't use with `excluded_advertised_spoke_routes` | Remove `enable_segmentation` |

### Aviatrix API Cleanup (orphaned resources)

```bash
# Login
CID=$(curl -sk -X POST "https://$AVIATRIX_CONTROLLER_IP/v1/api" \
  -d "action=login&username=$AVIATRIX_USERNAME&password=$AVIATRIX_PASSWORD" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")

# Detach spoke from transit
curl -sk -X POST "https://$AVIATRIX_CONTROLLER_IP/v2/api" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"detach_spoke_from_transit_gw\",\"CID\":\"$CID\",\"spoke_gw\":\"<spoke-name>\"}"

# Delete gateway
curl -sk -X POST "https://$AVIATRIX_CONTROLLER_IP/v2/api" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"delete_container\",\"CID\":\"$CID\",\"cloud_type\":1,\"gw_name\":\"<gw-name>\"}"

# Delete VPC from controller
curl -sk -X POST "https://$AVIATRIX_CONTROLLER_IP/v2/api" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"delete_custom_vpc\",\"CID\":\"$CID\",\"cloud_type\":1,\"account_name\":\"lab-test-aws\",\"pool_name\":\"<vpc-name>\"}"

# Note: Transit GWs with FireNet need terraform import + destroy
```

---

## Current Deployment Status

| Pattern | Region | Network | Clusters | Nodes | CRDs |
|---------|--------|---------|----------|-------|------|
| A: Cluster-aaS | us-west-2 | DONE | Deploying | - | - |
| B: Namespace-aaS | us-east-1 | DONE | DONE | DONE | Pending |
| C: Prod/Non-Prod | us-east-2 | DONE | DONE | Pending | Pending |
