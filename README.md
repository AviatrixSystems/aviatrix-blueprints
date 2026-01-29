# Aviatrix Blueprints

Production-ready Terraform lab environments for learning, demonstrating, and testing Aviatrix cloud networking solutions.

![Aviatrix Blueprints](aviatrix_blueprints_logo.png)

## What are Blueprints?

Blueprints are **complete, deployable lab environments** that demonstrate Aviatrix capabilities in real-world scenarios. Unlike reusable Terraform modules, blueprints are designed to be:

- **Self-contained**: Everything needed to deploy a working environment
- **Educational**: Clear documentation explaining what's being built and why
- **Demonstrable**: Built-in test scenarios for showcasing functionality
- **Ephemeral**: Designed for temporary use with easy cleanup

## Blueprint Tiers

| Tier | Description | Requirements |
|------|-------------|--------------|
| **Verified** | Validated by Aviatrix QA team, tested against specific controller versions | Full QA and SE review, version compatibility matrix |
| **Community** | Contributed by the community, functional but not officially validated | Validated by the Aviatrix SE and Professional Services |

## Blueprint Catalog

| Blueprint | Description | Cloud(s) | Tier | Status |
|-----------|-------------|----------|------|--------|
| [dcf-eks](blueprints/dcf-eks/) | Distributed Cloud Firewall with EKS | AWS | Community | 🚧 In Progress |

## Quick Start

### 1. Prerequisites

Before deploying any blueprint, ensure you have:

- An [Aviatrix Enterprise or Aviatrix Cloud Control Plane](docs/prerequisites/aviatrix-controller.md) deployed and accessible
- [Terraform](docs/prerequisites/terraform.md) installed (v1.5+)
- Cloud provider CLI configured for your target cloud:
  - [AWS CLI](docs/prerequisites/aws-cli.md)
  - [Azure CLI](docs/prerequisites/azure-cli.md)
  - [Google Cloud CLI](docs/prerequisites/gcloud-cli.md)
- Additional tools as required by specific blueprints (e.g., [kubectl](docs/prerequisites/kubectl.md))

See the [Prerequisites Overview](docs/prerequisites/README.md) for detailed setup instructions.

### 2. Deploy a Blueprint

```bash
# Clone the repository
git clone https://github.com/aviatrix/aviatrix-blueprints.git
cd aviatrix-blueprints

# Navigate to your chosen blueprint
cd blueprints/dcf-eks

# Review the README for specific requirements
cat README.md

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy
terraform init
terraform plan
terraform apply
```

### 3. Explore and Learn

Each blueprint includes:
- Architecture diagrams
- Step-by-step deployment instructions
- Test scenarios to validate functionality
- Demo walkthroughs for presentations

### 4. Clean Up

```bash
# Destroy all resources when done
terraform destroy
```

## Repository Structure

```
aviatrix-blueprints/
├── docs/                    # Documentation and guides
│   ├── prerequisites/       # Setup guides for required tools
│   ├── getting-started.md   # Quick start guide
│   └── blueprint-standards.md
├── modules/                 # Shared Terraform modules (future)
├── blueprints/              # Deployable lab environments
│   ├── _template/           # Template for new blueprints
│   └── dcf-eks/             # Individual blueprints...
└── .github/                 # CI/CD and templates
```

## Documentation

- [Getting Started Guide](docs/getting-started.md)
- [Blueprint Standards](docs/blueprint-standards.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Prerequisites](docs/prerequisites/README.md)

## Contributing

We welcome contributions! Whether you're fixing a bug, improving documentation, or adding a new blueprint, please see our [Contributing Guide](CONTRIBUTING.md).

### Adding a New Blueprint

1. Copy the [blueprint template](blueprints/_template/)
2. Follow the [Blueprint Standards](docs/blueprint-standards.md)
3. Submit a PR for review

## Support

- **Issues**: [GitHub Issues](https://github.com/aviatrix/aviatrix-blueprints/issues)
- **Discussions**: [GitHub Discussions](https://github.com/aviatrix/aviatrix-blueprints/discussions)
- **Aviatrix Documentation**: [docs.aviatrix.com](https://docs.aviatrix.com)

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
