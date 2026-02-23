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
├── .claude/              # Claude Code configuration
│   └── skills/           # Custom skills for blueprint operations
└── .github/              # CI/CD and templates
```

## Blueprint Architecture Patterns

### Single-Layer Blueprints

Simple blueprints with all resources in one directory:
```
blueprints/simple-transit/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── terraform.tfvars.example
```

Deploy with: `terraform init && terraform apply`

### Multi-Layer Blueprints

Complex blueprints with dependencies organized in layers:
```
blueprints/dcf-eks/
├── network/              # Layer 1: Foundation (VPCs, transit, DCF)
│   ├── main.tf
│   ├── dcf.tf
│   └── modules/
├── clusters/             # Layer 2: EKS clusters (parallel deployment)
│   ├── frontend/
│   └── backend/
├── nodes/                # Layer 3: Node groups (parallel deployment)
│   ├── frontend/
│   └── backend/
├── k8s-apps/             # Layer 4: Kubernetes applications (manual)
│   ├── frontend/
│   └── backend/
└── README.md
```

**Deployment order**: network → clusters (parallel) → nodes (parallel) → k8s-apps (manual)

**Data flow between layers**:
- Each layer reads outputs from previous layers using `data "terraform_remote_state" "local"`
- Local backend used exclusively (file-based state in each directory)
- Outputs flow: network → clusters & nodes → k8s-apps

### Working with Multi-Layer Blueprints

When deploying multi-layer blueprints:
1. Always deploy in order: foundation layers first, dependent layers after
2. Layers at the same level (e.g., frontend/backend clusters) can deploy in parallel
3. Each layer has its own state file (`terraform.tfstate`)
4. Use `data "terraform_remote_state" "local"` to reference outputs from other layers
5. Never use remote backends - all blueprints use local state only

Example data source pattern:
```hcl
# In clusters/frontend/data.tf
data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../network/terraform.tfstate"
  }
}

# Reference outputs
vpc_id = data.terraform_remote_state.network.outputs.frontend_vpc_id
```

## Key Standards

### Blueprint Requirements

Every blueprint MUST include:
1. `README.md` with ALL sections from `docs/blueprint-standards.md`
2. Architecture diagram (`architecture.png` or `.svg`)
3. `terraform.tfvars.example` with documented variables
4. `versions.tf` with pinned provider versions
5. Complete "Resources Created" table with cost estimates
6. Test scenarios for validation
7. Cleanup/destroy instructions (reverse order for multi-layer)

### Terraform Patterns

- Use `var.name_prefix` for all resource naming
- Never hardcode regions, account IDs, or credentials
- Mark sensitive variables with `sensitive = true`
- Use `locals` for computed values and common tags
- Always include default tags for resource tracking
- Use consistent file organization:
  - `main.tf` - primary resources
  - `variables.tf` - input variables
  - `outputs.tf` - output values
  - `versions.tf` - provider requirements
  - `data.tf` - data sources (especially remote state)

### Provider Versions

Always use the Aviatrix Terraform provider:
- Registry: `AviatrixSystems/aviatrix`
- Documentation: https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs
- GitHub: https://github.com/AviatrixSystems/terraform-provider-aviatrix

### Naming Conventions

- Blueprint directories: lowercase with hyphens (`aws-eks-multicluster`, `transit-aws`)
- Pattern: `<feature>-<platform>` or `<use-case>-<cloud>`
- Resources: `${var.name_prefix}-<resource-type>`
- Modules: descriptive names in lowercase with hyphens

## Claude Code Skills

This repository includes custom skills accessible via slash commands:

### /deploy-blueprint

Deploy a blueprint with guided orchestration:
```bash
# Deploy entire blueprint
/deploy-blueprint dcf-eks

# Plan only (no apply)
/deploy-blueprint dcf-eks --plan-only

# Deploy specific layer
/deploy-blueprint dcf-eks --layer network
```

The skill handles:
- Prerequisites verification
- Environment file setup (`.env.blueprint`)
- Multi-layer orchestration with parallel deployment
- Output collection and validation
- Post-deployment instructions

### /analyze-blueprint

Analyze a blueprint without deploying:
```bash
/analyze-blueprint dcf-eks
```

Provides:
- Complete resource inventory
- Cost estimates
- Prerequisites checklist
- Dependency graph
- Deployment time estimate

### /validate-blueprint

Run comprehensive validation:
```bash
/validate-blueprint dcf-eks
```

Checks:
- Terraform fmt/validate
- README completeness
- Standards compliance
- File structure

### /test-blueprint (Future)

End-to-end testing with Playwright:
- Deploy blueprint
- Verify in Controller/CoPilot
- Run test scenarios
- Capture screenshots
- Destroy and verify cleanup

## Common Tasks

### Creating a New Blueprint

1. Copy the template:
```bash
cp -r blueprints/_template blueprints/<new-name>
```

2. Update all files:
   - Replace template placeholders in README.md
   - Update `main.tf`, `variables.tf`, `outputs.tf`
   - Configure `versions.tf` with required providers
   - Create `terraform.tfvars.example` with all variables
   - Add architecture diagram (PNG or SVG)

3. Follow blueprint standards:
   - All sections in README.md
   - Resources table with cost estimates
   - Test scenarios
   - Troubleshooting section

4. Test full lifecycle:
```bash
cd blueprints/<new-name>
terraform init
terraform plan
terraform apply
# Run test scenarios
terraform destroy
```

5. Update blueprint catalog in root `README.md`

### Analyzing a Blueprint

When asked to analyze a blueprint, provide:
1. **Resources Created**: Complete table of all cloud resources with costs
2. **Prerequisites**: All required tools, access, and quotas
3. **Cost Estimate**: Hourly/monthly breakdown by component
4. **Dependencies**: External services or configurations needed
5. **Security Considerations**: IAM roles, security groups, exposed endpoints
6. **Deployment Architecture**: Single-layer vs multi-layer, parallel opportunities

### Validating a Blueprint

Run these checks:
```bash
cd blueprints/<name>

# Format check
terraform fmt -check -recursive

# Initialize without backend
terraform init -backend=false

# Validate configuration
terraform validate

# For multi-layer blueprints, validate each layer
for layer in network clusters/* nodes/*; do
  cd "$layer"
  terraform init -backend=false
  terraform validate
  cd -
done
```

### Deploying Multi-Layer Blueprints

**Manual deployment**:
```bash
# Layer 1: Foundation
cd network
terraform init && terraform apply

# Layer 2: Parallel (requires Layer 1 complete)
cd ../clusters/frontend
terraform init && terraform apply &

cd ../backend
terraform init && terraform apply &
wait

# Layer 3: Parallel (requires Layer 2 complete)
cd ../../nodes/frontend
terraform init && terraform apply &

cd ../backend
terraform init && terraform apply &
wait

# Layer 4: Manual Kubernetes deployments
cd ../../k8s-apps
kubectl apply -f frontend/
kubectl apply -f backend/
```

**Automated deployment** (recommended):
```bash
/deploy-blueprint dcf-eks
```

### Destroying Multi-Layer Blueprints

**CRITICAL**: Always destroy in REVERSE order:
```bash
# Remove Kubernetes resources first
kubectl delete -f k8s-apps/backend/
kubectl delete -f k8s-apps/frontend/

# Layer 3: Nodes (parallel)
cd nodes/frontend && terraform destroy &
cd ../backend && terraform destroy &
wait

# Layer 2: Clusters (parallel)
cd ../../clusters/frontend && terraform destroy &
cd ../backend && terraform destroy &
wait

# Layer 1: Foundation (last)
cd ../../network && terraform destroy
```

Or use the skill:
```bash
/deploy-blueprint dcf-eks --destroy
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

## Important Notes

- Blueprints use LOCAL STATE only - never add remote backend configuration
- Always test destroy before considering a blueprint complete
- Include troubleshooting for common failure scenarios
- Link prerequisites to shared docs in `docs/prerequisites/`
- Each blueprint tracks tested versions in a "Tested With" table and optionally a `CHANGELOG.md`
- For multi-layer blueprints, document the deployment order and destroy order explicitly

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

## Development Workflow

### Iterating on a Blueprint

1. Make changes to Terraform files
2. Format code: `terraform fmt -recursive`
3. Validate: `terraform validate`
4. Plan changes: `terraform plan`
5. Apply if needed: `terraform apply`
6. Test scenarios
7. Update README.md if behavior changed
8. Commit changes

### Adding New Features

1. Document the feature in README.md first
2. Add test scenario for the feature
3. Implement in Terraform
4. Verify with test scenario
5. Update cost estimates if needed
6. Add to troubleshooting if failure modes exist

### Debugging Failed Deployments

1. Check Terraform error output
2. Verify prerequisites (especially credentials)
3. Check Controller logs if Aviatrix resource fails
4. Verify quotas in cloud provider console
5. Check for orphaned resources: `terraform state list`
6. Use `-target` flag to retry specific resources
7. Document common issues in Troubleshooting section

## Testing Checklist

Before submitting a new or updated blueprint:

- [ ] `terraform fmt -recursive` passes
- [ ] `terraform validate` passes in all directories
- [ ] Full deploy completes successfully
- [ ] All test scenarios execute and pass
- [ ] Full destroy completes successfully (reverse order for multi-layer)
- [ ] No orphaned resources remain
- [ ] README.md has all required sections
- [ ] Architecture diagram is accurate
- [ ] Cost estimates are current
- [ ] terraform.tfvars.example includes all required variables
- [ ] Variables table is complete and accurate
- [ ] Outputs table is complete and accurate
- [ ] Tested versions table is updated
