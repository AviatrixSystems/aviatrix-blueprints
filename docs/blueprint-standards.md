# Blueprint Standards

Every Aviatrix Blueprint must meet these standards to ensure consistency, quality, and usability.

## Required README Sections

Each blueprint's README.md must include the following sections:

### 1. Title and Description

```markdown
# Blueprint Name

Brief description of what this blueprint deploys and demonstrates.
One to three sentences covering the use case and key Aviatrix features.
```

### 2. Architecture Diagram

A visual representation of the deployed infrastructure:

```markdown
## Architecture

![Architecture Diagram](architecture.png)

Brief explanation of the architecture and data flows.
```

Requirements:
- PNG or SVG format
- Clearly labeled components
- Show network connectivity and Aviatrix components
- Include cloud provider regions/availability zones

### 3. Prerequisites

Link to shared prerequisite docs plus any blueprint-specific requirements:

```markdown
## Prerequisites

### Required Tools
- [Aviatrix Control Plane](../../docs/prerequisites/aviatrix-controller.md) (v7.1+) - Controller and CoPilot
- [Terraform](../../docs/prerequisites/terraform.md) (v1.5+)
- [AWS CLI](../../docs/prerequisites/aws-cli.md)
- [kubectl](../../docs/prerequisites/kubectl.md)

### Required Access
- AWS account with permissions to create VPCs, EKS, EC2, etc.
- Aviatrix Control Plane with AWS account onboarded

### Blueprint-Specific Requirements
- At least 3 available EIPs in the target region
- Service quota for EKS clusters
```

### 4. Resources Created

A table listing all cloud resources that will be created:

```markdown
## Resources Created

| Resource | Description | Quantity |
|----------|-------------|----------|
| AWS VPC | Transit and spoke VPCs | 3 |
| Aviatrix Transit Gateway | Primary transit gateway | 1 |
| Aviatrix Spoke Gateway | Spoke gateways for workloads | 2 |
| EKS Cluster | Kubernetes cluster for app workloads | 1 |
| EC2 Instance | Test instances for connectivity validation | 2 |

**Estimated Cost**: ~$X/hour when running (see cost breakdown below)
```

### 5. Deployment Instructions

Step-by-step instructions:

```markdown
## Deployment

### Step 1: Clone and Navigate

\`\`\`bash
git clone https://github.com/aviatrix/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/<blueprint-name>
\`\`\`

### Step 2: Configure Variables

\`\`\`bash
cp terraform.tfvars.example terraform.tfvars
\`\`\`

Edit `terraform.tfvars` with your values:
- `controller_ip`: Your Aviatrix Control Plane (Controller) IP
- ...

### Step 3: Deploy

\`\`\`bash
terraform init
terraform plan
terraform apply
\`\`\`

Deployment takes approximately X minutes.
```

### 6. Variables Reference

Document all input variables:

```markdown
## Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| controller_ip | Aviatrix Control Plane (Controller) IP address | string | - | yes |
| controller_username | Controller admin username | string | "admin" | no |
| aws_region | AWS region for deployment | string | "us-east-1" | no |
```

### 7. Outputs Reference

Document all outputs:

```markdown
## Outputs

| Output | Description |
|--------|-------------|
| transit_gateway_id | ID of the Aviatrix Transit Gateway |
| spoke_vpc_ids | List of spoke VPC IDs |
| test_instance_ips | Public IPs of test instances |
```

### 8. Test Scenarios / Demo Walkthrough

Provide specific scenarios to validate the deployment:

```markdown
## Test Scenarios

### Scenario 1: East-West Connectivity

Verify connectivity between spoke VPCs:

\`\`\`bash
# SSH to test instance in Spoke 1
ssh -i key.pem ec2-user@<spoke1-instance-ip>

# Ping test instance in Spoke 2
ping <spoke2-private-ip>
\`\`\`

Expected result: Ping succeeds, traffic flows through Transit Gateway.

### Scenario 2: Firewall Inspection

Verify traffic is inspected by DCF:

1. Open CoPilot > Security > Distributed Cloud Firewall
2. Navigate to Monitor
3. Generate traffic between spokes
4. Verify traffic appears in logs
```

### 9. Cleanup / Destroy

Instructions for complete cleanup:

```markdown
## Cleanup

### Standard Destroy

\`\`\`bash
terraform destroy
\`\`\`

### Manual Cleanup (if destroy fails)

If Terraform destroy fails, manually delete:

1. Any Kubernetes LoadBalancer services (creates AWS ELBs)
2. ...

### Verify Cleanup

Confirm no resources remain:

\`\`\`bash
aws ec2 describe-vpcs --filters "Name=tag:Blueprint,Values=<blueprint-name>"
\`\`\`
```

### 10. Troubleshooting

Common issues and solutions:

```markdown
## Troubleshooting

### Gateway creation fails

**Symptom**: Aviatrix gateway times out during creation

**Solution**:
1. Verify AWS account is onboarded in the Control Plane
2. Check security group allows Controller communication
3. Verify sufficient EIP quota

### EKS nodes not joining

**Symptom**: EKS nodes remain in "NotReady" state

**Solution**:
1. Check node IAM role permissions
2. Verify VPC CNI configuration
3. Review node security group rules
```

### 11. Tested Versions

Document the versions this blueprint is currently tested against:

```markdown
## Tested With

This blueprint is currently tested with:

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 8.0.x |
| Aviatrix Terraform Provider | 3.2.0 |
| Terraform | 1.9.x |
| AWS Provider | 5.80.x |

> **Note**: The blueprint may work with other versions, but these are the versions used for validation.
```

### 12. Changelog (Optional but Recommended)

Include a `CHANGELOG.md` file to track significant changes:

```markdown
# Changelog

## 2025-01-15

- Added support for multiple availability zones
- Updated to Aviatrix provider 3.2.0

## 2024-12-01

- Initial release
- Tested with Controller 8.0.1
```

## Required Files

Every blueprint directory must contain:

```
blueprints/example-blueprint/
├── README.md                 # Documentation (all sections above)
├── main.tf                   # Primary Terraform configuration
├── variables.tf              # Input variable definitions
├── outputs.tf                # Output definitions
├── versions.tf               # Required providers and versions
├── terraform.tfvars.example  # Example variable values
├── architecture.png          # Architecture diagram
└── CHANGELOG.md              # Version history (optional but recommended)
```

### versions.tf Template

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = ">= 3.1.0"
    }
    # Add other providers as needed
  }
}
```

### terraform.tfvars.example Template

```hcl
# Aviatrix Control Plane Configuration
controller_ip       = "1.2.3.4"
controller_username = "admin"
controller_password = "CHANGE_ME"

# Cloud Provider Configuration
aws_region = "us-east-1"

# Blueprint-Specific Variables
name_prefix = "aws-eks-multicluster"
```

## Quality Checklist

Before submitting a blueprint:

- [ ] All required README sections present
- [ ] Architecture diagram is clear and accurate
- [ ] All variables documented with descriptions
- [ ] terraform.tfvars.example includes all required variables
- [ ] `terraform fmt` passes
- [ ] `terraform validate` passes
- [ ] Full deploy/destroy cycle tested
- [ ] Test scenarios verified
- [ ] Troubleshooting section covers common issues
- [ ] Version compatibility documented
