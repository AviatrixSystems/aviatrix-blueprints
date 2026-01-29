# Aviatrix Control Plane Prerequisites

The Aviatrix Control Plane is required for all blueprints. It consists of:

- **Controller** - The management plane for Terraform and API operations
- **CoPilot** - The GUI for visualization, monitoring, and day-2 operations

Alternatively, you can use **Aviatrix Cloud Fabric**, a fully managed control plane subscription.

## Requirements

### Control Plane Access

You need:
- **Controller IP or hostname**: The public IP or DNS name of your Controller
- **Admin credentials**: Username and password with admin privileges
- **Network access**: Your workstation must be able to reach the Controller on port 443

### Control Plane Version

Blueprints specify their required Control Plane version. Check the blueprint's README:

```markdown
## Prerequisites
- Aviatrix Control Plane v8.1 or later
```

### Cloud Account Onboarding

Before deploying blueprints, your cloud accounts must be onboarded to the Controller:

1. **AWS**: IAM roles configured via CloudFormation or manually
2. **Azure**: Service principal or managed identity configured
3. **GCP**: Service account configured

## Deploying a Control Plane

If you don't have a Control Plane, follow the official Aviatrix documentation:

### AWS Deployment

Follow the [AWS Getting Started Guide](https://docs.aviatrix.com/documentation/latest/getting-started/getting-started-guide-aws.html?expand=true) which covers:

- Launching the Controller from AWS Marketplace
- Initial Controller setup and licensing
- Onboarding your AWS account
- Deploying CoPilot

### Azure Deployment

Follow the [Azure Getting Started Guide](https://docs.aviatrix.com/documentation/latest/getting-started/getting-started-guide-azure.html?expand=true) which covers:

- Launching the Controller from Azure Marketplace
- Initial Controller setup and licensing
- Onboarding your Azure subscription
- Deploying CoPilot

### GCP Deployment

See the [Aviatrix Documentation](https://docs.aviatrix.com) for GCP-specific deployment instructions.

## Verifying Control Plane Access

### From Your Browser

1. Navigate to `https://<controller-ip>`
2. Log in with your credentials
3. Verify you can access the dashboard
4. Navigate to CoPilot and verify access

### From Terraform

Create a test file to verify connectivity:

```hcl
# test-controller.tf
terraform {
  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = ">= 3.1.0"
    }
  }
}

provider "aviatrix" {
  controller_ip = var.controller_ip
  username      = var.controller_username
  password      = var.controller_password
}

variable "controller_ip" {
  description = "Controller IP address"
  type        = string
}

variable "controller_username" {
  description = "Controller username"
  type        = string
  default     = "admin"
}

variable "controller_password" {
  description = "Controller password"
  type        = string
  sensitive   = true
}

data "aviatrix_account" "test" {
  account_name = "your-account-name"
}

output "account_info" {
  value = data.aviatrix_account.test
}
```

Run:
```bash
terraform init
terraform plan -var="controller_ip=1.2.3.4" -var="controller_password=xxx"
```

If successful, you'll see the account information.

## Troubleshooting

### Cannot reach Controller

1. Verify the Controller is running (check cloud provider console)
2. Check security groups allow inbound HTTPS (port 443)
3. Verify your IP is allowed (if IP allowlisting is enabled)
4. Check VPN connectivity if Controller is in private network

### Authentication fails

1. Verify username and password
2. Check for account lockout
3. Verify user has admin privileges
4. Check Controller license status

### Cloud account connection fails

1. Verify credentials are correct
2. Check IAM permissions (AWS) or role assignments (Azure/GCP)
3. Review Controller logs for detailed errors
4. Verify network connectivity to cloud provider APIs

## Resources

- [Aviatrix Documentation](https://docs.aviatrix.com)
- [AWS Getting Started Guide](https://docs.aviatrix.com/documentation/latest/getting-started/getting-started-guide-aws.html?expand=true)
- [Azure Getting Started Guide](https://docs.aviatrix.com/documentation/latest/getting-started/getting-started-guide-azure.html?expand=true)
- [Aviatrix Support](https://support.aviatrix.com)
