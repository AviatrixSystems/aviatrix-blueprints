# Getting Started with Aviatrix Blueprints

This guide walks you through deploying your first Aviatrix Blueprint.

## Overview

Aviatrix Blueprints are complete, self-contained Terraform configurations that deploy working lab environments. Each blueprint includes:

- All necessary Terraform code
- Detailed documentation
- Test scenarios for validation
- Cleanup instructions

## Prerequisites

Before you begin, ensure you have:

1. **Aviatrix Control Plane** - A deployed and accessible Aviatrix environment
   - See [Aviatrix Control Plane Prerequisites](prerequisites/aviatrix-controller.md)
   - This includes both **Controller** (for Terraform/API) and **CoPilot** (for GUI), or an **Aviatrix Cloud Fabric** subscription

2. **Terraform** - Version 1.5 or later
   - See [Terraform Installation Guide](prerequisites/terraform.md)

3. **Cloud Provider CLI** - For your target cloud(s):
   - [AWS CLI](prerequisites/aws-cli.md)
   - [Azure CLI](prerequisites/azure-cli.md)
   - [Google Cloud CLI](prerequisites/gcloud-cli.md)

4. **Additional Tools** - As required by specific blueprints:
   - [kubectl](prerequisites/kubectl.md) for Kubernetes-based blueprints

## Step-by-Step Deployment

### Step 1: Clone the Repository

```bash
git clone https://github.com/aviatrix/aviatrix-blueprints.git
cd aviatrix-blueprints
```

### Step 2: Choose a Blueprint

Browse the [Blueprint Catalog](../README.md#blueprint-catalog) and select one that matches your learning goals.

```bash
# Navigate to your chosen blueprint
cd blueprints/aws-eks-multicluster
```

### Step 3: Review Requirements

Read the blueprint's README carefully:

```bash
cat README.md
```

Pay attention to:
- **Prerequisites**: What tools and access you need
- **Resources Created**: What will be deployed (and the cost implications)
- **Time Estimate**: How long deployment typically takes

### Step 4: Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
# Use your preferred editor
vi terraform.tfvars
```

Common variables you'll need to set:

```hcl
# Aviatrix Control Plane (Controller)
controller_ip       = "1.2.3.4"
controller_username = "admin"
controller_password = "your-password"

# Cloud Provider
aws_region = "us-east-1"
```

### Step 5: Initialize Terraform

```bash
terraform init
```

This downloads required providers and modules.

### Step 6: Review the Plan

```bash
terraform plan
```

Review the planned changes:
- Confirm the resources match what you expect
- Check for any errors or warnings
- Note the number of resources to be created

### Step 7: Deploy

```bash
terraform apply
```

Type `yes` when prompted to confirm.

Deployment times vary by blueprint. Complex blueprints may take 15-30 minutes.

### Step 8: Explore and Test

Each blueprint includes test scenarios. Follow the instructions in the blueprint's README to:

1. Verify connectivity between components
2. Test Aviatrix features (firewalls, segmentation, etc.)
3. Explore the CoPilot visualizations

### Step 9: Clean Up

When you're done:

```bash
terraform destroy
```

Type `yes` when prompted to confirm.

**Important**: Always destroy resources when done to avoid ongoing cloud charges.

## Tips for Success

### Cost Management

- Blueprints create real cloud resources that incur charges
- Always run `terraform destroy` when finished
- Consider using cloud provider cost alerts
- Some blueprints note estimated costs in their README

### Troubleshooting

Common issues and solutions:

**Terraform init fails**
```bash
# Clear cache and retry
rm -rf .terraform .terraform.lock.hcl
terraform init
```

**Authentication errors**
- Verify your cloud CLI is configured: `aws sts get-caller-identity`
- Check control plane credentials in terraform.tfvars
- Ensure the Controller is accessible from your network

**Resource creation timeout**
- Some resources (like EKS clusters) take time
- Check the cloud provider console for status
- Review Controller/CoPilot logs for Aviatrix-related issues

**Destroy fails with dependencies**
- Some resources may need manual cleanup
- Check the blueprint's troubleshooting section
- Common: Load balancers created by Kubernetes services

### State Files

Blueprints use local state (`terraform.tfstate`). This file:

- Contains sensitive information - don't commit to git
- Is required for destroy - don't delete before cleanup
- Can be recreated if needed (with caveats)

### Multiple Deployments

To deploy the same blueprint multiple times:

```bash
# Use workspaces
terraform workspace new dev
terraform workspace new prod

# Or use separate directories
cp -r blueprints/aws-eks-multicluster blueprints/aws-eks-multicluster-demo2
```

## Next Steps

- [Blueprint Standards](blueprint-standards.md) - Understand what's in each blueprint
- [Contributing](../CONTRIBUTING.md) - Create your own blueprints
- [Aviatrix Documentation](https://docs.aviatrix.com) - Learn more about Aviatrix features
