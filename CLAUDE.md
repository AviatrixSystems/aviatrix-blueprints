# CLAUDE.md

This file provides guidance to Claude Code when working with the Aviatrix Blueprints repository.

## Repository Overview

This repository contains production-ready Terraform lab environments ("blueprints") for learning, demonstrating, and testing Aviatrix cloud networking solutions. Each blueprint is a self-contained, deployable environment.

## Project Structure

```
aviatrix-blueprints/
├── blueprints/           # Deployable lab environments
│   ├── _template/        # Template for new blueprints (copy this)
│   └── <name>/           # Individual blueprints
├── docs/                 # Documentation and guides
│   └── prerequisites/    # Tool installation guides
├── modules/              # Shared Terraform modules (future)
└── .github/              # CI/CD and templates
```

## Key Standards

### Blueprint Requirements

Every blueprint MUST include:
1. `README.md` with ALL sections from `docs/blueprint-standards.md`
2. Architecture diagram (`architecture.png` or `.svg`)
3. `terraform.tfvars.example` with documented variables
4. `versions.tf` with pinned provider versions
5. Complete "Resources Created" table
6. Test scenarios for validation
7. Cleanup/destroy instructions

### Terraform Patterns

- Use `var.name_prefix` for all resource naming
- Never hardcode regions, account IDs, or credentials
- Mark sensitive variables with `sensitive = true`
- Use `locals` for computed values and common tags
- Always include default tags for resource tracking

### Provider Versions

Always use the Aviatrix Terraform provider:
- Registry: `AviatrixSystems/aviatrix`
- Documentation: https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs
- GitHub: https://github.com/AviatrixSystems/terraform-provider-aviatrix

### Naming Conventions

- Blueprint directories: lowercase with hyphens (`dcf-eks`, `transit-aws`)
- Pattern: `<feature>-<platform>` or `<use-case>-<cloud>`
- Resources: `${var.name_prefix}-<resource-type>`

## Common Tasks

### Creating a New Blueprint

1. Copy the template: `cp -r blueprints/_template blueprints/<new-name>`
2. Update all files, replacing template placeholders
3. Create architecture diagram
4. Test full deploy/destroy cycle
5. Update blueprint catalog in root `README.md`

### Analyzing a Blueprint

When asked to analyze a blueprint, provide:
1. **Resources Created**: Complete table of all cloud resources
2. **Prerequisites**: All required tools, access, and quotas
3. **Cost Estimate**: Approximate hourly/monthly cost
4. **Dependencies**: External services or configurations needed
5. **Security Considerations**: IAM roles, security groups, exposed endpoints

### Validating a Blueprint

Run these checks:
```bash
cd blueprints/<name>
terraform fmt -check
terraform init -backend=false
terraform validate
```

### Testing with Playwright

When Playwright MCP is available, Claude can:
1. Deploy the blueprint to a test environment
2. Navigate to the Aviatrix Control Plane (Controller for API validation, CoPilot for UI verification)
3. Verify resources appear correctly
4. Run connectivity tests
5. Capture screenshots for documentation
6. Clean up resources

## MCP Server Integration

### GitHub MCP

Use for:
- Looking up Aviatrix provider resource documentation
- Checking module versions and examples
- Creating issues and PRs

Key repositories:
- `AviatrixSystems/terraform-provider-aviatrix` - Provider source
- `AviatrixSystems/terraform-aviatrix-aws-transit` - Transit module
- `AviatrixSystems/terraform-aviatrix-mc-spoke` - Multi-cloud spoke module

### Terraform MCP

Use for:
- Looking up latest provider versions
- Getting resource documentation
- Finding module examples

### Playwright MCP

Use for:
- Automated deployment testing
- Control Plane UI verification (CoPilot for visualization, Controller for configuration)
- Screenshot capture for documentation
- End-to-end validation

### Serena MCP

Use for:
- Semantic code analysis
- Cross-file refactoring
- Symbol lookups and references

## Skills (Future)

The following skills will be available for blueprint development:

### /analyze-blueprint
Analyze a blueprint directory and generate:
- Complete resources created table
- Prerequisites checklist
- Cost estimate
- Dependency graph

### /validate-blueprint
Run comprehensive validation:
- Terraform fmt/validate
- README completeness check
- Standards compliance
- Link verification

### /test-blueprint
Deploy and test a blueprint:
- Initialize and apply
- Verify in the Aviatrix Control Plane (Controller and CoPilot)
- Run test scenarios
- Capture evidence
- Destroy and verify cleanup

## Important Notes

- Blueprints use LOCAL STATE only - never add remote backend configuration
- Always test destroy before considering a blueprint complete
- Include troubleshooting for common failure scenarios
- Link prerequisites to shared docs in `docs/prerequisites/`
- Each blueprint tracks tested versions in a "Tested With" table and optionally a `CHANGELOG.md`

## Aviatrix-Specific Knowledge

### Cloud Type Codes

When using the Aviatrix provider, cloud types are:
- `1` = AWS
- `2` = GCP
- `4` = Azure
- `8` = OCI
- `256` = AWS GovCloud
- `512` = Azure Gov
- `1024` = AWS China
- `2048` = Azure China

### Common Resource Types

- `aviatrix_transit_gateway` - Transit hub gateway
- `aviatrix_spoke_gateway` - Spoke gateway attached to transit
- `aviatrix_transit_gateway_peering` - Transit-to-transit peering
- `aviatrix_distributed_firewalling_config` - DCF configuration
- `aviatrix_smart_group` - Smart groups for segmentation
- `aviatrix_web_group` - Web groups for URL filtering
- `aviatrix_distributed_firewalling_policy_list` - DCF policies

### Aviatrix Control Plane

The Aviatrix Control Plane consists of:
- **Controller** - Management plane for Terraform and API operations
- **CoPilot** - GUI for visualization, monitoring, and day-2 operations

Alternatively, users may have an **Aviatrix Cloud Fabric** subscription (fully managed control plane).

Most blueprints should include CoPilot verification steps:
- Topology view showing deployed architecture
- FlowIQ for traffic analysis
- Security > DCF for firewall rules (if applicable)
- Performance > Diagnostics for connectivity tests
