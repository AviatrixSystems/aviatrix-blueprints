# Prerequisites Overview

Before deploying Aviatrix Blueprints, you'll need to set up several tools and ensure you have the necessary access.

## Aviatrix Control Plane

Blueprints require access to an **Aviatrix Control Plane**, which consists of:

- **Controller** - The management plane for Terraform and API operations
- **CoPilot** - The GUI for visualization, monitoring, and day-2 operations

Alternatively, you can use an **Aviatrix Cloud Fabric** subscription, which provides a fully managed control plane.

See the [Aviatrix Control Plane Setup Guide](aviatrix-controller.md) for details.

## Required for All Blueprints

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| [Aviatrix Control Plane](aviatrix-controller.md) | 7.1+ | Manages Aviatrix infrastructure |
| [Terraform](terraform.md) | 1.5+ | Infrastructure as Code deployment |

## Cloud Provider CLIs

Install the CLI for your target cloud(s):

| Cloud | Tool | Guide |
|-------|------|-------|
| AWS | AWS CLI | [Installation Guide](aws-cli.md) |
| Azure | Azure CLI | [Installation Guide](azure-cli.md) |
| GCP | gcloud CLI | [Installation Guide](gcloud-cli.md) |

## Additional Tools

Some blueprints require additional tools:

| Tool | Required For | Guide |
|------|--------------|-------|
| kubectl | Kubernetes blueprints (EKS, AKS, GKE) | [Installation Guide](kubectl.md) |
| helm | Some Kubernetes deployments | See blueprint README |

## Cloud Shell Option

If you prefer not to install tools locally, you can use cloud-native shells:

| Provider | Shell | Notes |
|----------|-------|-------|
| AWS | CloudShell | Includes AWS CLI, limited to AWS |
| Azure | Cloud Shell | Includes Azure CLI and Terraform |
| GCP | Cloud Shell | Includes gcloud CLI and Terraform |

See [Cloud Shell Guide](cloudshell.md) for setup instructions.

## Verification

After installation, verify your setup:

```bash
# Terraform
terraform version
# Expected: Terraform v1.5.x or higher

# AWS CLI
aws --version
aws sts get-caller-identity
# Expected: Shows your AWS account info

# Azure CLI (if using Azure)
az --version
az account show
# Expected: Shows your Azure subscription

# GCP CLI (if using GCP)
gcloud --version
gcloud auth list
# Expected: Shows your GCP account

# kubectl (if needed)
kubectl version --client
# Expected: Shows client version
```

## Quick Install Summary

### macOS (with Homebrew)

```bash
# Core tools
brew install terraform

# Cloud CLIs
brew install awscli
brew install azure-cli
brew install google-cloud-sdk

# Kubernetes tools
brew install kubectl
```

### Windows (with Chocolatey)

```powershell
# Core tools
choco install terraform

# Cloud CLIs
choco install awscli
choco install azure-cli
choco install gcloudsdk

# Kubernetes tools
choco install kubernetes-cli
```

### Linux

See individual guides for distribution-specific instructions.

## Next Steps

1. Install required tools using the guides above
2. Configure cloud provider authentication
3. Verify your Aviatrix Control Plane access (Controller and CoPilot)
4. Choose a [blueprint](../../README.md#blueprint-catalog) to deploy
5. Follow the [Getting Started Guide](../getting-started.md)
