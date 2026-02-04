---
name: deploy-blueprint
description: Deploy an Aviatrix blueprint to your environment with guided, multi-step orchestration. Handles both simple single-layer and complex multi-layer blueprints.
argument-hint: "[blueprint-path] [--plan-only] [--layer <layer-name>]"
disable-model-invocation: true
context: fork
agent: general-purpose
allowed-tools:
  - Bash(terraform *)
  - Bash(aws *)
  - Bash(kubectl *)
  - Bash(helm *)
  - Bash(gh *)
  - Bash(find *)
  - Bash(source *)
  - Task
  - AskUserQuestion
  - Read
  - Grep
  - Glob
  - Write
---

# Deploy Blueprint

Deploy an Aviatrix blueprint to your environment with guided, multi-step orchestration.

## Usage

```
/deploy-blueprint [blueprint-path] [--plan-only] [--layer <layer-name>]
```

Options:
- `--plan-only`: Review deployment plan without applying changes
- `--layer <layer>`: Deploy specific layer only (e.g., `network`, `clusters`, `nodes`)

If no path is provided, prompts for blueprint selection.

## Prerequisites

This skill requires:
- **Aviatrix Control Plane** accessible (Controller and optionally CoPilot)
- **Cloud provider credentials** configured (AWS CLI, Azure CLI, or gcloud)
- **Terraform v1.5+** installed
- **Valid terraform.tfvars** with appropriate values

## What This Skill Does

1. **Blueprint Selection** - Choose which blueprint to deploy
2. **README Review** - Display key information from documentation
3. **Prerequisites Check** - Verify tools, access, and configuration
4. **Environment File Setup** - Create/verify credentials file
5. **Deployment Planning** - Analyze architecture and create execution plan
6. **Orchestrated Deployment** - Execute deployment with subagents for efficiency
7. **Validation** - Verify deployment success
8. **Post-Deployment** - Provide next steps and access information

## Deployment Workflow

### Phase 1: Blueprint Selection

If no blueprint path provided, display available blueprints and prompt for selection.

### Phase 2: README Review

Display key sections from the blueprint README:
- Description and architecture summary
- Estimated cost and deployment time
- Link to full README

Ask for confirmation to continue.

### Phase 3: Prerequisites Check

Verify all required tools and access:
- Terraform version
- Cloud CLI tools
- Configuration files
- Controller connectivity

Interactively prompt for:
- Controller URL and credentials
- Cloud account information
- Blueprint-specific variables

### Phase 4: Environment File Setup

Create or verify environment file for credentials:

```bash
# Create .env.blueprint file
cat > .env.blueprint <<EOF
export AVIATRIX_CONTROLLER_IP="${controller_ip}"
export AVIATRIX_USERNAME="${username}"
export AVIATRIX_PASSWORD="${password}"
export AWS_REGION="${aws_region}"
EOF

# Add to .gitignore
echo ".env.blueprint" >> .gitignore

# Source the file
source .env.blueprint
```

### Phase 5: Deployment Planning

Analyze blueprint architecture:
- Detect if single-layer or multi-layer
- For multi-layer: identify dependencies and deployment order
- Run `terraform plan` for each layer to count resources
- Display deployment summary with time estimates

Ask for confirmation to proceed.

### Phase 6: Orchestrated Deployment

**For multi-layer deployments:**

```
Layer 1: Sequential deployment (foundation)
  └─ Deploy network layer

Layer 2: Parallel deployment (if multiple subdirectories)
  ├─ Spawn subagent for clusters/frontend
  └─ Spawn subagent for clusters/backend

Layer 3: Parallel deployment (if multiple subdirectories)
  ├─ Spawn subagent for nodes/frontend
  └─ Spawn subagent for nodes/backend
```

Use the Task tool with `subagent_type=Bash` to spawn deployment agents for parallel execution.

**For single-layer deployments:**

Use a single agent for straightforward deployment.

### Phase 7: Validation

Verify deployment success:
- Check gateway status in Controller
- Verify EKS clusters (if applicable)
- Run connectivity tests
- Validate against expected outputs

### Phase 8: Post-Deployment

Provide access information:
- Kubernetes cluster access commands
- Controller/CoPilot URLs and navigation
- Sample application deployment instructions
- Next steps from README
- Destroy instructions (in reverse order)

## Instructions for Claude

When this skill is invoked:

### 1. Blueprint Selection

```bash
# If no path provided, list available blueprints
find blueprints/ -maxdepth 1 -type d -not -name ".*" -not -name "blueprints"

# Read README.md from selected blueprint
# Extract: title, description, estimated cost, deployment time, architecture type
```

### 2. Prerequisites Check

```bash
# Check required tools
terraform --version
aws --version
kubectl version --client

# Check for configuration files
test -f terraform.tfvars || test -f terraform.tfvars.example
```

Use `AskUserQuestion` to collect:
- Aviatrix Controller URL
- Aviatrix credentials
- Cloud provider information
- Blueprint-specific variables

### 3. Environment File Creation

```bash
# Check if .env.blueprint exists
if [ ! -f .env.blueprint ]; then
  # Create environment file with collected credentials
  # Add to .gitignore
fi

# Source the file
source .env.blueprint
```

### 4. Architecture Analysis

```bash
# Detect blueprint structure
if [ -d "network" ] && [ -d "clusters" ]; then
  architecture_type="multi-layer"
  layers=("network" "clusters" "nodes")
else
  architecture_type="single-layer"
  layers=(".")
fi

# For each layer, run terraform plan to count resources
cd ${layer_dir}
terraform init -backend=false
terraform plan -detailed-exitcode
# Parse plan output for resource count
```

### 5. Deployment Orchestration

For multi-layer deployments, use Task tool to spawn subagents:

```
Task 1: Deploy network layer
  Prompt: "Deploy the network layer at $blueprint/network.
          Run terraform init, plan, and apply.
          Capture outputs for next layer.
          Report progress with resource creation status."

Task 2: Deploy frontend cluster (after Task 1)
  Prompt: "Deploy the frontend cluster at $blueprint/clusters/frontend.
          Use data sources to read network layer state.
          Run terraform init, plan, and apply.
          Report cluster ARN and endpoint when complete."

Task 3: Deploy backend cluster (parallel with Task 2)
  [Similar prompt]
```

For single-layer deployments, execute directly.

### 6. Validation

```bash
# Verify Aviatrix resources
# Parse terraform output for gateway names

# Verify Kubernetes resources (if applicable)
aws eks update-kubeconfig --name <cluster-name> --region <region>
kubectl get nodes
kubectl get pods -A

# Run connectivity tests if defined in README
```

### 7. Post-Deployment Output

```bash
# Extract important outputs
terraform output -json > outputs.json

# Parse outputs and format access instructions
# Include:
# - Cluster names and access commands
# - Controller/CoPilot URLs
# - Cost summary
# - Next steps from README
# - Destroy instructions (in reverse order)
```

## Error Handling

### Terraform Errors

If terraform apply fails:
1. Capture full error output
2. Check common issues (missing variables, auth failures, quota exceeded, dependencies)
3. Provide specific remediation steps
4. Ask if user wants to retry, continue, or abort

### Credential Issues

If authentication fails:
1. Verify credentials in .env.blueprint
2. Test Controller connectivity
3. Test cloud provider credentials
4. Offer to recreate .env.blueprint

### Partial Deployment

If deployment fails mid-layer:
1. Identify which resources were created
2. Offer options: resume, destroy partial deployment, or manual intervention
3. Preserve state files
4. Log all outputs for debugging

## Plan-Only Mode

When `--plan-only` flag is used:
1. Run all checks through Phase 5 (Planning)
2. Execute terraform plan (but not apply) for each layer
3. Show complete resource list and cost estimates
4. Export plan to file: `terraform plan -out=tfplan`
5. Provide command to apply later

## Layer-Specific Deployment

When `--layer <name>` flag is used:
1. Verify dependencies are met (previous layers deployed)
2. Deploy only the specified layer
3. Skip layers that depend on this one
4. Warn about incomplete deployment

## Output Files

Generate these files during deployment:
- `.env.blueprint` - Environment variables with credentials
- `.deploy-blueprint-<timestamp>.log` - Complete deployment log
- `terraform.tfplan` - Saved plan file (if --plan-only)
- `outputs-<layer>.json` - JSON outputs from each layer

## Security Notes

- Never display passwords in plain text (use ******)
- Always add .env.blueprint to .gitignore
- Warn about local state file risks
- Remind users to destroy resources when done
- Check for exposed security groups or public endpoints in validation
