# Multi-Cluster EKS with Aviatrix Transit Architecture

This repository deploys a multi-cluster Kubernetes environment with Aviatrix transit networking, demonstrating Distributed Cloud Firewall (DCF) for Kubernetes capabilities.

> [!TIP]
> **🤖 Optimized for Claude Code** — Run `/deploy-blueprint` for AI-guided deployment with prerequisite checks and automated orchestration, or `/analyze-blueprint` for resource and cost details. [Get Claude Code](https://claude.ai/code)

---

## Prerequisites

Before deploying this infrastructure, ensure you have the following prerequisites in place.

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **Aviatrix Controller** | Version compatible with provider ~> 8.2 | Must be deployed and accessible |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **AWS Account Onboarded** | Account registered in Controller | Use the exact account name in `var.tfvars` |

### Local Tools

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.5 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| **AWS CLI** | v2 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS authentication and EKS kubectl auth |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster interaction |
| **Docker** | Latest | [Install Guide](https://docs.docker.com/get-docker/) | Container builds (optional) |

### AWS IAM Permissions

The AWS credentials used must have permissions to create and manage:

- **EKS**: Clusters, managed node groups, add-ons, OIDC providers
- **VPC**: VPCs, subnets, route tables, internet/NAT gateways, security groups
- **IAM**: Roles and policies (for IRSA, node groups, add-ons)
- **Route53**: Private hosted zones, record sets
- **ECR**: Repositories (for container images)
- **ELB**: Application and Network Load Balancers
- **EC2**: Instances (for database VM), key pairs, ENIs

> **Tip:** The `AdministratorAccess` managed policy provides all required permissions for demo environments. For production, create a scoped-down policy.

### Environment Variables

Set these before running Terraform:

```bash
# Required: Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<controller-ip-or-hostname>"
export AVIATRIX_USERNAME="<username>"
export AVIATRIX_PASSWORD="<password>"

# AWS credentials (one of these methods):
# Option 1: Environment variables
export AWS_ACCESS_KEY_ID="<access-key>"
export AWS_SECRET_ACCESS_KEY="<secret-key>"
export AWS_REGION="us-east-2"

# Option 2: AWS CLI profile (recommended)
aws configure --profile <profile-name>
export AWS_PROFILE="<profile-name>"
```

### Verify Prerequisites

Run these commands to verify your environment is ready:

```bash
# Check Terraform version
terraform version
# Expected: Terraform v1.5.x or higher

# Verify AWS CLI and credentials
aws sts get-caller-identity
# Expected: Returns your AWS account ID and IAM identity

# Verify kubectl is installed
kubectl version --client
# Expected: Client Version: v1.x.x

# Verify Docker (optional)
docker version
# Expected: Client and Server version info

# Test Aviatrix Controller connectivity
curl -k -s "https://${AVIATRIX_CONTROLLER_IP}/v1/api" | head -c 100
# Expected: JSON response (API is accessible)
```

### Provider Versions

This repository uses the following Terraform providers:

| Provider | Version | Source |
|----------|---------|--------|
| Aviatrix | ~> 8.2 | `AviatrixSystems/aviatrix` |
| AWS | ~> 6.0 | `hashicorp/aws` |
| Kubernetes | ~> 2.20 | `hashicorp/kubernetes` |
| Helm | ~> 2.x | `hashicorp/helm` |

---

## Quickstart

**For experienced users who want the essential commands only:**

```bash
# 0. Set environment variables
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="<username>"
export AVIATRIX_PASSWORD="<password>"

# 1. Deploy network infrastructure (~15-20 min)
cd network/
terraform init -upgrade
cp terraform.tfvars.example var.tfvars
# Edit var.tfvars with your values
terraform apply -var-file=var.tfvars

# 2. Deploy frontend cluster (~10-15 min)
cd ../clusters/frontend/
terraform init
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set aviatrix_controller_role_arn to your Controller's IAM role ARN
terraform apply

# 3. Deploy frontend nodes (~7-10 min)
cd ../../nodes/frontend/
terraform init
terraform apply

# 4. Configure kubectl for frontend
cd ../../clusters/frontend/
$(terraform output -raw configure_kubectl)
kubectl config rename-context $(kubectl config current-context) frontend-cluster
kubectl get nodes  # Should show 2 Ready nodes

# 5. Deploy backend cluster (~10-15 min)
cd ../backend/
terraform init
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set aviatrix_controller_role_arn to your Controller's IAM role ARN
terraform apply

# 6. Deploy backend nodes (~7-10 min)
cd ../../nodes/backend/
terraform init
terraform apply

# 7. Configure kubectl for backend
cd ../../clusters/backend/
$(terraform output -raw configure_kubectl)
kubectl config rename-context $(kubectl config current-context) backend-cluster
kubectl get nodes  # Should show 2 Ready nodes

# 8. Deploy Gatus monitoring (optional)
kubectl config use-context frontend-cluster
kubectl create namespace gatus
kubectl apply -f ../../k8s-apps/frontend/gatus.yaml

kubectl config use-context backend-cluster
kubectl create namespace gatus
kubectl apply -f ../../k8s-apps/backend/gatus.yaml

```

**Total deployment time:** ~45-60 minutes (infrastructure)

---

## Architecture Overview

![Architecture Diagram](architecture.svg)

### Key Features

- **Overlapping Pod CIDRs**: Both EKS clusters use non-routable 100.64.0.0/16 for pods (RFC6598 CGNAT space)
- **Aviatrix Custom SNAT**: Pod traffic is NATted to spoke gateway IPs for transit routing
- **Aviatrix Distributed Cloud Firewall (DCF)**: Kubernetes-native firewall policies via FirewallPolicy CRD
- **Route53 Private Hosted Zone**: Internal DNS (aws.aviatrixdemo.local) shared across all VPCs
- **ExternalDNS Integration**: Automatic DNS record creation for Kubernetes services
- **Separated Subnets**: Dedicated subnets for Aviatrix gateways, load balancers, infrastructure, and pods
- **Fully Automated**: VPC CNI custom networking, Kubernetes add-ons, and Aviatrix CRDs deployed via Terraform

### 3-Layer Deployment Architecture

The infrastructure is deployed in **three layers** to solve the Terraform "chicken-and-egg" problem where node group `count`/`for_each` depends on cluster outputs that don't exist during initial plan.

```
Layer 1: Network Infrastructure
├── network/                    # Transit, Spokes, VPCs, DB VM, Route53

Layer 2: EKS Clusters (Control Plane Only)
├── clusters/frontend/          # Control plane, IAM roles, security groups, VPC CNI addon
├── clusters/backend/           # Control plane, IAM roles, security groups, VPC CNI addon

Layer 3: EKS Node Groups + Kubernetes Resources
├── nodes/frontend/             # k8s-firewall Helm, ENIConfig, nodes, CoreDNS, Helm charts (ALB Controller, ExternalDNS)
├── nodes/backend/              # k8s-firewall Helm, ENIConfig, nodes, CoreDNS, Helm charts (ALB Controller, ExternalDNS)
```

Each layer reads the previous layer's state via `terraform_remote_state` data sources.

---

## Complete Deployment Guide

> **Note:** Ensure you have completed all items in the [Prerequisites](#prerequisites) section before proceeding.

### Step 1: Set Environment Variables

Set your Aviatrix Controller credentials and verify AWS access:

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="<username>"
export AVIATRIX_PASSWORD="<password>"

# Verify AWS credentials
aws sts get-caller-identity
```

### Step 2: Deploy Network Infrastructure

The network layer creates the Aviatrix transit/spoke topology, VPCs with custom subnets, Route53 private hosted zone, and database VM.

```bash
cd network/

# Initialize Terraform
terraform init -upgrade

# Create your variable file
cp terraform.tfvars.example var.tfvars

# Edit with your values:
# - aviatrix_aws_account_name: AWS account name registered in Aviatrix Controller
# - aws_region: Deployment region (default: us-east-2)
vim var.tfvars

# Deploy network infrastructure (~15-20 minutes)
terraform apply -var-file=var.tfvars
```

**What's created:**
- Aviatrix Transit Gateway (us-east-2)
- Frontend spoke VPC (10.10.0.0/23) with Aviatrix gateway
- Backend spoke VPC (10.20.0.0/23) with Aviatrix gateway
- Database spoke VPC (10.5.0.0/22) with Apache test VM
- Route53 private hosted zone (aws.aviatrixdemo.local)
- VPCs with primary and secondary CIDRs for pod networking
- Custom SNAT policies (100.64.0.0/16 → spoke gateway IPs)
- Subnets: Aviatrix gateway (/28), Load balancer (/26), Infrastructure (/26), Pods (/17)

### Step 3: Deploy Frontend EKS Cluster

The cluster layer creates the EKS control plane, security groups, OIDC provider, IAM roles for add-ons, and VPC CNI addon with custom networking enabled.

```bash
cd ../clusters/frontend/

# Initialize Terraform
terraform init

# Create your variable file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars:
# - aviatrix_controller_role_arn: Your Aviatrix Controller's IAM role ARN
#   (e.g., arn:aws:iam::123456789012:role/aviatrix-role-app)
vim terraform.tfvars

# Deploy cluster (~10-15 minutes)
terraform apply
```

**What's created:**
- EKS control plane
- Cluster security groups
- OIDC provider for IRSA
- IAM roles for ALB Controller and ExternalDNS
- Pod security group for VPC CNI custom networking
- Route53 zone association
- VPC CNI addon with custom networking settings (`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`)

**Note:** No node groups or Helm charts are deployed yet—those come in Step 4.

### Step 4: Deploy Frontend Node Groups

The node layer creates ENIConfig resources, managed node groups, and automatically installs Kubernetes add-ons via Terraform's Helm provider.

```bash
cd ../../nodes/frontend/

# Initialize and deploy nodes (~7-10 minutes)
terraform init
terraform apply
```

**What's created:**
- Aviatrix k8s-firewall Helm chart (FirewallPolicy + WebGroupPolicy CRDs)
- ENIConfig resources (one per availability zone) - created BEFORE nodes
- EKS managed node groups
- Node IAM roles with SSM access
- CoreDNS addon
- AWS Load Balancer Controller v1.10.1 (via Helm)
- ExternalDNS v1.19.0 (via Helm)

**Deployment order:** k8s-firewall Helm chart → ENIConfig → Node Groups → CoreDNS → Helm Charts (ALB Controller, ExternalDNS)

**⚠️ IMPORTANT:** You cannot run kubectl commands until you configure kubectl in Step 5.

### Step 5: Configure kubectl for Frontend Cluster

Before you can run any kubectl commands, you must configure kubectl to connect to your EKS cluster.

```bash
# Go to the frontend cluster directory (NOT frontend nodes!)
cd ../../clusters/frontend/

# Configure kubectl
$(terraform output -raw configure_kubectl)

# Rename context for easier switching
kubectl config rename-context $(kubectl config current-context) frontend-cluster

# Verify the cluster is accessible
kubectl get nodes
```

**Expected output:**
```
NAME                                        STATUS   ROLES    AGE     VERSION
ip-10-10-1-100.us-east-2.compute.internal   Ready    <none>   9m30s   v1.34.2-eks-ecaa3a6
ip-10-10-1-163.us-east-2.compute.internal   Ready    <none>   9m29s   v1.34.2-eks-ecaa3a6
```

**Verify the deployment:**

```bash
# Check Aviatrix DCF CRDs
kubectl get crd firewallpolicies.networking.aviatrix.com
kubectl get crd webgrouppolicies.networking.aviatrix.com
```

**Expected output:**
```
NAME                                          CREATED AT
firewallpolicies.networking.aviatrix.com      2025-11-28T...
```

```bash
# Check ENIConfig resources (one per AZ)
kubectl get eniconfig
```

**Expected output:**
```
NAME         AGE
us-east-2a   10m
us-east-2b   10m
```

```bash
# Check Helm charts were installed
kubectl get deployment -n kube-system aws-load-balancer-controller
```

**Expected output:**
```
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           8m34s
```

```bash
kubectl get deployment -n kube-system external-dns
```

**Expected output:**
```
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
external-dns   1/1     1            1           8m15s
```

```bash
# Verify pods have IPs from secondary CIDR (100.64.x.x)
kubectl get pods -A -o wide
```

**Expected output (showing pods with 100.64.x.x IPs):**
```
NAMESPACE     NAME                                            READY   STATUS    RESTARTS   AGE     IP               NODE
gatus         frontend-6dc84fcdd9-f7qr6                       1/1     Running   0          5m32s   100.64.167.228   ip-10-10-1-163...
gatus         frontend-6dc84fcdd9-qwtrk                       1/1     Running   0          5m32s   100.64.78.17     ip-10-10-1-100...
kube-system   aws-load-balancer-controller-7c4f49bc94-86drs   1/1     Running   0          8m36s   100.64.141.82    ip-10-10-1-163...
kube-system   aws-load-balancer-controller-7c4f49bc94-mqwmc   1/1     Running   0          8m36s   100.64.77.27     ip-10-10-1-100...
kube-system   aws-node-22pjm                                  2/2     Running   0          9m45s   10.10.1.100      ip-10-10-1-100...
kube-system   aws-node-jmlc4                                  2/2     Running   0          9m44s   10.10.1.163      ip-10-10-1-163...
kube-system   coredns-57894bd5c4-59rhc                        1/1     Running   0          8m49s   100.64.116.208   ip-10-10-1-100...
kube-system   coredns-57894bd5c4-6stlc                        1/1     Running   0          8m49s   100.64.147.81    ip-10-10-1-163...
kube-system   external-dns-7bc8dd7b9-vz67f                    1/1     Running   0          8m16s   100.64.75.21     ip-10-10-1-100...
kube-system   kube-proxy-6jsxj                                1/1     Running   0          9m45s   10.10.1.100      ip-10-10-1-100...
kube-system   kube-proxy-xmt8f                                1/1     Running   0          9m44s   10.10.1.163      ip-10-10-1-163...
```

**Note:** Most pods (except aws-node and kube-proxy) should have IPs from the 100.64.0.0/16 range.

### Step 6: Deploy Backend EKS Cluster

```bash
cd ../backend/

# Initialize Terraform
terraform init

# Create your variable file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars:
# - aviatrix_controller_role_arn: Your Aviatrix Controller's IAM role ARN
#   (same value used for the frontend cluster)
vim terraform.tfvars

# Deploy cluster (~10-15 minutes)
terraform apply
```

**What's created:** Same as frontend cluster (control plane, IAM, security groups, VPC CNI addon)

### Step 7: Deploy Backend Node Groups

```bash
cd ../../nodes/backend/

# Initialize and deploy nodes (~7-10 minutes)
terraform init
terraform apply
```

**What's created:** Same as frontend nodes (k8s-firewall Helm chart, ENIConfig, node groups, CoreDNS, Helm charts)

### Step 8: Configure kubectl for Backend Cluster

```bash
# Go to the backend cluster directory (NOT backend nodes!)
cd ../../clusters/backend/

# Configure kubectl
$(terraform output -raw configure_kubectl)

# Rename context for easier switching
kubectl config rename-context $(kubectl config current-context) backend-cluster

# Verify the cluster is accessible
kubectl get nodes
```

**Verify both clusters are configured:**

```bash
# View all configured contexts
kubectl config get-contexts
```

**Expected output (showing both clusters):**
```
CURRENT   NAME               CLUSTER            AUTHINFO           NAMESPACE
*         backend-cluster    arn:aws:eks:...    arn:aws:eks:...
          frontend-cluster   arn:aws:eks:...    arn:aws:eks:...
```

```bash
# Test switching between clusters
kubectl config use-context frontend-cluster
kubectl get nodes
```

**Expected output:**
```
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-10-1-100.us-east-2.compute.internal   Ready    <none>   20m   v1.34.2-eks-ecaa3a6
ip-10-10-1-163.us-east-2.compute.internal   Ready    <none>   20m   v1.34.2-eks-ecaa3a6
```

```bash
kubectl config use-context backend-cluster
kubectl get nodes
```

**Expected output:**
```
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-20-1-45.us-east-2.compute.internal    Ready    <none>   12m   v1.34.2-eks-ecaa3a6
ip-10-20-1-98.us-east-2.compute.internal    Ready    <none>   12m   v1.34.2-eks-ecaa3a6
```

### Step 9: Deploy Applications (Optional)

#### Deploy Gatus Monitoring

```bash
# Frontend Gatus
kubectl config use-context frontend-cluster
kubectl create namespace gatus
kubectl apply -f ../../k8s-apps/frontend/gatus.yaml

# Backend Gatus
kubectl config use-context backend-cluster
kubectl create namespace gatus
kubectl apply -f ../../k8s-apps/backend/gatus.yaml
```

### Step 10: Verify Deployment

**Verify Aviatrix DCF CRDs:**

```bash
# Verify CRDs are installed in both clusters
kubectl config use-context frontend-cluster
kubectl get crd firewallpolicies.networking.aviatrix.com
kubectl get crd webgrouppolicies.networking.aviatrix.com

kubectl config use-context backend-cluster
kubectl get crd firewallpolicies.networking.aviatrix.com
kubectl get crd webgrouppolicies.networking.aviatrix.com
```

**Expected output (for both clusters):**
```
NAME                                          CREATED AT
firewallpolicies.networking.aviatrix.com      2025-11-28T...
```

**Verify pod networking:**

```bash
# Check all pod IPs are from secondary CIDR (100.64.x.x)
kubectl config use-context frontend-cluster
kubectl get pods -A -o wide
```

**Test DNS resolution:**

```bash
# Test DNS from a pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nslookup db.aws.aviatrixdemo.local
```

**Test database connectivity:**

```bash
# Test HTTP connectivity to database VM
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -s http://db.aws.aviatrixdemo.local
```

**Check Route53 records:**

```bash
cd ../../network/
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -raw route53_zone_id) \
  --output table
```

**Get LoadBalancer and DNS names:**

```bash
# Get LoadBalancer services
kubectl get svc -o wide
```

**Expected output:**
```
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP                                                      PORT(S)          AGE
frontend     LoadBalancer   172.20.34.212   k8s-gatus-frontend-cc1bd8d207-xxx.elb.us-east-2.amazonaws.com    8080:32502/TCP   10m
kubernetes   ClusterIP      172.20.0.1      <none>                                                           443/TCP          20m
```

```bash
# Get Ingress resources
kubectl get ingress -A
```

**Expected output:**
```
NAMESPACE   NAME               CLASS   HOSTS   ADDRESS                                                     PORTS   AGE
gatus       frontend-ingress   alb     *       k8s-gatus-frontend-xxx.us-east-2.elb.amazonaws.com          80      10m
```

```bash
# Check Route53 records created by ExternalDNS
ZONE_ID=$(terraform output -raw route53_zone_id)
aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='A' || Type=='CNAME']" --output table
```

---

## How It Works

### VPC CNI Custom Networking

Both clusters use CNI custom networking to assign pod IPs from a non-routable secondary CIDR (100.64.0.0/16). This is **fully automated via Terraform**.

**Layer 2 (Cluster) Configuration:**
- VPC CNI addon with custom networking enabled (`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`)
- `ENI_CONFIG_LABEL_DEF` set to `topology.kubernetes.io/zone` (matches ENIConfigs by AZ)
- `AWS_VPC_K8S_CNI_EXTERNALSNAT=true` (disables CNI SNAT, allows Aviatrix SNAT)
- Pod security group with proper ingress/egress rules

**Layer 3 (Nodes) Configuration:**
- ENIConfig resources for each availability zone (created BEFORE nodes)
- Node groups that use the ENIConfig for pod networking

**Verify CNI configuration:**

```bash
kubectl config use-context frontend-cluster

# Verify ENIConfigs
kubectl get eniconfig
```

**Expected output:**
```
NAME         AGE
us-east-2a   15m
us-east-2b   15m
```

```bash
# Verify CNI custom networking is enabled
kubectl get daemonset aws-node -n kube-system -o yaml | grep -A1 CUSTOM_NETWORK
```

**Expected output:**
```
        - name: AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG
          value: "true"
```

```bash
# Verify external SNAT is enabled (for Aviatrix SNAT)
kubectl get daemonset aws-node -n kube-system -o yaml | grep -A1 EXTERNALSNAT
```

**Expected output:**
```
        - name: AWS_VPC_K8S_CNI_EXTERNALSNAT
          value: "true"
```

```bash
# Verify pods have IPs from secondary CIDR
kubectl get pods -A -o wide | grep 100.64
```

**Expected output (truncated, showing 100.64.x.x IPs):**
```
gatus         frontend-6dc84fcdd9-f7qr6                       1/1     Running   0   10m   100.64.167.228   ip-10-10-1-163...
gatus         frontend-6dc84fcdd9-qwtrk                       1/1     Running   0   10m   100.64.78.17     ip-10-10-1-100...
kube-system   coredns-57894bd5c4-59rhc                        1/1     Running   0   12m   100.64.116.208   ip-10-10-1-100...
kube-system   coredns-57894bd5c4-6stlc                        1/1     Running   0   12m   100.64.147.81    ip-10-10-1-163...
```

### Kubernetes Add-ons (Automated)

**AWS Load Balancer Controller** and **ExternalDNS** are automatically installed via Terraform's Helm provider in Layer 3 (node deployment).

**What's installed:**
- AWS Load Balancer Controller v1.10.1 - Manages ALB/NLB for Services and Ingress
- ExternalDNS v1.19.0 - Creates Route53 DNS records for Services and Ingress

**Both add-ons are configured with:**
- IRSA (IAM Roles for Service Accounts) for secure AWS API access
- Proper VPC ID and region settings (required for custom networking)
- Route53 private hosted zone integration

**Why install in Layer 3?**
- The cluster must exist (created in Layer 2)
- Nodes must be running to schedule the Helm chart pods
- ENIConfig must be applied first for proper pod networking

**View add-on logs:**

```bash
# AWS Load Balancer Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=5
```

**Expected output:**
```
{"level":"info","ts":"2025-11-27T01:37:23Z","logger":"controller-runtime.webhook","msg":"Starting webhook server"}
{"level":"info","ts":"2025-11-27T01:37:23Z","logger":"controller-runtime.certwatcher","msg":"Updated current TLS certificate"}
{"level":"info","ts":"2025-11-27T01:37:23Z","logger":"controller-runtime.webhook","msg":"Serving webhook server","host":"","port":9443}
{"level":"info","ts":"2025-11-27T01:40:37Z","msg":"Successful reconcile","tgb":{"name":"k8s-default-frontend-f3ec21cdb7","namespace":"default"}}
{"level":"info","ts":"2025-11-27T01:47:07Z","msg":"v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/EndpointSlice"}
```

```bash
# ExternalDNS
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=5
```

**Expected output:**
```
time="2025-11-27T02:01:58Z" level=info msg="All records are already up to date"
time="2025-11-27T02:02:59Z" level=info msg="Applying provider record filter for domains: [aws.aviatrixdemo.local. .aws.aviatrixdemo.local.]"
time="2025-11-27T02:02:59Z" level=info msg="All records are already up to date"
time="2025-11-27T02:03:59Z" level=info msg="Applying provider record filter for domains: [aws.aviatrixdemo.local. .aws.aviatrixdemo.local.]"
time="2025-11-27T02:03:59Z" level=info msg="All records are already up to date"
```

### Aviatrix Distributed Cloud Firewall (DCF)

The **k8s-firewall Helm chart** installs CRDs that enable Kubernetes-native management of Aviatrix firewall policies. This chart is automatically installed during Layer 3 node deployment.

**What It Does:**
- Enables declarative firewall policies using Kubernetes manifests
- Supports SmartGroups for dynamic resource grouping (CIDR, K8s labels, cloud tags)
- Provides WebGroups for domain-based filtering
- Integrates with Aviatrix Distributed Cloud Firewall for centralized policy enforcement

**Helm Chart Installation:**
The k8s-firewall chart is installed via Terraform during node deployment:
```hcl
resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"
  wait       = false
}
```

**Installed CRDs:**
- `firewallpolicies.networking.aviatrix.com` - Define firewall rules for pod traffic
- `webgrouppolicies.networking.aviatrix.com` - Define domain-based filtering policies

**Example FirewallPolicy Resource:**
```yaml
apiVersion: networking.aviatrix.com/v1alpha1
kind: FirewallPolicy
metadata:
  name: allow-external-api
  namespace: default
spec:
  rules:
    - name: allow-https-egress
      selector:
        service: my-app
      action: permit
      protocol: tcp
      port: 443
      destinationSmartGroups:
        - name: internet
      webGroups:
        - name: trusted-apis
```

**Key Features:**
- **SmartGroups**: Dynamic grouping by VPC name, hostname (FQDN), CIDR, Kubernetes labels, cloud provider tags, region, zone
- **WebGroups**: Domain-based filtering (e.g., allow traffic to `*.example.com`)
- **Actions**: `permit`, `deny`, `intrusion_detection_permit`
- **Protocols**: TCP, UDP, ICMP, any
- **Bandwidth Limits**: Per-connection, per-source-IP, or per-policy
- **Logging**: Optional traffic logging for matched rules

**Verify CRD Installation:**
```bash
# Check CRDs exist
kubectl get crd firewallpolicies.networking.aviatrix.com
kubectl get crd webgrouppolicies.networking.aviatrix.com

# List all FirewallPolicy resources
kubectl get firewallpolicies -A
kubectl get webgrouppolicies -A

# Describe a specific policy
kubectl describe firewallpolicy <policy-name> -n <namespace>
```

**GitOps Integration:**
Store FirewallPolicy manifests in your Git repository alongside application manifests for version-controlled, auditable firewall rules.

### Aviatrix SNAT Configuration

Custom SNAT policies on each spoke gateway translate pod IPs to the spoke gateway's private IP:

- **Source CIDR**: 100.64.0.0/16 (pod CIDR)
- **Destination**: 0.0.0.0/0
- **SNAT IP**: Spoke gateway private IP
- **Purpose**: Allows overlapping pod CIDRs while maintaining unique source IPs in transit

**Traffic flow example:**

```
Frontend Pod (100.64.x.x)
  → Frontend Spoke Gateway [SNAT to 10.10.x.x]
  → Transit Gateway
  → Backend Spoke Gateway [route to 10.20.x.x]
  → Backend Service/LoadBalancer
  → Backend Pod (100.64.y.y)
```

### NLB Configuration for Non-Routable Pod CIDRs

**⚠️ CRITICAL:** When using LoadBalancer Services with non-routable pod CIDRs (100.64.0.0/16), you **must** configure NLBs to use **IP target type**. This is required for the Aviatrix SNAT design to work correctly.

**Why this matters:**
- **Instance target type (default)**: NLB preserves client source IP → return traffic bypasses NLB → asymmetric routing breaks Aviatrix SNAT
- **IP target type**: NLB performs SNAT → return traffic goes back through NLB → symmetric routing works with Aviatrix SNAT

**Required Service annotation:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    # REQUIRED for non-routable pod CIDRs with Aviatrix SNAT
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
spec:
  type: LoadBalancer
  ...
```

**What this annotation does:**
1. Targets pod IPs directly (100.64.x.x) instead of EC2 instances via NodePort
2. Automatically disables client IP preservation (`preserve_client_ip.enabled: false`)
3. Ensures return traffic flows back through NLB, maintaining symmetric routing

**Note:** ALB Ingress resources already use IP target type by default when you specify `alb.ingress.kubernetes.io/target-type: ip`, so they work correctly out of the box.

---

## Day 2 Operations

### Scale Node Groups

Node scaling changes don't require touching the cluster:

```bash
cd nodes/frontend/

# Edit terraform.tfvars
vim terraform.tfvars
# Change min_size, max_size, desired_size

# Apply changes (~2-3 minutes)
terraform apply
```

### Upgrade Kubernetes Version

Upgrade cluster first, then nodes:

```bash
# Step 1: Upgrade control plane
cd clusters/frontend/
vim terraform.tfvars  # Update kubernetes_version
terraform apply

# Step 2: Upgrade node groups
cd ../../nodes/frontend/
terraform apply
# Terraform will create new nodes and drain old ones
```

### Add a New Node Group

```bash
cd nodes/frontend/

# Add another module block in main.tf:
# module "gpu_node_group" {
#   source = "../shared-modules/eks-node-group"
#   ...
# }

terraform apply
```

### Destroy Infrastructure

Always destroy in reverse order. **Critical:** ExternalDNS creates Route53 records that must be cleaned up before destroying the node groups, otherwise DNS records will be orphaned.

```bash
# Step 1: Remove Kubernetes resources (clean up ALBs/NLBs and trigger DNS cleanup)
kubectl config use-context frontend-cluster
kubectl delete ingress --all -A
kubectl delete svc -A --field-selector spec.type=LoadBalancer

kubectl config use-context backend-cluster
kubectl delete ingress --all -A
kubectl delete svc -A --field-selector spec.type=LoadBalancer

# Wait for LoadBalancers and DNS records to be deleted
sleep 60

# Step 2: Verify DNS records are cleaned up (only db.* should remain)
cd network/
ZONE_ID=$(terraform output -raw route53_zone_id)
aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='CNAME' || Type=='TXT']" --output table

# If CNAME/TXT records still exist, wait longer or manually delete them:
# aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID \
#   --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":{...}}]}'

# Step 3: Destroy node groups
cd ../nodes/backend/ && terraform destroy
cd ../frontend/ && terraform destroy

# Step 4: Destroy clusters
cd ../../clusters/backend/ && terraform destroy
cd ../frontend/ && terraform destroy

# Step 5: Destroy network (includes Route53 hosted zone)
cd ../../network/ && terraform destroy -var-file=var.tfvars

# Step 6: Clean up kubectl contexts (optional)
kubectl config delete-context frontend-cluster
kubectl config delete-context backend-cluster
```

**Notes:**
- Destroying the network layer deletes the Route53 private hosted zone
- The `db.aws.aviatrixdemo.local` A record is Terraform-managed and deleted with the network layer
- If ExternalDNS-managed records (CNAME/TXT) are not deleted before Step 3, they will be orphaned and must be manually removed from Route53

---

## Troubleshooting

### Pods Can't Reach Other Clusters

1. **Verify SNAT configuration:**
   - In Aviatrix Controller: Gateway → Spoke Gateway → SNAT
   - Verify 100.64.0.0/16 source CIDR exists

2. **Check ENIConfig:**
   ```bash
   kubectl get eniconfig -o yaml
   ```

3. **Verify CNI configuration:**
   ```bash
   kubectl get daemonset aws-node -n kube-system -o yaml | grep -A1 EXTERNALSNAT
   # Should show: AWS_VPC_K8S_CNI_EXTERNALSNAT=true
   ```

4. **Check pod IP assignments:**
   ```bash
   kubectl get pods -A -o wide
   # Pod IPs should be from 100.64.x.x range
   ```

### Intermittent Connectivity to LoadBalancer Services

If cross-cluster connectivity via NLB is intermittent (some requests succeed, others timeout):

1. **Check NLB target type:**
   ```bash
   # Get target group ARN
   TG_ARN=$(aws elbv2 describe-target-groups --names "k8s-<namespace>-<service>-*" \
     --query "TargetGroups[0].TargetGroupArn" --output text)

   # Check target type (should be "ip", not "instance")
   aws elbv2 describe-target-groups --target-group-arns $TG_ARN \
     --query "TargetGroups[0].TargetType"
   ```

2. **Fix: Add IP target type annotation to Service:**
   ```yaml
   metadata:
     annotations:
       service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
   ```

3. **Re-apply the Service** (may need to delete and recreate):
   ```bash
   kubectl delete svc <service-name> -n <namespace>
   kubectl apply -f <service-manifest>.yaml
   ```

**Root cause:** Instance target type preserves client IP, causing asymmetric routing that breaks Aviatrix SNAT. See [NLB Configuration for Non-Routable Pod CIDRs](#nlb-configuration-for-non-routable-pod-cidrs) for details.

### DNS Resolution Not Working

1. **Check ExternalDNS logs:**
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns
   ```

2. **Verify Route53 hosted zone associations:**
   ```bash
   aws route53 get-hosted-zone --id <zone-id>
   # Check VPCs list includes your cluster VPC
   ```

3. **Test DNS resolution from pod:**
   ```bash
   kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
     nslookup db.aws.aviatrixdemo.local
   ```

### LoadBalancer Service Stuck in Pending

1. **Check AWS Load Balancer Controller logs:**
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

2. **Verify IRSA is working:**
   ```bash
   kubectl describe sa aws-load-balancer-controller -n kube-system
   # Check annotations for eks.amazonaws.com/role-arn
   ```

3. **Verify IAM role permissions:**
   - IAM role needs AWSLoadBalancerControllerIAMPolicy

### Terraform "Chicken-and-Egg" Errors

If you see: `The "count" value depends on resource attributes that cannot be determined until apply`

1. Ensure you're deploying in the correct order: network → cluster → nodes
2. Verify cluster terraform.tfstate exists before running node deployment
3. Check data.tf paths are correct in frontend-nodes/data.tf and backend-nodes/data.tf

### Node Groups Not Joining Cluster

1. **Check node group status:**
   ```bash
   aws eks describe-nodegroup --cluster-name frontend-cluster --nodegroup-name <name>
   ```

2. **Check EC2 instances:**
   ```bash
   aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=frontend-cluster"
   ```

3. **Verify node IAM role has required policies:**
   - AmazonEKSWorkerNodePolicy
   - AmazonEKS_CNI_Policy
   - AmazonEC2ContainerRegistryReadOnly

---

## Directory Structure

```
aws-eks-multicluster/
├── network/                    # Layer 1: Network infrastructure
│   ├── main.tf                 # Transit, spokes, VPCs, DB VM
│   ├── outputs.tf              # Export VPC IDs, subnet IDs, Route53 zone
│   └── terraform.tfstate       # Network state
│
├── clusters/
│   ├── frontend/               # Layer 2: Frontend control plane
│   │   ├── main.tf             # Cluster, security groups, IRSA roles, VPC CNI addon
│   │   ├── data.tf             # Read network state
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   │
│   └── backend/                # Layer 2: Backend control plane
│
├── nodes/
│   ├── frontend/               # Layer 3: Frontend nodes and add-ons
│   │   ├── main.tf             # k8s-firewall Helm, ENIConfig, node groups, CoreDNS
│   │   ├── helm.tf             # ALB Controller, ExternalDNS
│   │   ├── data.tf             # Read network + cluster state
│   │   └── terraform.tfvars
│   │
│   └── backend/                # Layer 3: Backend nodes and add-ons
│
├── k8s-apps/                   # Kubernetes application manifests
│   ├── frontend/               # Frontend apps (Gatus)
│   └── backend/                # Backend apps (Gatus)
│
├── modules/                    # Shared Terraform modules
│   ├── eks-vpc/                # Custom VPC module
│   └── apache-vm/              # Test VM module
│
└── architecture.svg            # Architecture diagram
```

---

## State Dependencies

```
network/terraform.tfstate
    │
    ├── clusters/frontend/terraform.tfstate
    │       │
    │       └── nodes/frontend/terraform.tfstate
    │
    └── clusters/backend/terraform.tfstate
            │
            └── nodes/backend/terraform.tfstate
```

Each layer reads the previous layer's state via `terraform_remote_state` data sources.

---

## Networking Details

### Subnet Layout (per VPC)

| Subnet Type           | CIDR            | Purpose                           | AZ Coverage |
|-----------------------|-----------------|-----------------------------------|-------------|
| Aviatrix Gateway      | /28 (16 IPs)    | Aviatrix spoke gateways           | 2 AZs       |
| Load Balancer         | /26 (64 IPs)    | ALB/NLB ENIs                      | 2 AZs       |
| Infrastructure        | /26 (64 IPs)    | EKS nodes, control plane ENIs     | 2 AZs       |
| Pods                  | /17 (32k IPs)   | Pod ENIs (from secondary CIDR)    | 2 AZs       |

### CNI Configuration Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG` | `true` | Enables custom networking mode |
| `ENI_CONFIG_LABEL_DEF` | `topology.kubernetes.io/zone` | Matches ENIConfigs by AZ |
| `AWS_VPC_K8S_CNI_EXTERNALSNAT` | `true` | Disables CNI SNAT, allows Aviatrix SNAT |

---

## Benefits of 3-Layer Architecture

1. **No chicken-and-egg errors** - Cluster state exists before nodes plan
2. **No Kubernetes provider auth errors** - Kubernetes/Helm resources deployed only after cluster exists
3. **Faster iteration** - Change nodes without touching cluster (~2-5 min vs ~15 min)
4. **Better blast radius** - Node changes don't risk cluster stability
5. **Flexible scaling** - Add/remove node groups independently
6. **Smaller state files** - Easier troubleshooting
7. **Parallel deployments** - Frontend and backend can be deployed simultaneously
8. **Proper resource ordering** - ENIConfig → Nodes → Helm charts ensures correct pod networking

---

## Module Versions

Current versions (updated 2025-11-26):

- **Terraform**: >= 1.5
- **Aviatrix Provider**: ~> 8.1 (requires compatible controller version)
- **AWS Provider**: ~> 6.0
- **mc-transit module**: ~> 8.0
- **mc-spoke module**: ~> 8.0
- **terraform-aws-modules/eks/aws**: ~> 21.9
- **terraform-aws-modules/iam/aws**: ~> 6.2

---

## Additional Resources

- [CLAUDE.md.reference](CLAUDE.md.reference) - Detailed guidance for AI assistants working with this repository

## Contributing

When making changes:

1. Always run `terraform validate` before committing
2. Format code with `terraform fmt -recursive`
3. Update documentation if architectural decisions change
4. Test changes in a non-production environment first
5. Document breaking changes in version history

## Resource Inventory & Cost Estimate

This section provides a comprehensive inventory of all AWS and Aviatrix resources deployed by this infrastructure, along with estimated monthly costs for the us-east-2 region.

### Resource Inventory

#### Compute Resources

| Component | Resource Type | Quantity | Instance Size | Capacity | Notes |
|-----------|--------------|----------|---------------|----------|-------|
| **Aviatrix Gateways** | | | | | |
| Transit Gateway | EC2 | 1 | c5.xlarge | On-Demand | FireNet enabled, no HA |
| Frontend Spoke GW | EC2 | 1 | t3.medium | On-Demand | Custom SNAT, no HA |
| Backend Spoke GW | EC2 | 1 | t3.medium | On-Demand | Custom SNAT, no HA |
| DB Spoke GW | EC2 | 1 | t3.medium | On-Demand | Single IP SNAT, no HA |
| **EKS Control Planes** | | | | | |
| Frontend Cluster | EKS | 1 | - | - | K8s 1.33 |
| Backend Cluster | EKS | 1 | - | - | K8s 1.33 |
| **EKS Node Groups** | | | | | |
| Frontend Nodes | EC2 | 2 (desired) | t3.large | SPOT | min=1, max=3 |
| Backend Nodes | EC2 | 2 (desired) | t3.large | SPOT | min=1, max=3 |
| **Database** | | | | | |
| DB VM (Apache) | EC2 | 1 | t3.micro | On-Demand | Amazon Linux 2023 |

**Total EC2 Instances:** 9 (at desired state)

#### Networking Resources

| Component | Quantity | Details |
|-----------|----------|---------|
| VPCs | 4 | Transit (10.2.0.0/20), Frontend (10.10.0.0/23), Backend (10.20.0.0/23), Database (10.5.0.0/22) |
| Subnets | ~20 | Aviatrix GW, Load Balancer, Infrastructure, Pod subnets across 2 AZs |
| Internet Gateways | 2 | Frontend & Backend VPCs |
| NAT Gateways | **0** | Aviatrix SNAT replaces NAT GW (cost savings) |
| Route Tables | 8+ | Public and private per VPC |
| Security Groups | 6+ | Cluster, pod, and DB VM security groups |

#### DNS Resources

| Component | Quantity | Details |
|-----------|----------|---------|
| Route53 Private Zone | 1 | aws.aviatrixdemo.local |
| Zone Associations | 4 | All VPCs associated |
| Static DNS Records | 1 | db.aws.aviatrixdemo.local |

#### Storage & Registry

| Component | Type | Size | Details |
|-----------|------|------|---------|
| EBS Volumes (Nodes) | gp3 | ~20 GB each | 4 volumes (2 per cluster) |
| EBS Volume (DB VM) | gp3 | ~8 GB | Root volume |

---

### Monthly Cost Estimate (us-east-2)

#### EC2 Compute - Aviatrix Gateways

| Resource | Instance | Hourly Rate | Monthly (730 hrs) |
|----------|----------|-------------|-------------------|
| Transit Gateway | c5.xlarge | $0.1700 | $124.10 |
| Frontend Spoke GW | t3.medium | $0.0416 | $30.37 |
| Backend Spoke GW | t3.medium | $0.0416 | $30.37 |
| DB Spoke GW | t3.medium | $0.0416 | $30.37 |
| **Subtotal Gateways** | | | **$215.21** |

#### EC2 Compute - Other

| Resource | Instance | Hourly Rate | Monthly |
|----------|----------|-------------|---------|
| Database VM | t3.micro | $0.0104 | $7.59 |

#### EKS Control Plane

| Resource | Rate | Monthly |
|----------|------|---------|
| Frontend Cluster | $0.10/hr | $73.00 |
| Backend Cluster | $0.10/hr | $73.00 |
| **Subtotal EKS** | | **$146.00** |

#### EKS Node Groups (SPOT Pricing)

| Resource | Instance | Qty | SPOT Rate* | Monthly |
|----------|----------|-----|------------|---------|
| Frontend Nodes | t3.large | 2 | ~$0.025/hr | $36.50 |
| Backend Nodes | t3.large | 2 | ~$0.025/hr | $36.50 |
| **Subtotal Nodes** | | | | **$73.00** |

*SPOT pricing varies; t3.large SPOT in us-east-2 typically $0.02-0.03/hr vs $0.0832 on-demand

#### Storage

| Resource | Size | Rate | Monthly |
|----------|------|------|---------|
| EBS (4 nodes × 20GB gp3) | 80 GB | $0.08/GB | $6.40 |
| EBS (1 DB VM × 8GB) | 8 GB | $0.08/GB | $0.64 |
| **Subtotal Storage** | | | **$7.04** |

#### Networking

| Resource | Rate | Monthly |
|----------|------|---------|
| Route53 Private Zone | $0.50/zone | $0.50 |
| Route53 Queries | ~$0.40/1M | ~$0.10 |
| Internet Gateways | Free | $0.00 |
| VPCs/Subnets | Free | $0.00 |
| **NAT Gateways** | **None deployed** | **$0.00** |
| **Subtotal Networking** | | **$0.60** |

#### Data Transfer (Estimated)

| Type | Est. Volume | Rate | Monthly |
|------|-------------|------|---------|
| Cross-AZ (nodes/gateways) | ~100 GB | $0.01/GB | $1.00 |
| Internet Egress | ~50 GB | $0.09/GB | $4.50 |
| Inter-VPC via Transit | ~50 GB | Included | $0.00 |
| **Subtotal Transfer** | | | **~$5.50** |

---

### Total Monthly Cost Summary

| Category | Cost |
|----------|------|
| Aviatrix Gateway EC2 | $215.21 |
| Database VM EC2 | $7.59 |
| EKS Control Planes | $146.00 |
| EKS Nodes (SPOT) | $73.00 |
| Storage | $7.04 |
| Networking | $0.60 |
| Data Transfer | ~$5.50 |
| **TOTAL** | **~$455/month** |

### Cost Breakdown by Category

```
Aviatrix Gateways (EC2)  ██████████████████░░░  47.3%  ($215)
EKS Control Planes       ████████████░░░░░░░░░  32.1%  ($146)
EKS Nodes (SPOT)         ██████░░░░░░░░░░░░░░░  16.0%  ($73)
Other (storage/DB/xfer)  ██░░░░░░░░░░░░░░░░░░░   4.6%  ($21)
```

---

### Important Cost Exclusions

The estimates above do **NOT** include:

- **Aviatrix Licensing**: Separate licensing costs based on deployment type (PAYG via AWS Marketplace or BYOL)
- **Load Balancer Costs**: ALB/NLB created by Kubernetes services (~$16-22/month each + data processing)
- **CloudWatch Logs**: If enabled for EKS or gateways
- **AWS Support**: If not on Basic (free) tier

---

## License

This is a demonstration environment. Use at your own risk in production.
