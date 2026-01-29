# Google Cloud CLI Installation Guide

The Google Cloud CLI (gcloud) is required for deploying blueprints to Google Cloud Platform. This guide covers installation and configuration on macOS and Windows.

## Version Requirements

- **Minimum version**: 400.0.0
- **Recommended**: Latest stable version

## Installation

### macOS

#### Using Homebrew (Recommended)

```bash
# Install Google Cloud SDK
brew install google-cloud-sdk

# Verify installation
gcloud --version
```

#### Using Official Installer

```bash
# Download the installer
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-arm.tar.gz

# For Intel Macs:
# curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-x86_64.tar.gz

# Extract
tar -xf google-cloud-cli-darwin-*.tar.gz

# Install
./google-cloud-sdk/install.sh

# Initialize (restart terminal first)
gcloud init

# Verify
gcloud --version
```

### Windows

#### Using Official Installer (Recommended)

1. Download: [Google Cloud CLI Installer](https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe)
2. Run the installer
3. Follow the installation wizard
4. Check "Run gcloud init" at the end
5. Complete the initialization in the terminal

#### Using Chocolatey

```powershell
# Install Google Cloud SDK
choco install gcloudsdk

# Initialize
gcloud init

# Verify
gcloud --version
```

### Linux

#### Ubuntu/Debian

```bash
# Add Cloud SDK distribution URI as package source
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# Import Google Cloud public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

# Install
sudo apt-get update && sudo apt-get install google-cloud-cli

# Initialize
gcloud init

# Verify
gcloud --version
```

#### RHEL/CentOS/Fedora

```bash
# Add repository
sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM

# Install
sudo dnf install google-cloud-cli

# Initialize
gcloud init

# Verify
gcloud --version
```

## Authentication

### Interactive Login (Development)

```bash
# Initialize and authenticate
gcloud init

# Or just authenticate
gcloud auth login
```

This opens a browser for Google account authentication.

### Application Default Credentials (Terraform)

For local development with Terraform:

```bash
# Set up application default credentials
gcloud auth application-default login
```

### Service Account (Automation)

For automated deployments and CI/CD:

1. **Create a service account** in GCP Console:
   - Go to IAM & Admin > Service Accounts
   - Create Service Account
   - Grant required roles (see permissions section)
   - Create and download JSON key

2. **Activate service account**:
```bash
# Activate with key file
gcloud auth activate-service-account --key-file=path/to/key.json

# Or set environment variable
export GOOGLE_APPLICATION_CREDENTIALS="path/to/key.json"
```

## Configuration

### Initialize gcloud

```bash
gcloud init
```

This walks you through:
1. Logging in
2. Selecting a project
3. Setting default region/zone

### Set Default Project

```bash
# List projects
gcloud projects list

# Set default project
gcloud config set project PROJECT_ID

# Verify
gcloud config get project
```

### Set Default Region/Zone

```bash
# Set default region
gcloud config set compute/region us-central1

# Set default zone
gcloud config set compute/zone us-central1-a

# View all configuration
gcloud config list
```

### Manage Configurations

Use configurations to manage multiple projects/accounts:

```bash
# Create a new configuration
gcloud config configurations create my-project

# Activate configuration
gcloud config configurations activate my-project

# List configurations
gcloud config configurations list
```

## Verification

```bash
# Check version
gcloud --version

# Verify authentication
gcloud auth list

# Check current project
gcloud config get project

# Test access
gcloud compute instances list
```

## Terraform Integration

### Using Application Default Credentials

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
  # Uses application default credentials automatically
}
```

### Using Service Account Key

```hcl
provider "google" {
  credentials = file("path/to/service-account-key.json")
  project     = var.project_id
  region      = var.region
}
```

### Using Environment Variables

```bash
export GOOGLE_APPLICATION_CREDENTIALS="path/to/key.json"
export GOOGLE_PROJECT="my-project-id"
export GOOGLE_REGION="us-central1"
```

```hcl
provider "google" {
  # Uses environment variables
}
```

## Required Permissions

For Aviatrix blueprints, the service account typically needs:

- **Compute Admin** (`roles/compute.admin`) - VPCs, instances, firewalls
- **Service Account User** (`roles/iam.serviceAccountUser`) - For using service accounts
- **Kubernetes Engine Admin** (`roles/container.admin`) - For GKE blueprints

Create a custom role or use predefined roles:

```bash
# Grant roles to service account
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:SA_EMAIL" \
  --role="roles/compute.admin"
```

## Additional Components

Install additional components as needed:

```bash
# List available components
gcloud components list

# Install kubectl
gcloud components install kubectl

# Install GKE authentication plugin
gcloud components install gke-gcloud-auth-plugin

# Update all components
gcloud components update
```

## Troubleshooting

### Authentication errors

```bash
# Clear cached credentials
gcloud auth revoke --all

# Re-authenticate
gcloud auth login

# For application default credentials
gcloud auth application-default revoke
gcloud auth application-default login
```

### Project not set

```
ERROR: (gcloud) The project property must be set
```

```bash
# Set project
gcloud config set project YOUR_PROJECT_ID
```

### API not enabled

```
ERROR: API [compute.googleapis.com] not enabled
```

```bash
# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

### Quota exceeded

Check and request quota increases in the GCP Console:
- Go to IAM & Admin > Quotas
- Filter by the specific quota
- Request increase

### SSL certificate errors

```bash
# Update CA certificates
# macOS
brew install ca-certificates

# Ubuntu
sudo apt-get update && sudo apt-get install ca-certificates
```

## Useful Commands

| Command | Description |
|---------|-------------|
| `gcloud init` | Initialize configuration |
| `gcloud auth login` | Interactive login |
| `gcloud auth list` | List authenticated accounts |
| `gcloud projects list` | List accessible projects |
| `gcloud config list` | Show current configuration |
| `gcloud compute instances list` | List VMs |
| `gcloud compute networks list` | List VPCs |
| `gcloud container clusters list` | List GKE clusters |

## Resources

- [Google Cloud CLI Documentation](https://cloud.google.com/sdk/docs)
- [gcloud Command Reference](https://cloud.google.com/sdk/gcloud/reference)
- [Google Provider for Terraform](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
