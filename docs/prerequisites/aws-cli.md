# AWS CLI Installation Guide

The AWS CLI is required for deploying blueprints to AWS. This guide covers installation and configuration on macOS and Windows.

## Version Requirements

- **Minimum version**: AWS CLI v2
- **Recommended**: Latest stable version

## Installation

### macOS

#### Using Homebrew (Recommended)

```bash
# Install AWS CLI
brew install awscli

# Verify installation
aws --version
```

#### Using Official Installer

```bash
# Download the installer
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

# Install (requires admin password)
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify installation
aws --version

# Clean up
rm AWSCLIV2.pkg
```

### Windows

#### Using MSI Installer (Recommended)

1. Download the installer: [AWS CLI MSI Installer](https://awscli.amazonaws.com/AWSCLIV2.msi)
2. Run the downloaded MSI installer
3. Follow the installation wizard
4. Open a new Command Prompt or PowerShell
5. Verify: `aws --version`

#### Using Chocolatey

```powershell
# Install AWS CLI
choco install awscli

# Verify installation
aws --version
```

#### Using winget

```powershell
# Install AWS CLI
winget install Amazon.AWSCLI

# Verify installation
aws --version
```

### Linux

#### Ubuntu/Debian

```bash
# Download installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Install unzip if needed
sudo apt install unzip

# Extract and install
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version

# Clean up
rm -rf aws awscliv2.zip
```

#### Amazon Linux 2 / RHEL / CentOS

```bash
# Download installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Install unzip if needed
sudo yum install unzip

# Extract and install
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version
```

## Configuration

### Quick Configuration

The fastest way to configure credentials:

```bash
aws configure
```

You'll be prompted for:
- **AWS Access Key ID**: Your access key
- **AWS Secret Access Key**: Your secret key
- **Default region name**: e.g., `us-east-1`
- **Default output format**: `json` (recommended)

### Configuration Files

AWS CLI stores configuration in two files:

**~/.aws/credentials** (Linux/macOS) or **%USERPROFILE%\.aws\credentials** (Windows)
```ini
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**~/.aws/config**
```ini
[default]
region = us-east-1
output = json
```

### Multiple Profiles

Configure multiple AWS accounts using profiles:

```bash
# Configure a named profile
aws configure --profile production
```

**~/.aws/credentials**
```ini
[default]
aws_access_key_id = AKIA...DEFAULT
aws_secret_access_key = ...

[production]
aws_access_key_id = AKIA...PROD
aws_secret_access_key = ...

[development]
aws_access_key_id = AKIA...DEV
aws_secret_access_key = ...
```

Use profiles:
```bash
# Set profile for current session
export AWS_PROFILE=production

# Or specify per-command
aws s3 ls --profile production
```

### Using IAM Identity Center (SSO)

For organizations using AWS IAM Identity Center:

```bash
# Configure SSO
aws configure sso

# Login
aws sso login --profile my-sso-profile

# Use the profile
export AWS_PROFILE=my-sso-profile
```

### Using IAM Roles (EC2/ECS)

When running on AWS infrastructure with an IAM role attached, no configuration is needed. The CLI automatically uses the instance/task role.

## Verification

Verify your configuration works:

```bash
# Check CLI version
aws --version

# Verify credentials
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/myuser"
}
```

## Terraform Integration

Terraform uses AWS credentials from:
1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
2. AWS credentials file (`~/.aws/credentials`)
3. Instance profile (when running on EC2)

### Using Profiles with Terraform

```hcl
provider "aws" {
  region  = "us-east-1"
  profile = "production"  # Optional: use specific profile
}
```

Or set environment variable:
```bash
export AWS_PROFILE=production
terraform apply
```

## Required Permissions

For Aviatrix blueprints, you typically need permissions to create:
- VPCs, Subnets, Route Tables
- EC2 instances, Security Groups
- IAM roles (for EKS, Aviatrix gateways)
- EKS clusters (for Kubernetes blueprints)
- Various other services depending on the blueprint

See each blueprint's README for specific IAM requirements.

## Troubleshooting

### Credentials not found

```
Unable to locate credentials
```

Solutions:
1. Run `aws configure` to set up credentials
2. Verify credentials file exists: `cat ~/.aws/credentials`
3. Check environment variables: `env | grep AWS`

### Invalid credentials

```
An error occurred (InvalidClientTokenId)
```

Solutions:
1. Verify access key is correct
2. Check if key has been deactivated in IAM console
3. Regenerate credentials if needed

### Region not specified

```
You must specify a region
```

Solutions:
1. Run `aws configure` and set default region
2. Set environment variable: `export AWS_DEFAULT_REGION=us-east-1`
3. Specify in command: `aws ec2 describe-instances --region us-east-1`

### SSL certificate errors

```
SSL validation failed
```

Solutions:
1. Update CA certificates on your system
2. Check for proxy interference
3. As last resort (not recommended): `aws --no-verify-ssl ...`

## Resources

- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/latest/userguide/)
- [AWS CLI Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
