# Apache VM Module

This module deploys a simple Apache web server VM for connectivity testing with EKS clusters.

## Purpose

The VM serves as a backend "database" or service endpoint that can be accessed from EKS clusters to demonstrate:
- East-west traffic routing through Aviatrix
- Network connectivity validation
- Load balancer configurations

## Resources Created

- **EC2 Instance** (t3.micro) running Amazon Linux 2023
- **Security Group** allowing RFC1918 ingress (10.0.0.0/8)
- **SSH Key Pair** generated via terraform-aws-modules/key-pair
- **Apache HTTP Server** installed via user data script

## Usage

```hcl
module "db" {
  source = "./apache-vm"

  vpc_id    = module.spoke_db.vpc.vpc_id
  subnet_id = module.spoke_db.vpc.private_subnets[0].subnet_id
  region    = "us-east-2"
}
```

## Accessing the VM

The VM is deployed in a private subnet with no public IP. Access options:

1. **AWS Systems Manager Session Manager** (no SSH key needed)
2. **AWS EC2 Instance Connect Endpoint** (recommended)
3. **SSH via bastion** (if bastion exists)

Example using EC2 Instance Connect:

```bash
# Get the instance ID
VM_IP=$(terraform output -raw db_private_ip)
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=$VM_IP" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Connect via SSM
aws ssm start-session --target $INSTANCE_ID
```

## Testing Apache

From an EKS pod:

```bash
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
curl http://<db_private_ip>
```

## Note

The hardcoded SSH key name (`avtx-cmchenry-aws-useast2`) is commented out in the current implementation. The module uses `terraform-aws-modules/key-pair` to generate a key instead.
