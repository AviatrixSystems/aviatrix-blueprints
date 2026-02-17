# EKS Cluster Module

This module deploys an EKS cluster configured for CNI custom networking with Aviatrix integration.

## Features

- **Configurable cluster name** - No hardcoded names
- **CNI Custom Networking** - Pods get IPs from secondary CIDR subnets
- **ENIConfig Resources** - Automatically created via Kubernetes provider
- **External SNAT Disabled** - Allows Aviatrix to perform SNAT
- **IRSA Roles** - Pre-configured for AWS Load Balancer Controller and ExternalDNS
- **Security Groups** - Separate SGs for nodes and pods
- **SPOT Instances** - Cost-optimized with configurable capacity type

## CNI Configuration

The module automatically configures VPC CNI with:

```yaml
AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG: "true"
ENI_CONFIG_LABEL_DEF: "topology.kubernetes.io/zone"
AWS_VPC_K8S_CNI_EXTERNALSNAT: "true"  # Critical for Aviatrix
```

## Usage

```hcl
module "frontend_eks" {
  source = "../shared-modules/eks-cluster"

  cluster_name       = "frontend-cluster"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.infra_private_subnet_ids  # For nodes
  pod_subnet_ids     = module.vpc.pod_private_subnet_ids    # For pods
  availability_zones = ["us-east-2a", "us-east-2b"]
  region             = "us-east-2"

  node_group_config = {
    min_size       = 1
    max_size       = 3
    desired_size   = 2
    instance_types = ["t3.large"]
    capacity_type  = "SPOT"
  }

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
  }
}
```

## Post-Deployment

After cluster creation, configure kubectl:

```bash
aws eks update-kubeconfig --region us-east-2 --name frontend-cluster
```

Verify CNI configuration:

```bash
kubectl get eniconfigs
kubectl describe daemonset -n kube-system aws-node
```

## Integration with Aviatrix

This cluster is designed to work with Aviatrix spoke gateway SNAT:

1. **Pods get IPs from secondary CIDR** (100.64.0.0/16)
2. **CNI external SNAT is disabled** (`AWS_VPC_K8S_CNI_EXTERNALSNAT=true`)
3. **Aviatrix spoke gateway performs SNAT** to translate pod IPs to routable IPs

Traffic flow:
```
Pod (100.64.x.x) → Aviatrix Spoke GW → SNAT to 10.x.x.x → Transit GW
```

## IAM Roles

The module creates IRSA roles for:

1. **AWS Load Balancer Controller** - For ALB/NLB provisioning
2. **ExternalDNS** - For Route53 DNS management

Use these role ARNs when deploying the controllers:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: <alb_controller_role_arn>
```

## Security Groups

- **Cluster Additional SG**: Allows monitoring traffic (ports 8080-8081)
- **Node SG**: Managed by EKS module
- **Pod SG**: Used in ENIConfig, allows traffic from nodes and other pods
