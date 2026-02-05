# Claude Code Configuration

This directory contains configuration and skills for [Claude Code](https://claude.ai/code) to work effectively with the Aviatrix Blueprints repository.

## Contents

```
.claude/
├── README.md                   # This file
├── settings.json               # Project-level Claude Code settings
├── mcp-servers.example.json    # Example MCP server configuration
└── skills/                     # Custom skills for blueprint development
    ├── analyze-blueprint.md
    ├── validate-blueprint.md
    ├── deploy-blueprint.md
    └── test-blueprint.md
```

## MCP Server Setup

For the best experience developing blueprints, configure these MCP servers in your **global** Claude Code settings (`~/.claude.json` or via Claude Code settings):

| Server | Purpose |
|--------|---------|
| **GitHub** | Access to Aviatrix provider documentation and repository management |
| **Terraform** | Registry lookups for provider/module versions |
| **Playwright** | Browser automation for testing against the Aviatrix Control Plane |
| **Serena** | LSP-based code intelligence for Terraform |

Copy the configuration from `mcp-servers.example.json` to your global settings.

## Skills

### /analyze-blueprint

Analyzes a blueprint and generates:
- Complete resource inventory
- Prerequisites checklist
- Cost estimates
- Required permissions

### /validate-blueprint

Validates a blueprint against repository standards:
- Terraform fmt/validate
- README completeness
- Naming conventions
- Security checks

### /deploy-blueprint

Deploys a blueprint with guided, multi-step orchestration:
- Interactive blueprint selection
- README review and prerequisites check
- Environment file creation for credentials
- Multi-layer architecture analysis
- Orchestrated deployment with parallel subagents
- Validation and connectivity tests
- Post-deployment access information

Supports both simple single-layer and complex multi-layer blueprints (like aws-eks-multicluster with network → clusters → nodes).

### /test-blueprint

Deploys and tests a blueprint end-to-end:
- Pre-flight checks
- Terraform apply
- Control Plane verification (Controller and CoPilot)
- Test scenario execution
- Cleanup and orphan check

## Usage

1. Install [Claude Code](https://claude.ai/code)
2. Configure MCP servers in your global settings (see `mcp-servers.example.json`)
3. Open this repository in Claude Code
4. Claude will automatically read the project's `CLAUDE.md` for context
5. Use skills with:
   - `/analyze-blueprint` - Understand what a blueprint creates
   - `/validate-blueprint` - Check blueprint against standards
   - `/deploy-blueprint` - Deploy a blueprint to your environment
   - `/test-blueprint` - Full end-to-end testing with cleanup

## Customization

To add custom skills:
1. Create a new `.md` file in the `skills/` directory
2. Follow the format of existing skills
3. Claude Code will automatically recognize the new skill

## Environment Variables

Some MCP servers require environment variables:

```bash
# GitHub MCP
export GITHUB_TOKEN="your-github-token"

# For testing (optional)
export AVIATRIX_CONTROLLER_IP="10.0.0.1"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"
```
