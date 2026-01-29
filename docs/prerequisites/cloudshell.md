# Cloud Shell Guide

> **Note**: This guide is a placeholder for future content. Cloud Shell provides browser-based command-line access with pre-installed tools.

## Overview

Cloud shells are browser-based terminal environments provided by cloud vendors. They come pre-configured with common tools, making them useful when you can't install tools locally.

## Available Cloud Shells

### AWS CloudShell

- **URL**: Available from AWS Console (top navigation bar)
- **Pre-installed**: AWS CLI, Python, Node.js, git
- **Not included**: Terraform (must be installed manually)
- **Storage**: 1 GB persistent storage in home directory
- **Limitations**: Only works with AWS services

### Azure Cloud Shell

- **URL**: [shell.azure.com](https://shell.azure.com) or Azure Portal
- **Pre-installed**: Azure CLI, Terraform, kubectl, Python, git
- **Storage**: 5 GB persistent Azure Files storage
- **Modes**: Bash or PowerShell

### Google Cloud Shell

- **URL**: [shell.cloud.google.com](https://shell.cloud.google.com) or GCP Console
- **Pre-installed**: gcloud CLI, Terraform, kubectl, Python, git
- **Storage**: 5 GB persistent home directory
- **Features**: Web preview, code editor

## Using Cloud Shell with Blueprints

### Basic Workflow

1. Open Cloud Shell for your target provider
2. Clone the blueprints repository
3. Navigate to your chosen blueprint
4. Configure variables and deploy

### Considerations

- **Multi-cloud**: Cloud shells are typically limited to their own provider
- **Session timeout**: Shells may disconnect after idle period
- **Tool versions**: Pre-installed tools may not match required versions
- **Terraform state**: Stored in Cloud Shell storage (ephemeral for some providers)

## Detailed Setup Guides

*Coming soon: Detailed guides for using each cloud shell with Aviatrix Blueprints.*

## Resources

- [AWS CloudShell Documentation](https://docs.aws.amazon.com/cloudshell/)
- [Azure Cloud Shell Documentation](https://docs.microsoft.com/en-us/azure/cloud-shell/)
- [Google Cloud Shell Documentation](https://cloud.google.com/shell/docs)
