# Contributing to Aviatrix Blueprints

Thank you for your interest in contributing to Aviatrix Blueprints! This document provides guidelines and standards for contributions.

## Code of Conduct

Please be respectful and constructive in all interactions. We're building a community resource for cloud security and platform teams.

## Recommended Development Environment

We strongly recommend an AI coding agent for blueprint development. Both **[Claude Code](https://claude.ai/code)** and **[Cursor](https://cursor.com)** work well — they understand Terraform, Aviatrix patterns, and can help ensure your blueprints meet repository standards. The repo ships ready-to-use config for both (see [Setting Up Your Agent](#setting-up-your-agent) below).

### Recommended MCP Servers

Configure these MCP servers for the best development experience. The first three are recommended; the last is optional.

| MCP Server | Purpose | Configuration |
|------------|---------|---------------|
| **GitHub** | Access to Aviatrix Terraform provider docs, modules, and repository management | Official remote server (`https://api.githubcopilot.com/mcp/`) — browser OAuth on first use, no token to paste |
| **Terraform** | Registry lookups for provider/module versions and documentation | HashiCorp `terraform-mcp-server` (runs via Docker) |
| **Serena** | LSP-based code intelligence for semantic understanding of Terraform configurations | [oraios/serena](https://github.com/oraios/serena), runs via `uvx` |
| **Playwright** *(optional)* | Browser automation against a real Aviatrix Control Plane | `@playwright/mcp` — usually unnecessary; prefer the `agent-browser` skill (below) |

> **Browser-based self-testing:** For driving the Aviatrix CoPilot/Controller UI (verifying deployments, capturing screenshots), prefer the bundled **`agent-browser`** skill. It needs no MCP configuration and works out of the box. The Playwright MCP server is an optional alternative.

### Why Use an AI Agent?

- **Standards Compliance**: The agent reads the repository's `CLAUDE.md` / `AGENTS.md` and automatically follows blueprint standards
- **Self-Testing**: With the `agent-browser` skill (or Playwright MCP), the agent can deploy blueprints and verify they work against a real Aviatrix environment
- **Accurate Documentation**: Automatically generates comprehensive resource lists and prerequisites
- **Provider Awareness**: Direct access to Aviatrix Terraform provider documentation ensures correct resource usage

### Setting Up Your Agent

The MCP servers need a couple of local tools available on your PATH:

- **Docker** (for the Terraform server) — [install](https://docs.docker.com/get-docker/)
- **uv / uvx** (for Serena) — [install](https://docs.astral.sh/uv/getting-started/installation/)
- **Node.js / npx** (only if you enable the optional Playwright server) — [install](https://nodejs.org)

#### Claude Code

1. Install the [Claude Code CLI](https://claude.ai/code).
2. Copy the `mcpServers` block from **[.claude/mcp-servers.example.json](.claude/mcp-servers.example.json)** into your Claude Code config (`~/.claude/settings.json`, or a project-level `.mcp.json`):

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/"
    },
    "terraform": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server"]
    },
    "serena": {
      "command": "uvx",
      "args": ["--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "ide-assistant"]
    }
  }
}
```

3. Clone this repository and open it in Claude Code.
4. Claude automatically reads `CLAUDE.md` for project-specific instructions.

#### Cursor

1. Install [Cursor](https://cursor.com).
2. The repo already includes **[.cursor/mcp.json](.cursor/mcp.json)** with the same servers — Cursor picks it up automatically when you open the project. Enable the servers in **Cursor Settings → MCP** on first launch.
3. Cursor reads the root **`AGENTS.md`** (and, by extension, `CLAUDE.md`) for repository conventions.

> Both setups use the same three core servers. The optional Playwright server is in `.claude/mcp-servers.example.json` if you want it; otherwise use the `agent-browser` skill for browser work.

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
- [ ] **AGENTS.md** with agent deployment context (Required Variables, Deploy Sequence, Verification, Common Errors, Constraints)
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
blueprints/aws-eks-multicluster/           # Good
blueprints/DCF_EKS/           # Bad
blueprints/distributed-cloud-firewall-eks/  # Too verbose
```

Pattern: `<feature>-<platform>` or `<use-case>-<cloud>`

Examples:
- `aws-eks-multicluster` - Distributed Cloud Firewall with EKS
- `transit-aws` - Transit architecture in AWS
- `multicloud-hub` - Multi-cloud hub and spoke

#### Terraform Resource Naming

Use consistent prefixes within your blueprint:
```hcl
# Use a variable for the prefix
variable "name_prefix" {
  default = "aws-eks-multicluster"
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

### Getting the Code: Do I Need Special Permissions?

**Short answer:** Anyone can download (clone) this repository because it's public. You do **not** need to be added to the Aviatrix organization just to read or copy the code. You only need extra permission to push changes *back* into the official repository, and even then there's a way around it (forking).

Here's the distinction in plain terms:

| What you want to do | Permission needed | How |
|---------------------|-------------------|-----|
| **Read / clone / copy the code** to your laptop | None. It's public. | `git clone` (anonymous, no account required) |
| **Push a branch directly** into `AviatrixSystems/aviatrix-blueprints` | **Write access** (you must be a member or collaborator added by an Aviatrix admin) | `git push origin your-branch` |
| **Contribute changes without write access** | None. | Fork the repo, push to *your* fork, open a Pull Request |

So if you've been added to the **AviatrixSystems** GitHub organization with write access, use the **Direct (collaborator)** path below. If you're an outside contributor or you aren't sure, use the **Fork** path — it always works and is the standard open-source way to contribute.

> Not sure which you have? Run `gh repo view AviatrixSystems/aviatrix-blueprints --json viewerPermission`. If it shows `WRITE`, `MAINTAIN`, or `ADMIN`, you can push directly. If it shows `READ` (or the command fails because you're not authenticated), use the Fork path.

> **Note for outside contributors:** Direct write access requires being added to the AviatrixSystems organization, which only a GitHub **enterprise owner** can approve (repo admins cannot invite outside collaborators here). If you haven't been added, don't wait on it — the **Fork** path below needs no special access and works immediately.

### Quick Start (Fork-First)

If you just want the fastest path that works for everyone, copy-paste this. It forks the repo, creates a branch, and opens a Pull Request — no special permissions required.

```bash
# One-time: log in (opens a browser)
gh auth login

# Fork the repo to your account and clone it locally
gh repo fork AviatrixSystems/aviatrix-blueprints --clone
cd aviatrix-blueprints

# Start a branch for your change
git checkout -b feature/your-change-name

# ...make your edits, then...
git add .
git commit -m "Describe your change"

# Push to your fork and open a Pull Request (opens a browser)
git push -u origin feature/your-change-name
gh pr create --web
```

The rest of this section explains each step in more detail.

#### Step 0: One-Time Setup (do this first)

1. **Install Git.** Verify it's installed by running `git --version`. If that errors, download it from [git-scm.com/downloads](https://git-scm.com/downloads).
2. **Create a free GitHub account** at [github.com](https://github.com) if you don't have one.
3. **Install the GitHub CLI** (`gh`) — this is the easiest way to handle login for a non-expert. Download from [cli.github.com](https://cli.github.com), then authenticate once:
   ```bash
   gh auth login
   ```
   Choose **GitHub.com** → **HTTPS** → **Login with a web browser**, and follow the prompts. This stores your credentials so you never have to paste a password or token into the terminal again.

   *(Prefer not to use `gh`? You can authenticate with a [Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-secure/managing-your-personal-access-tokens) over HTTPS, or set up [SSH keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh). The `gh` CLI is recommended because it handles all of this for you.)*

#### Path A: Fork (recommended — works for everyone)

Use this if you are **not** a member of the AviatrixSystems org, or aren't sure.

```bash
# 1. Fork the repo into your own GitHub account, then clone YOUR fork.
#    The gh CLI does both in one step and wires up the remotes for you:
gh repo fork AviatrixSystems/aviatrix-blueprints --clone

# (Without gh: click "Fork" at https://github.com/AviatrixSystems/aviatrix-blueprints,
#  then run: git clone https://github.com/<your-username>/aviatrix-blueprints.git)

cd aviatrix-blueprints
```

After cloning a fork you have two remotes: `origin` (your fork, where you push) and `upstream` (the official Aviatrix repo, where you pull updates from). `gh repo fork` sets both up automatically. You push branches to `origin` and open the Pull Request against `upstream`.

#### Path B: Direct (only if you have write access)

Use this **only** if you're an Aviatrix org member with write access.

```bash
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints
```

Here `origin` is the official repo, and you push your feature branches directly to it.

### Branch Naming

Use descriptive branch names with a prefix:

| Prefix | Use Case | Example |
|--------|----------|---------|
| `feature/` | New blueprints or features | `feature/aws-eks-multicluster-blueprint` |
| `fix/` | Bug fixes | `fix/transit-aws-timeout` |
| `docs/` | Documentation updates | `docs/improve-prerequisites` |
| `chore/` | Maintenance tasks | `chore/update-provider-versions` |

### Workflow

Assumes you've already cloned the repo (Path A or Path B above).

```bash
# 1. Make sure you're starting from the latest main
git checkout main
git pull            # Fork users: 'git pull upstream main' to get the newest Aviatrix changes

# 2. Create a feature branch
git checkout -b feature/your-blueprint-name

# 3. Make your changes
cp -r blueprints/_template blueprints/your-blueprint-name
# ... develop and test ...

# 4. Commit your changes
git add .
git commit -m "Add your-blueprint-name blueprint"

# 5. Push your branch to your remote
#    Path A (fork):        pushes to YOUR fork
#    Path B (collaborator): pushes to the official repo
git push -u origin feature/your-blueprint-name

# 6. Open a Pull Request
#    Easiest: run 'gh pr create --web' and follow the browser prompts.
#    Or visit: https://github.com/AviatrixSystems/aviatrix-blueprints/pulls
#    (Fork users: GitHub automatically targets AviatrixSystems/aviatrix-blueprints as the base.)
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