# Contributing to Aviatrix Blueprints

Thank you for your interest in contributing to Aviatrix Blueprints! This document provides guidelines and standards for contributions.

## Code of Conduct

Please be respectful and constructive in all interactions. We're building a community resource for cloud networking professionals.

## Recommended Development Environment

We strongly recommend using **[Claude Code](https://claude.ai/code)** for blueprint development. Claude Code understands Terraform, Aviatrix patterns, and can help ensure your blueprints meet repository standards.

### Required MCP Servers

Configure Claude Code with the following MCP servers for the best development experience:

| MCP Server | Purpose | Configuration |
|------------|---------|---------------|
| **GitHub** | Access to Aviatrix Terraform provider docs, modules, and repository management | Point to [AviatrixSystems/terraform-provider-aviatrix](https://github.com/AviatrixSystems/terraform-provider-aviatrix) |
| **Terraform** | Registry lookups for provider/module versions and documentation | Default configuration |
| **Playwright** | Automated browser testing for validating deployments against a real Aviatrix Control Plane | Required for self-testing blueprints |
| **Serena** | LSP-based code intelligence for semantic understanding of Terraform configurations | Enables accurate refactoring and analysis |

### Why Use Claude Code?

- **Standards Compliance**: Claude Code reads the repository's `CLAUDE.md` and automatically follows blueprint standards
- **Self-Testing**: With Playwright MCP, Claude can deploy blueprints and verify they work against a real Aviatrix environment
- **Accurate Documentation**: Automatically generates comprehensive resource lists and prerequisites
- **Provider Awareness**: Direct access to Aviatrix Terraform provider documentation ensures correct resource usage

### Setting Up Claude Code

1. Install [Claude Code CLI](https://claude.ai/code)
2. Configure MCP servers in your global Claude Code settings (`~/.claude.json`):

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-token>"
      }
    },
    "terraform": {
      "command": "npx",
      "args": ["-y", "@anthropics/terraform-mcp-server"]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@anthropics/mcp-server-playwright"]
    },
    "serena": {
      "command": "npx",
      "args": ["-y", "serena-mcp-server"]
    }
  }
}
```

   See [.claude/mcp-servers.example.json](.claude/mcp-servers.example.json) for a copy-paste ready configuration.

3. Clone this repository and open it in Claude Code
4. Claude will automatically read `CLAUDE.md` for project-specific instructions

## Ways to Contribute

- **New Blueprints**: Add new lab environments demonstrating Aviatrix capabilities
- **Improvements**: Enhance existing blueprints with better documentation, additional scenarios, or bug fixes
- **Documentation**: Improve guides, fix typos, or add clarifications
- **Bug Reports**: Report issues you encounter when deploying blueprints
- **Feature Requests**: Suggest new blueprints or enhancements

## Contributing a New Blueprint

### 1. Start from the Template

```bash
# Copy the template
cp -r blueprints/_template blueprints/your-blueprint-name

# Follow naming conventions (see below)
```

### 2. Blueprint Requirements Checklist

Every blueprint **must** include:

- [ ] **README.md** with all required sections (see [Blueprint Standards](docs/blueprint-standards.md))
- [ ] **Architecture diagram** (PNG or SVG in the blueprint directory)
- [ ] **terraform.tfvars.example** with documented variables
- [ ] **versions.tf** with required provider versions
- [ ] **Complete prerequisites list** linking to shared docs
- [ ] **Resources Created table** listing all cloud resources
- [ ] **Test scenarios** for validating the deployment
- [ ] **Cleanup instructions** including any manual steps

### 3. Naming Conventions

#### Blueprint Directory Names

Use lowercase with hyphens:
```
blueprints/dcf-eks/           # Good
blueprints/DCF_EKS/           # Bad
blueprints/distributed-cloud-firewall-eks/  # Too verbose
```

Pattern: `<feature>-<platform>` or `<use-case>-<cloud>`

Examples:
- `dcf-eks` - Distributed Cloud Firewall with EKS
- `transit-aws` - Transit architecture in AWS
- `multicloud-hub` - Multi-cloud hub and spoke

#### Terraform Resource Naming

Use consistent prefixes within your blueprint:
```hcl
# Use a variable for the prefix
variable "name_prefix" {
  default = "dcf-eks"
}

# Apply consistently
resource "aws_vpc" "main" {
  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}
```

### 4. Terraform Standards

#### File Structure

```
blueprints/your-blueprint/
├── README.md
├── main.tf              # Primary resources
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── versions.tf          # Provider versions
├── terraform.tfvars.example
├── architecture.png     # Architecture diagram
├── CHANGELOG.md         # Version history (recommended)
└── modules/             # Local modules (if needed)
```

#### Required versions.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = ">= 3.1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}
```

#### Variable Documentation

All variables must have descriptions:
```hcl
variable "controller_ip" {
  description = "IP address or hostname of the Aviatrix Controller"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}
```

#### Output Documentation

Outputs should help users interact with the deployment:
```hcl
output "controller_url" {
  description = "URL to access the Aviatrix Controller"
  value       = "https://${var.controller_ip}"
}

output "test_instance_ip" {
  description = "IP address of the test instance for connectivity validation"
  value       = aws_instance.test.public_ip
}
```

### 5. Version Tracking

Blueprints track tested versions and change history:

#### Tested With Section (Required)

Document current tested versions in README:
```markdown
## Tested With

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 8.0.x |
| Aviatrix Terraform Provider | 3.2.0 |
| Terraform | 1.9.x |
| AWS Provider | 5.80.x |
```

#### CHANGELOG.md (Recommended)

Track significant changes in a separate changelog file:
```markdown
# Changelog

## 2025-01-15
- Added support for multiple availability zones
- Updated to Aviatrix provider 3.2.0

## 2024-12-01
- Initial release
```

### 6. State Management

Blueprints use **local state only**. Do not add remote state configuration:

```hcl
# Do NOT include this in blueprints
terraform {
  backend "s3" { ... }
}
```

Users deploying for longer-term use can add their own backend configuration.

## Branching and Pull Request Workflow

The `main` branch is protected. All changes must be submitted via pull request.

### Branch Naming

Use descriptive branch names with a prefix:

| Prefix | Use Case | Example |
|--------|----------|---------|
| `feature/` | New blueprints or features | `feature/dcf-eks-blueprint` |
| `fix/` | Bug fixes | `fix/transit-aws-timeout` |
| `docs/` | Documentation updates | `docs/improve-prerequisites` |
| `chore/` | Maintenance tasks | `chore/update-provider-versions` |

### Workflow

```bash
# 1. Clone the repository (first time only)
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints

# 2. Create a feature branch from main
git checkout main
git pull origin main
git checkout -b feature/your-blueprint-name

# 3. Make your changes
cp -r blueprints/_template blueprints/your-blueprint-name
# ... develop and test ...

# 4. Commit your changes
git add .
git commit -m "Add your-blueprint-name blueprint"

# 5. Push your branch
git push -u origin feature/your-blueprint-name

# 6. Create a Pull Request on GitHub
# Visit: https://github.com/AviatrixSystems/aviatrix-blueprints/pulls
```

### Pull Request Requirements

#### Before Submitting

- [ ] Run `terraform fmt -recursive` on your blueprint
- [ ] Run `terraform validate` successfully
- [ ] Test full deployment and destroy cycle
- [ ] Verify all links in README work
- [ ] Update the blueprint catalog in root README.md

#### PR Description Must Include

- Clear description of what the blueprint does
- Screenshots or diagram of the deployed architecture
- Confirmation that you've tested deploy and destroy
- List of any prerequisites beyond standard requirements

### Review Process

1. **Automated checks**: CI runs `terraform fmt` and `terraform validate`
2. **Maintainer review**: Code and documentation review
3. **Approval required**: At least 1 approving review from a team member with write access
4. **SE validation** (required for merging): Full deployment test by Aviatrix SE

### Merging

Once approved, PRs are merged using **squash merge** to keep the main branch history clean. The PR title becomes the commit message.

### After Merge

- Blueprint appears in catalog as "Community" tier
- Aviatrix team may promote to "Verified" after QA validation
- Version tags are created for releases
- Delete your feature branch (GitHub offers this option after merge)

## Improving Existing Blueprints

### Bug Fixes

1. Create an issue describing the bug
2. Reference the issue in your PR
3. Include steps to reproduce and verify the fix

### Enhancements

1. Create an issue or discussion for feedback
2. Ensure backward compatibility when possible
3. Update documentation to reflect changes

### Documentation Improvements

- Fix typos and clarify confusing sections
- Add missing information discovered during use
- Improve examples and test scenarios

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/aviatrix/aviatrix-blueprints/discussions)
- **Bugs**: Open an [Issue](https://github.com/aviatrix/aviatrix-blueprints/issues)
- **Feature ideas**: Open an [Issue](https://github.com/aviatrix/aviatrix-blueprints/issues) with the "enhancement" label

## Recognition

Contributors are recognized in:
- PR merge comments
- Release notes
- The blueprint's README (for significant contributions)

Thank you for helping build the Aviatrix Blueprints community!