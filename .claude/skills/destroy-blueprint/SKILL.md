---
name: destroy-blueprint
description: Tear down an Aviatrix blueprint and clean up all cloud resources. Handles both simple single-layer and complex multi-layer blueprints in the correct reverse order.
argument-hint: "[blueprint-path] [--layer <layer-name>] [--force]"
disable-model-invocation: true
context: fork
agent: general-purpose
allowed-tools:
  - Bash(terraform *)
  - Bash(aws *)
  - Bash(az *)
  - Bash(kubectl *)
  - Bash(helm *)
  - Bash(gh *)
  - Bash(find *)
  - Bash(source *)
  - Bash(rm *)
  - Task
  - AskUserQuestion
  - Read
  - Grep
  - Glob
  - Write
---

# Destroy Blueprint

Tear down an Aviatrix blueprint and remove all cloud resources. Executes destruction in the correct reverse dependency order for multi-layer blueprints.

## Usage

```
/destroy-blueprint [blueprint-path] [--layer <layer-name>] [--force]
```

Options:
- `--layer <layer>`: Destroy a specific layer only (e.g., `nodes`, `clusters`, `network`)
- `--force`: Skip confirmation prompts (use with care)

If no path is provided, prompts for blueprint selection.

## What This Skill Does

1. **Blueprint Selection** - Identify which blueprint to destroy
2. **State Inventory** - Detect which layers have active state
3. **Pre-Destroy Check** - Confirm what will be destroyed and warn about cost savings
4. **Kubernetes Cleanup** - Remove k8s workloads before Terraform (if applicable)
5. **Orchestrated Destruction** - Execute destroy in reverse layer order
6. **Verification** - Confirm all resources are removed
7. **Cleanup** - Remove state files, log files, and local artifacts

## Destruction Order

**CRITICAL**: Always destroy in reverse deployment order to avoid dependency failures.

For a typical multi-layer blueprint (e.g., `dcf-eks`):
```
Step 1: k8s-apps/    (kubectl delete — manual resources)
Step 2: nodes/       (parallel: frontend & backend)
Step 3: clusters/    (parallel: frontend & backend)
Step 4: network/     (last — foundation layer)
```

For single-layer blueprints, run `terraform destroy` in the single directory.

## Instructions for Claude

### 1. Blueprint Selection

```bash
# If no path provided, list available blueprints and check for active state
find blueprints/ -maxdepth 1 -type d -not -name ".*" -not -name "blueprints"

# Check which blueprints have active terraform.tfstate files
find blueprints/ -name "terraform.tfstate" -not -empty 2>/dev/null
```

Show the user which blueprints have active deployments (non-empty state files) and which are clean, then ask which to destroy.

### 2. State Inventory

```bash
# Detect blueprint structure
blueprint_dir="blueprints/<selected>"

# Single-layer check
if [ -f "$blueprint_dir/terraform.tfstate" ]; then
  echo "Single-layer blueprint with active state"
fi

# Multi-layer check — list layers with state
find "$blueprint_dir" -name "terraform.tfstate" -not -empty | sort
```

For each layer with active state, report the resource count:
```bash
cd <layer_dir>
terraform state list 2>/dev/null | wc -l
```

### 3. Pre-Destroy Confirmation

Display a destruction plan:
```
Blueprint:   <name>
Layers:      4 layers with active state
Resources:   ~47 resources across all layers
Cloud cost:  Stopping ~$X/hr

Destruction order:
  1. k8s-apps (kubectl)
  2. nodes/frontend, nodes/backend (parallel)
  3. clusters/frontend, clusters/backend (parallel)
  4. network (sequential, last)
```

Unless `--force` is set, use `AskUserQuestion` to confirm before proceeding. This is irreversible.

### 4. Kubernetes Cleanup (if applicable)

Before running `terraform destroy` on any layer containing Kubernetes resources, remove managed workloads:

```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>
# or
az aks get-credentials --resource-group <rg> --name <cluster-name>

# Remove Helm releases
helm list -A
helm uninstall <release> -n <namespace>

# Remove remaining k8s resources from k8s-apps directory
kubectl delete -f k8s-apps/backend/ --ignore-not-found
kubectl delete -f k8s-apps/frontend/ --ignore-not-found

# Wait for pods to terminate
kubectl get pods -A --watch
```

Removing Helm/kubectl resources before terraform destroy prevents finalizer deadlocks and orphaned cloud resources (LoadBalancers, PVCs, etc.).

### 5. Orchestrated Destruction

**Source credentials first:**
```bash
if [ -f .env.blueprint ]; then
  source .env.blueprint
fi
```

**Multi-layer destruction (reverse order):**

For layers at the same level (e.g., all `nodes/` subdirs), destroy in parallel using Task tool:

```
Task A: Destroy nodes/frontend
  Prompt: "Run terraform destroy -auto-approve in <blueprint>/nodes/frontend.
           Source .env.blueprint first if it exists.
           Report each resource destroyed and any errors.
           Return the final resource count remaining."

Task B: Destroy nodes/backend  (parallel with Task A)
  [Similar prompt]
```

Wait for both tasks before proceeding to the next layer down.

**Sequential layers (foundation last):**
```bash
cd network
terraform destroy -auto-approve
```

**Single-layer destruction:**
```bash
cd <blueprint>
terraform destroy -auto-approve
```

### 6. Handling Destroy Errors

**State drift / resource already deleted externally:**
```bash
# Remove from state and retry
terraform state rm <resource_address>
terraform destroy -auto-approve
```

**AVXERR-DFW-0025 (DCF ruleset conflict):**
```bash
# Remove stale ruleset from state
terraform state rm aviatrix_dcf_ruleset.<name>
terraform destroy -auto-approve
```

**Azure SubnetMissingRequiredDelegation:**
```bash
# Destroy dependent resources first with -target
terraform destroy -target=<dependent_resource> -auto-approve
# Then destroy the rest
terraform destroy -auto-approve
```

**AKS pod_subnet delegation drift on teardown:**
```bash
# Known issue: use -target to destroy the subnet delegation resource before the subnet
terraform destroy -target=azurerm_subnet_service_endpoint_storage_policy.<name> -auto-approve
terraform destroy -auto-approve
```

For any error that blocks the full destroy:
1. Report the exact error to the user
2. Check if the resource is already gone in the cloud console
3. If so, offer `terraform state rm` as the remediation
4. If not, diagnose and provide specific fix steps
5. Do NOT silently skip resources — always confirm with the user before `state rm`

### 7. Verification

After all layers are destroyed, verify no resources remain:

```bash
# Check each layer directory for remaining state
for state_file in $(find "$blueprint_dir" -name "terraform.tfstate"); do
  resource_count=$(terraform -chdir=$(dirname "$state_file") state list 2>/dev/null | wc -l)
  echo "$state_file: $resource_count resources remaining"
done
```

If any resources remain, report them and offer to retry that specific layer.

Optionally check the cloud provider for orphaned resources (LoadBalancers, EIPs, ENIs) if the blueprint documentation lists common orphans.

### 8. Cleanup

After successful destruction, offer to remove local artifacts:

```bash
# Remove state files (only after confirming empty)
find "$blueprint_dir" -name "terraform.tfstate" -empty -delete
find "$blueprint_dir" -name "terraform.tfstate.backup" -delete

# Remove cached provider plugins and .terraform directories
find "$blueprint_dir" -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
find "$blueprint_dir" -name ".terraform.lock.hcl" -delete

# Remove deployment artifacts
find "$blueprint_dir" -name "outputs-*.json" -delete
find "$blueprint_dir" -name ".deploy-blueprint-*.log" -delete

# Remove .env.blueprint (ask first — user may want to keep credentials for redeployment)
```

Ask the user before deleting `.env.blueprint` and `.terraform/` directories, as they may want to redeploy.

## Layer-Specific Destruction

When `--layer <name>` is used:
1. Warn that destroying a foundation layer while upper layers exist will likely fail
2. Check that dependent layers have already been destroyed
3. If dependencies exist, list them and offer to abort or continue
4. Proceed with single-layer destroy

## Output

At the end, report:
```
Destruction complete for: <blueprint-name>

  Layers destroyed: 4/4
  Resources removed: ~47
  Time elapsed: ~8m

  Cloud cost stopped: ~$X/hr
  Monthly savings: ~$Y/mo

  Local artifacts cleaned: yes / no (kept for redeployment)
```

## Security Notes

- Destruction is **irreversible** — always confirm before proceeding unless `--force` is set
- State files are deleted last, only after confirming all cloud resources are removed
- Warn if `.env.blueprint` contains credentials that should be rotated after lab teardown
- Check for any public endpoints or security groups that may have been created outside Terraform
