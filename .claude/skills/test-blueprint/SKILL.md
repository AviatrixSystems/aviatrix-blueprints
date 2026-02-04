---
name: test-blueprint
description: Deploy a blueprint to a real environment, verify it works, run test scenarios, and clean up. Use for end-to-end testing of blueprints.
argument-hint: "[blueprint-path] [--keep] [--screenshots]"
disable-model-invocation: true
allowed-tools:
  - Bash(terraform *)
  - Bash(aws *)
  - Bash(kubectl *)
  - Bash(curl *)
  - Bash(ssh *)
  - Read
  - Grep
  - Glob
---

# Test Blueprint

Deploy a blueprint to a real environment, verify it works, run test scenarios, and clean up.

## Usage

```
/test-blueprint [blueprint-path] [--keep] [--screenshots]
```

Options:
- `--keep`: Don't destroy resources after testing (for manual inspection)
- `--screenshots`: Capture screenshots of the Aviatrix Control Plane for documentation

## Prerequisites

This skill requires:
- **Playwright MCP server** configured and running (optional, for screenshots)
- **Valid terraform.tfvars** with real credentials
- **Aviatrix Control Plane** (Controller and CoPilot) accessible from the test environment
- **Cloud provider credentials** configured

## What This Skill Does

1. **Pre-flight checks** - Validates configuration before deployment
2. **Deploy** - Runs `terraform apply`
3. **Verify in Controller** - Uses Playwright to check resources in UI
4. **Run test scenarios** - Executes tests defined in README
5. **Capture evidence** - Screenshots for documentation
6. **Cleanup** - Runs `terraform destroy`
7. **Verify cleanup** - Confirms no orphaned resources

## Test Workflow

### Phase 1: Pre-flight

```
Checking prerequisites...
✅ terraform.tfvars exists
✅ Controller reachable at 10.0.0.1
✅ AWS credentials valid
✅ Required quotas available
```

### Phase 2: Deploy

```
Deploying blueprint...
terraform init... done
terraform plan... 23 resources to create
terraform apply...

Creating resources:
  aws_vpc.transit... created
  aws_vpc.spoke_1... created
  aviatrix_transit_gateway.main... created (3m 45s)
  aviatrix_spoke_gateway.spoke_1... created (2m 30s)
  ...

✅ Deployment complete (8m 23s)
```

### Phase 3: Verify in Control Plane

Uses Playwright to:
1. Log into the Aviatrix Control Plane
2. Navigate to Cloud Fabric > Gateways
3. Verify transit gateway appears and is UP
4. Verify spoke gateways appear and are UP
5. Check attachments are established
6. Navigate to CoPilot topology (if applicable)
7. Verify architecture matches diagram

```
Verifying in Control Plane...
✅ Transit gateway 'dcf-eks-transit' status: UP
✅ Spoke gateway 'dcf-eks-spoke-1' status: UP
✅ Spoke gateway 'dcf-eks-spoke-2' status: UP
✅ Transit-spoke attachment verified
✅ CoPilot topology shows correct architecture
```

### Phase 4: Run Test Scenarios

Executes test scenarios from the blueprint README:

```
Running test scenarios...

Scenario 1: East-West Connectivity
  → SSH to spoke-1 test instance
  → Ping spoke-2 private IP
  ✅ Ping successful (latency: 2.3ms)

Scenario 2: DCF Inspection
  → Generate traffic between spokes
  → Check CoPilot > Security > DCF Monitor
  ✅ Traffic appears in DCF logs
  ✅ Correct policy applied

Scenario 3: Internet Egress
  → SSH to spoke instance
  → curl https://api.ipify.org
  ✅ Egress through NAT gateway confirmed
```

### Phase 5: Capture Evidence

If `--screenshots` is enabled:

```
Capturing screenshots...
📸 controller-topology.png
📸 copilot-flowiq.png
📸 dcf-monitor.png
📸 gateway-status.png
```

### Phase 6: Cleanup

```
Destroying resources...
terraform destroy...

Destroying resources:
  aviatrix_spoke_gateway.spoke_2... destroyed
  aviatrix_spoke_gateway.spoke_1... destroyed
  aviatrix_transit_gateway.main... destroyed
  aws_vpc.spoke_1... destroyed
  ...

✅ Destroy complete (5m 12s)
```

### Phase 7: Verify Cleanup

```
Verifying cleanup...
✅ No VPCs with blueprint tag found
✅ No gateways in Control Plane
✅ No orphaned EIPs
✅ Cleanup verified
```

## Instructions for Claude

When this skill is invoked:

### 1. Pre-flight Checks

```bash
# Verify tfvars exists
test -f terraform.tfvars

# Test Controller connectivity
curl -k https://${CONTROLLER_IP}/v1/api

# Verify cloud credentials
aws sts get-caller-identity
```

### 2. Deploy

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Monitor for errors and capture output.

### 3. Verify with Playwright

Use Playwright MCP to:
- Open browser to Controller URL
- Log in with provided credentials
- Navigate to relevant pages
- Verify resources exist and are healthy
- Take screenshots if requested

### 4. Run Test Scenarios

Parse the README's "Test Scenarios" section and execute each one:
- SSH commands via Bash
- UI verifications via Playwright
- API calls via curl

### 5. Cleanup

```bash
terraform destroy -auto-approve
```

### 6. Verify Cleanup

Check for orphaned resources:
```bash
# AWS example
aws ec2 describe-vpcs --filters "Name=tag:Blueprint,Values=<name>"
```

Use Playwright to verify nothing remains in the Control Plane.

## Output Format

```
=== Blueprint Test Report ===

Blueprint: dcf-eks
Date: 2024-01-15 14:32:00 UTC
Duration: 18m 45s

## Summary
✅ Deployment: SUCCESS
✅ Verification: SUCCESS
✅ Test Scenarios: 3/3 PASSED
✅ Cleanup: SUCCESS

## Deployment Details
- Resources created: 23
- Deployment time: 8m 23s
- No errors

## Test Results

| Scenario | Result | Duration |
|----------|--------|----------|
| East-West Connectivity | ✅ PASS | 45s |
| DCF Inspection | ✅ PASS | 1m 20s |
| Internet Egress | ✅ PASS | 30s |

## Screenshots
- controller-topology.png
- dcf-monitor.png

## Cleanup Details
- Resources destroyed: 23
- Destroy time: 5m 12s
- Orphan check: CLEAN

---
Blueprint dcf-eks is **VERIFIED** ✅
```

## Error Handling

If any phase fails:

1. **Deployment fails**: Capture error, attempt cleanup, report failure
2. **Verification fails**: Continue with tests, note discrepancy
3. **Test fails**: Log failure, continue other tests, include in report
4. **Cleanup fails**: Report orphaned resources, provide manual cleanup steps
