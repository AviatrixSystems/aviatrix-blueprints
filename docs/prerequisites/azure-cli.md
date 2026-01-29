# Azure CLI Installation Guide

The Azure CLI is required for deploying blueprints to Microsoft Azure. This guide covers installation and configuration on macOS and Windows.

## Version Requirements

- **Minimum version**: 2.50.0
- **Recommended**: Latest stable version

## Installation

### macOS

#### Using Homebrew (Recommended)

```bash
# Install Azure CLI
brew install azure-cli

# Verify installation
az --version
```

#### Using Official Script

```bash
# Install using the official script
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Verify installation
az --version
```

### Windows

#### Using MSI Installer (Recommended)

1. Download the installer: [Azure CLI MSI](https://aka.ms/installazurecliwindows)
2. Run the downloaded MSI installer
3. Follow the installation wizard
4. Open a new Command Prompt or PowerShell
5. Verify: `az --version`

#### Using Chocolatey

```powershell
# Install Azure CLI
choco install azure-cli

# Verify installation
az --version
```

#### Using winget

```powershell
# Install Azure CLI
winget install Microsoft.AzureCLI

# Verify installation
az --version
```

#### Using PowerShell

```powershell
# Install Azure CLI
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
Remove-Item .\AzureCLI.msi

# Restart PowerShell, then verify
az --version
```

### Linux

#### Ubuntu/Debian

```bash
# Get packages needed for install
sudo apt-get update
sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg

# Download and install Microsoft signing key
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

# Add Azure CLI repository
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list

# Install
sudo apt-get update
sudo apt-get install azure-cli

# Verify
az --version
```

#### RHEL/CentOS/Fedora

```bash
# Import Microsoft repository key
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

# Add repository
sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm

# Install
sudo dnf install azure-cli

# Verify
az --version
```

## Authentication

### Interactive Login (Recommended for Development)

```bash
# Login interactively - opens browser
az login

# Verify login
az account show
```

### Service Principal (Recommended for Automation)

Create a service principal for Terraform and automated deployments:

```bash
# Create service principal with Contributor role
az ad sp create-for-rbac \
  --name "aviatrix-blueprints-sp" \
  --role Contributor \
  --scopes /subscriptions/<subscription-id>
```

Output:
```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "displayName": "aviatrix-blueprints-sp",
  "password": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

Save these values for Terraform configuration.

### Login with Service Principal

```bash
az login --service-principal \
  --username <appId> \
  --password <password> \
  --tenant <tenant>
```

## Configuration

### Set Default Subscription

```bash
# List subscriptions
az account list --output table

# Set default subscription
az account set --subscription "<subscription-name-or-id>"

# Verify
az account show
```

### Set Default Location

```bash
# Configure default location
az config set defaults.location=eastus

# Or use environment variable
export AZURE_DEFAULTS_LOCATION=eastus
```

## Verification

```bash
# Check CLI version
az --version

# Verify authentication
az account show

# Test resource access
az group list --output table
```

## Terraform Integration

### Using Azure CLI Authentication

Terraform can use your Azure CLI credentials directly:

```hcl
provider "azurerm" {
  features {}
  # Uses Azure CLI credentials automatically
}
```

### Using Service Principal

For automation, configure the service principal:

```hcl
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}
```

Or use environment variables:
```bash
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export ARM_CLIENT_ID="<appId>"
export ARM_CLIENT_SECRET="<password>"
export ARM_TENANT_ID="<tenant>"
```

## Required Permissions

For Aviatrix blueprints, the service principal typically needs:

- **Contributor** role on the subscription (or specific resource groups)
- Additional permissions may be needed for:
  - Creating service principals (if blueprint creates them)
  - Managing Azure AD resources
  - Network Contributor for VNet peering

See each blueprint's README for specific permission requirements.

## Troubleshooting

### Login fails in browser

```bash
# Use device code flow instead
az login --use-device-code
```

### Subscription not found

```bash
# List all accessible subscriptions
az account list --all --output table

# Check if logged into correct tenant
az account show
```

### Permission denied

1. Verify service principal has required role
2. Check role assignment scope (subscription vs resource group)
3. Wait a few minutes - role assignments can take time to propagate

### Token expired

```bash
# Clear cached tokens and re-login
az account clear
az login
```

### SSL/TLS errors

```bash
# Update CA certificates
# macOS
brew install ca-certificates

# Ubuntu
sudo apt-get update && sudo apt-get install ca-certificates

# Or disable verification (not recommended)
az config set core.disable_confirm_prompt=yes
```

## Managing Multiple Tenants

```bash
# Login to specific tenant
az login --tenant <tenant-id>

# List all tenants
az account tenant list

# Switch between subscriptions in different tenants
az account set --subscription <subscription-id>
```

## Useful Commands

| Command | Description |
|---------|-------------|
| `az login` | Interactive login |
| `az logout` | Log out |
| `az account list` | List subscriptions |
| `az account show` | Show current subscription |
| `az account set -s <sub>` | Set subscription |
| `az group list` | List resource groups |
| `az vm list` | List virtual machines |
| `az network vnet list` | List virtual networks |

## Resources

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/reference-index)
- [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
