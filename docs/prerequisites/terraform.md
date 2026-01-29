# Terraform Installation Guide

Terraform is required for deploying all Aviatrix Blueprints. This guide covers installation on macOS, Windows, and Linux.

## Version Requirements

- **Minimum version**: 1.5.0
- **Recommended**: Latest stable version

Check blueprint README files for specific version requirements.

## Installation

### macOS

#### Using Homebrew (Recommended)

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Terraform
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify installation
terraform version
```

#### Manual Installation

```bash
# Download (replace VERSION with desired version)
curl -LO https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_darwin_arm64.zip

# For Intel Macs, use darwin_amd64 instead
# curl -LO https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_darwin_amd64.zip

# Extract
unzip terraform_*.zip

# Move to PATH
sudo mv terraform /usr/local/bin/

# Verify
terraform version
```

### Windows

#### Using Chocolatey (Recommended)

```powershell
# Install Chocolatey if not already installed (run as Administrator)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install Terraform
choco install terraform

# Verify installation
terraform version
```

#### Using winget

```powershell
winget install Hashicorp.Terraform

# Verify installation
terraform version
```

#### Manual Installation

1. Download from [terraform.io/downloads](https://www.terraform.io/downloads)
2. Extract the ZIP file
3. Move `terraform.exe` to a directory in your PATH
4. Or add the extraction directory to your PATH:
   ```powershell
   # Add to PATH (PowerShell, run as Administrator)
   [Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\terraform", "Machine")
   ```

### Linux

#### Ubuntu/Debian

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install
sudo apt update && sudo apt install terraform

# Verify
terraform version
```

#### RHEL/CentOS/Fedora

```bash
# Add repository
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

# Install
sudo yum -y install terraform

# Verify
terraform version
```

#### Amazon Linux 2

```bash
# Add repository
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo

# Install
sudo yum -y install terraform

# Verify
terraform version
```

## Verification

After installation, verify Terraform is working:

```bash
# Check version
terraform version

# Expected output:
# Terraform v1.7.0
# on darwin_arm64

# Check help
terraform -help
```

## Managing Multiple Versions

For managing multiple Terraform versions, consider using a version manager:

### tfenv (macOS/Linux)

```bash
# Install tfenv
brew install tfenv

# List available versions
tfenv list-remote

# Install specific version
tfenv install 1.5.7
tfenv install 1.7.0

# Switch versions
tfenv use 1.7.0

# Set default version
tfenv use 1.7.0
echo "1.7.0" > ~/.tfenv/version
```

### tfswitch (macOS/Linux)

```bash
# Install tfswitch
brew install warrensbox/tap/tfswitch

# Run in project directory to auto-select version
tfswitch

# Or specify version
tfswitch 1.7.0
```

## Configuration

### Enable Tab Completion (Optional)

#### Bash

```bash
terraform -install-autocomplete
# Restart shell or source ~/.bashrc
```

#### Zsh

```bash
terraform -install-autocomplete
# Restart shell or source ~/.zshrc
```

### Provider Plugin Cache (Recommended)

Speed up `terraform init` by caching providers:

```bash
# Create cache directory
mkdir -p ~/.terraform.d/plugin-cache

# Add to shell profile (~/.bashrc, ~/.zshrc, etc.)
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
```

## Common Commands

| Command | Description |
|---------|-------------|
| `terraform init` | Initialize working directory |
| `terraform plan` | Preview changes |
| `terraform apply` | Apply changes |
| `terraform destroy` | Destroy resources |
| `terraform fmt` | Format code |
| `terraform validate` | Validate configuration |
| `terraform output` | Show outputs |
| `terraform state list` | List resources in state |

## Troubleshooting

### Command not found

Ensure Terraform is in your PATH:

```bash
# Check PATH
echo $PATH

# Find terraform location
which terraform

# On Windows
where terraform
```

### Provider download fails

Check network connectivity and proxy settings:

```bash
# Set proxy if needed
export HTTP_PROXY=http://proxy:port
export HTTPS_PROXY=http://proxy:port
```

### Permission denied

On Linux/macOS, ensure the binary is executable:

```bash
chmod +x /usr/local/bin/terraform
```

### Version conflicts

If a blueprint requires a specific version:

```bash
# Check required version in versions.tf
cat versions.tf

# Use tfenv or tfswitch to install that version
tfenv install 1.5.7
tfenv use 1.5.7
```

## Resources

- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Terraform CLI Documentation](https://developer.hashicorp.com/terraform/cli)
- [Aviatrix Terraform Provider](https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs)
