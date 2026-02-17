# EKS VPC Module

This module creates a VPC optimized for EKS clusters with overlapping pod CIDRs using Aviatrix network architecture.

## Architecture

The module creates:

- **Primary CIDR** (/23): For infrastructure resources
  - Aviatrix gateway subnets (2x /28) - Dedicated for Aviatrix spoke gateways
  - Load balancer subnets (2x /26) - For ALB/NLB
  - Infrastructure subnets (2x /26) - For EKS nodes and control plane ENIs

- **Secondary CIDR** (/16): For EKS pods
  - Pod subnets (2x /17) - Can overlap across VPCs (100.64.0.0/16)

## Subnet Layout Example (10.10.0.0/23)

```
Primary CIDR: 10.10.0.0/23
├── 10.10.0.0/28     → Aviatrix Gateway AZ1 (16 IPs)
├── 10.10.0.16/28    → Aviatrix Gateway AZ2 (16 IPs)
├── 10.10.0.32/26    → Load Balancer AZ1 (64 IPs)
├── 10.10.0.96/26    → Load Balancer AZ2 (64 IPs)
├── 10.10.0.160/26   → Infrastructure AZ1 (64 IPs)
└── 10.10.0.224/26   → Infrastructure AZ2 (64 IPs)

Secondary CIDR: 100.64.0.0/16
├── 100.64.0.0/17    → Pods AZ1 (32,768 IPs)
└── 100.64.128.0/17  → Pods AZ2 (32,768 IPs)
```

## Usage

```hcl
module "frontend_vpc" {
  source = "./eks-vpc"

  name           = "frontend"
  cluster_name   = "frontend-cluster"
  primary_cidr   = "10.10.0.0/23"
  secondary_cidr = "100.64.0.0/16"
  region         = "us-east-2"

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
  }
}
```

## Integration with Aviatrix

This VPC is designed to work with Aviatrix mc-spoke module in `use_existing_vpc` mode:

```hcl
module "spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  use_existing_vpc = true
  vpc_id           = module.vpc.vpc_id
  gw_subnet        = module.vpc.avx_gateway_subnet_cidrs[0]
  hagw_subnet      = module.vpc.avx_gateway_subnet_cidrs[1]
  # ... other spoke config
}
```

## Route Tables

- **avx-public-rt**: For Aviatrix gateway subnets (IGW route only)
- **lb-public-rt**: For load balancer subnets (IGW route only)
- **private-rt**: For all private subnets (managed by Aviatrix, uses `ignore_changes`)

## Key Features

1. **Separated Aviatrix Subnets**: Dedicated /28 subnets for gateway deployment
2. **EKS-Tagged Subnets**: Proper tagging for ALB/NLB discovery
3. **Secondary CIDR Support**: Non-routable pod IPs (100.64.0.0/16)
4. **Lifecycle Management**: Route table changes ignored (Aviatrix manages them)
5. **Multi-AZ**: Spreads resources across 2 availability zones
