# Zero Trust Network Segmentation

Demonstrates Zero Trust Network Segmentation using Aviatrix Distributed Cloud Firewall (DCF) with SmartGroups. This blueprint creates a simple three-tier architecture (Dev, Prod, Database) with policy-based segmentation that prevents lateral movement while allowing authorized traffic flows.

> [!TIP]
> **🤖 Optimized for Claude Code** — Run `/deploy-blueprint zero-trust-segmentation` for AI-guided deployment with prerequisite checks, or `/analyze-blueprint zero-trust-segmentation` for resource and cost details. [Get Claude Code](https://claude.ai/code)

---

## Architecture

![Architecture Diagram](architecture.svg)

This blueprint deploys:
- **1 Aviatrix Transit Gateway** - Central hub for all spoke connectivity
- **3 Aviatrix Spoke Gateways** - One for each environment (Dev, Prod, DB)
- **3 AWS VPCs** - Isolated network segments for each environment
- **3 EC2 Test Instances** - One per environment for connectivity validation
- **3 DCF SmartGroups** - Dynamic groups based on environment tags
- **5 DCF Policies** - Zero Trust rules enforcing segmentation

**Traffic Flow Rules:**
- ✅ **Prod → DB**: ALLOW (production needs database access)
- ✅ **Dev → Prod**: ALLOW ICMP only (developers can ping production for diagnostics)
- ❌ **Dev → DB**: DENY (prevents unauthorized data access)
- ❌ **Prod → Dev**: DENY (production isolation from development)
- ❌ **Default**: DENY all other traffic (Zero Trust principle)

## Prerequisites

### Required Tools

- [Aviatrix Control Plane](../../docs/prerequisites/aviatrix-controller.md) (v7.1+) - Controller and CoPilot
- [Terraform](../../docs/prerequisites/terraform.md) (v1.5+)
- [AWS CLI](../../docs/prerequisites/aws-cli.md)

### Required Access

- AWS account with permissions to create VPCs, EC2 instances, and networking resources
- Aviatrix Control Plane with AWS account onboarded
- AWS EC2 key pair for SSH access to test VMs

### Blueprint-Specific Requirements

- At least 3 available Elastic IPs in the target AWS region
- AWS Systems Manager (SSM) permissions if using automated test script

## Resources Created

| Resource | Description | Quantity | Estimated Cost/Hour |
|----------|-------------|----------|---------------------|
| **Aviatrix Transit Gateway** | Central hub gateway (t3.small) | 1 | $0.05 |
| **Aviatrix Spoke Gateways** | Spoke gateways for each environment (t3.small) | 3 | $0.15 |
| **AWS VPCs** | Virtual Private Clouds | 4 | Free |
| **AWS Subnets** | Public and private subnets | 8 | Free |
| **AWS Internet Gateways** | Internet connectivity | 4 | Free |
| **AWS Route Tables** | Routing configuration | 8 | Free |
| **AWS Security Groups** | Firewall rules for test VMs | 3 | Free |
| **EC2 Instances** | Test VMs (t3.micro) | 3 | $0.03 |
| **Elastic IPs** | Public IPs for gateways | 4 | $0.02 |
| **DCF SmartGroups** | Dynamic network segments | 3 | Free |
| **DCF Policies** | Zero Trust firewall rules | 5 | Free |

**Total Estimated Cost**: ~$0.25/hour (~$6/day or ~$180/month)

> **Note:** Costs are estimates for us-east-1 and may vary by region. Remember to destroy resources after testing.

## Deployment

### Step 1: Clone and Navigate

```bash
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/zero-trust-segmentation
```

### Step 2: Configure Environment Variables

```bash
# Set Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<your-controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<your-password>"

# Set AWS credentials (if not using AWS CLI profile)
export AWS_ACCESS_KEY_ID="<your-access-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret-key>"
export AWS_REGION="us-east-1"
```

### Step 3: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_account_name      = "my-aws-account"  # As configured in Aviatrix Controller
aws_region            = "us-east-1"
name_prefix           = "zt-seg"
test_vm_key_name      = "my-keypair"      # Must exist in your AWS account
test_vm_instance_type = "t3.micro"
```

### Step 4: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted to confirm.

**Deployment takes approximately 10-15 minutes.**

### Step 5: Verify Deployment

After deployment completes:

```bash
# View outputs
terraform output

# You should see:
# - Transit and spoke gateway names
# - Test VM private IPs
# - SmartGroup UUIDs
# - Test scenarios to run
```

## Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `name_prefix` | Prefix for all resource names | `string` | `"zt-seg"` | no |
| `aws_region` | AWS region for deployment | `string` | `"us-east-1"` | no |
| `aws_account_name` | Aviatrix Access Account name for AWS | `string` | - | **yes** |
| `test_vm_key_name` | EC2 key pair name for SSH access | `string` | - | **yes** |
| `test_vm_instance_type` | EC2 instance type for test VMs | `string` | `"t3.micro"` | no |
| `transit_gateway` | Transit gateway configuration | `object` | See below | no |
| `spokes` | Spoke gateway configurations | `map(object)` | See below | no |

**Default `transit_gateway` value:**
```hcl
{
  cidr       = "10.0.0.0/23"
  asn        = 64512
  ha_enabled = false
}
```

**Default `spokes` value:**
```hcl
{
  dev = {
    cidr        = "10.1.0.0/24"
    environment = "development"
  }
  prod = {
    cidr        = "10.2.0.0/24"
    environment = "production"
  }
  db = {
    cidr        = "10.3.0.0/24"
    environment = "database"
  }
}
```

## Outputs

| Output | Description |
|--------|-------------|
| `transit_gateway_name` | Name of the Aviatrix Transit Gateway |
| `spoke_gateways` | Map of spoke gateway names |
| `test_vm_private_ips` | Private IP addresses of test VMs |
| `smartgroup_uuids` | UUIDs of created SmartGroups |
| `test_scenarios` | Detailed test scenarios with expected results |
| `copilot_verification_steps` | Steps to verify deployment in CoPilot |

## Test Scenarios

### Manual Testing

#### Scenario 1: Dev Attempting to Access DB (SHOULD BE BLOCKED)

This tests the most critical security control - preventing development environments from accessing production databases.

**Steps:**
```bash
# Get the test VM IPs
terraform output test_vm_private_ips

# SSH to Dev VM (use AWS Session Manager or SSH via bastion)
aws ssm start-session --target <dev-vm-instance-id>

# Try to ping DB VM
ping <db-vm-private-ip>
```

**Expected Result:** ❌ Ping fails - traffic is blocked by DCF policy "deny-dev-to-db"

**Verification in CoPilot:**
1. Navigate to **Security > Distributed Cloud Firewall > Monitor**
2. Set time range to **Last 15 minutes**
3. Look for **DENIED** traffic from Dev VM IP → DB VM IP
4. Click the entry to see which policy blocked it

---

#### Scenario 2: Prod Accessing DB (SHOULD BE ALLOWED)

This validates that legitimate production-to-database traffic is permitted.

**Steps:**
```bash
# SSH to Prod VM
aws ssm start-session --target <prod-vm-instance-id>

# Ping DB VM
ping <db-vm-private-ip>
```

**Expected Result:** ✅ Ping succeeds - traffic is allowed by DCF policy "allow-prod-to-db"

**Verification in CoPilot:**
1. Navigate to **Security > Distributed Cloud Firewall > Monitor**
2. Filter for **PERMITTED** traffic
3. See Prod VM IP → DB VM IP with "allow-prod-to-db" policy

---

#### Scenario 3: Dev Accessing Prod (SHOULD BE ALLOWED - ICMP Only)

This demonstrates fine-grained control - allowing diagnostics while blocking other protocols.

**Steps:**
```bash
# SSH to Dev VM
aws ssm start-session --target <dev-vm-instance-id>

# Ping Prod VM (ICMP should work)
ping <prod-vm-private-ip>

# Try TCP connection (should fail)
nc -zv <prod-vm-private-ip> 80
```

**Expected Result:**
- ✅ Ping succeeds (ICMP allowed)
- ❌ TCP connection fails (only ICMP allowed)

---

#### Scenario 4: Prod Attempting to Access Dev (SHOULD BE BLOCKED)

This enforces production isolation from less secure development environments.

**Steps:**
```bash
# SSH to Prod VM
aws ssm start-session --target <prod-vm-instance-id>

# Try to ping Dev VM
ping <dev-vm-private-ip>
```

**Expected Result:** ❌ Ping fails - traffic is blocked by DCF policy "deny-prod-to-dev"

---

### Automated Testing

Run the included test script:

```bash
# Make sure you have AWS CLI configured and jq installed
chmod +x test-scenarios.sh
./test-scenarios.sh
```

The script will:
1. Retrieve all VM IPs from Terraform state
2. Run connectivity tests using AWS Systems Manager
3. Report PASS/FAIL for each scenario
4. Provide CoPilot verification instructions

## Demo Walkthrough

Use this sequence for a compelling demonstration:

### 1. Show the Architecture (2 minutes)

- Open **CoPilot > Topology**
- Show the transit gateway with three spoke connections
- Highlight the three environments (Dev, Prod, DB)

### 2. Explain SmartGroups (3 minutes)

- Navigate to **Security > Distributed Cloud Firewall > SmartGroups**
- Show how instances are automatically grouped by Environment tag
- Explain dynamic membership - new instances automatically join groups

### 3. Show Zero Trust Policies (3 minutes)

- Navigate to **Security > Distributed Cloud Firewall > Rules**
- Walk through each policy:
  - **allow-prod-to-db** (priority 100)
  - **allow-dev-to-prod-read-only** (priority 110, ICMP only)
  - **deny-dev-to-db** (priority 200, **Watch mode enabled**)
  - **deny-prod-to-dev** (priority 210)
  - **default-deny-all** (priority 1000)
- Emphasize priority-based evaluation and default-deny principle

### 4. Live Traffic Testing (5 minutes)

- Run test scenarios (manual or scripted)
- Show **Security > Distributed Cloud Firewall > Monitor** in real-time
- Point out:
  - Allowed traffic in green
  - Denied traffic in red
  - Policy names for each flow
  - Source/destination SmartGroups

### 5. Show the Value (2 minutes)

- No manual security group rules to manage
- Policies follow workloads automatically
- Centralized visibility across all clouds
- Microsegmentation without network redesign
- Audit trail of all traffic (allowed and denied)

**Total Demo Time:** ~15 minutes

## Cleanup

### Standard Destroy

```bash
terraform destroy
```

Type `yes` when prompted to confirm.

**Destroy takes approximately 8-10 minutes.**

### Manual Cleanup (if destroy fails)

If Terraform destroy fails, manually delete resources in this order:

1. **DCF Policies** - In CoPilot: Security > DCF > Rules > Delete all policies
2. **SmartGroups** - In CoPilot: Security > DCF > SmartGroups > Delete all groups
3. **Spoke Gateways** - In CoPilot: Cloud Fabric > Gateways > Delete each spoke
4. **Transit Gateway** - In CoPilot: Cloud Fabric > Gateways > Delete transit
5. **EC2 Instances** - In AWS Console: EC2 > Instances > Terminate all test VMs
6. **VPCs** - In AWS Console: VPC > Your VPCs > Delete all VPCs (this also deletes subnets, route tables, IGWs)

### Verify Cleanup

Confirm no resources remain:

```bash
# Check for remaining VPCs
aws ec2 describe-vpcs \
  --filters "Name=tag:Blueprint,Values=zero-trust-segmentation" \
  --query 'Vpcs[].VpcId'

# Check for remaining instances
aws ec2 describe-instances \
  --filters "Name=tag:Blueprint,Values=zero-trust-segmentation" \
  --query 'Reservations[].Instances[].InstanceId'
```

Both commands should return empty arrays `[]`.

## Troubleshooting

### Issue: Gateway creation times out

**Symptom:** Aviatrix gateway creation fails with timeout error

**Solution:**
1. Verify AWS account is onboarded in the Aviatrix Control Plane
2. Check that the Controller can reach AWS API endpoints
3. Verify sufficient EIP quota in the target region (need 4 EIPs)
4. Check IAM permissions for the Aviatrix IAM roles

### Issue: DCF policies not working

**Symptom:** Traffic is allowed when it should be blocked (or vice versa)

**Solution:**
1. Verify DCF is enabled: **Security > DCF > Configuration** should show "Enabled"
2. Check SmartGroup membership: **Security > DCF > SmartGroups** > click group > verify instances are listed
3. Verify policy priority order - lower numbers are evaluated first
4. Check that test VM instances have correct Environment tags
5. Wait 1-2 minutes for policy changes to propagate

### Issue: Can't SSH to test VMs

**Symptom:** Unable to connect to test VMs for testing

**Solution:**
1. Verify security group allows SSH (port 22) - it should by default
2. Use AWS Systems Manager Session Manager instead of SSH:
   ```bash
   aws ssm start-session --target <instance-id>
   ```
3. Verify the EC2 key pair exists in your AWS account
4. Check that test VMs have private IPs in the correct subnets

### Issue: Test script fails

**Symptom:** `./test-scenarios.sh` returns errors

**Solution:**
1. Install required tools:
   ```bash
   # macOS
   brew install jq awscli

   # Linux
   sudo apt-get install jq awscli  # Debian/Ubuntu
   sudo yum install jq awscli      # RHEL/CentOS
   ```
2. Configure AWS CLI:
   ```bash
   aws configure
   ```
3. Verify SSM agent is running on test VMs (it's installed by default on Amazon Linux 2)
4. Check IAM permissions for SSM:SendCommand

### Issue: High costs

**Symptom:** AWS bill higher than expected

**Solution:**
1. This blueprint costs ~$6/day when running - destroy after testing
2. Check for orphaned Elastic IPs (charged when not attached)
3. Verify NAT Gateways weren't created (they're expensive)
4. Use t3.micro instead of larger instance types

## Tested With

This blueprint is currently tested with:

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 7.2.x |
| Aviatrix Terraform Provider | 3.1.5 |
| Terraform | 1.9.x |
| AWS Provider | 5.80.x |

> **Note**: The blueprint may work with other versions, but these are the versions used for validation.

## Use Cases Demonstrated

This blueprint addresses the following Aviatrix use cases:

1. **Zero Trust Network Segmentation** (Primary) - Enforces least-privilege access between network segments
2. **Prevent Lateral Movement** (Secondary) - Blocks unauthorized east-west traffic between environments
3. **Accelerate DevSecOps Velocity** (Tertiary) - Policy-as-code enables rapid, secure deployments

## Contributing

See the [Contributing Guide](../../CONTRIBUTING.md) for information on how to contribute to this blueprint.

## License

Apache 2.0 - See [LICENSE](../../LICENSE)

---

**Author:** @tatiLogg
**Status:** ✅ Complete and tested
**Last Updated:** February 2026
