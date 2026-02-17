# EKS Node Group Module

This module creates EKS managed node groups **separately** from the EKS cluster.

## Why Separate?

This solves the "chicken-and-egg" problem in Terraform where:
- Node group `count`/`for_each` depends on cluster outputs
- Cluster outputs don't exist during initial `terraform plan`
- Terraform fails with: `The "count" value depends on resource attributes that cannot be determined until apply`

By deploying node groups in a separate Terraform state **after** the cluster exists, all required values are known at plan time.

## Usage

```hcl
module "node_group" {
  source = "../shared-modules/eks-node-group"

  cluster_name       = data.terraform_remote_state.cluster.outputs.cluster_name
  kubernetes_version = data.terraform_remote_state.cluster.outputs.cluster_version

  # From network state (static)
  subnet_ids = data.terraform_remote_state.network.outputs.frontend_infra_private_subnet_ids

  # From cluster state (exists at plan time)
  cluster_primary_security_group_id = data.terraform_remote_state.cluster.outputs.cluster_primary_security_group_id

  # Scaling
  min_size     = 1
  max_size     = 5
  desired_size = 2

  # Instance config
  instance_types = ["t3.large", "t3.xlarge"]
  capacity_type  = "SPOT"

  tags = {
    Environment = "demo"
  }
}
```

## Deployment Order

1. Deploy `network/` - Creates VPCs and subnets
2. Deploy `eks/frontend-cluster/` - Creates EKS control plane (no nodes)
3. Deploy `eks/frontend-nodes/` - Creates node groups (this module)

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| cluster_name | EKS cluster name | string | required |
| kubernetes_version | K8s version | string | required |
| subnet_ids | Subnet IDs for nodes | list(string) | required |
| cluster_primary_security_group_id | Cluster SG ID | string | required |
| min_size | Min nodes | number | 1 |
| max_size | Max nodes | number | 3 |
| desired_size | Desired nodes | number | 2 |
| instance_types | Instance types | list(string) | ["t3.large"] |
| capacity_type | ON_DEMAND or SPOT | string | "SPOT" |

## Outputs

| Name | Description |
|------|-------------|
| node_group_id | Node group ID |
| node_group_arn | Node group ARN |
| iam_role_arn | Node IAM role ARN |
