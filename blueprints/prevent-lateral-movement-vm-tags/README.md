# Prevent Lateral Movement - VM Tags

Deploy **tag-based lateral movement prevention** in 15 minutes using Aviatrix Distributed Cloud Firewall (DCF) and SmartGroups. This blueprint enforces tag-based network segmentation across AWS VPCs — preventing lateral movement, accelerating compliance, and eliminating security group sprawl.

> [!TIP]
> **🤖 Optimized for Claude Code** — Run `/deploy-blueprint prevent-lateral-movement-vm-tags` for AI-guided deployment with prerequisite checks, or `/analyze-blueprint prevent-lateral-movement-vm-tags` for resource and cost details. [Get Claude Code](https://claude.ai/code)

---

## Prerequisites

### Aviatrix Control Plane

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **Aviatrix Controller** | v7.1+ | Must be deployed, accessible, and have your AWS account onboarded under **Accounts > Access Accounts** |
| **Aviatrix CoPilot** | Required | Used for topology visualization, DCF Monitor, and SmartGroup verification |
| **DCF** | Enabled automatically | This blueprint enables DCF automatically via Terraform (`aviatrix_config_feature`). No manual step required. DCF will NOT be disabled on destroy — this is intentional to avoid disrupting other workloads. |

### Local Tools

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.5 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| **AWS CLI** | v2 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS authentication and EC2 Instance Connect |

### Test VM Security Groups

The test VMs are deployed in private subnets with no public IP addresses. SSH access is provided through EC2 Instance Connect Endpoint (EICE) — an AWS-managed tunnel that routes traffic from your terminal through AWS's network into the private subnet, with no bastion host, VPN, or key pair required.

Because EICE injects traffic from inside the VPC (from the RFC-1918 address space), the test VM security groups must explicitly allow it:

| Rule | Protocol | Port | Source | Purpose |
|------|----------|------|--------|---------|
| Inbound | TCP | 22 | `10.0.0.0/8` | Allows EICE tunnel to reach the instance |

> **Note:** Without this rule, `aws ec2-instance-connect ssh` will establish the EICE tunnel successfully but the TCP handshake to port 22 on the instance will be silently dropped — resulting in a "Connection timed out" error. This is the most common SSH failure when using EICE with private instances.

### AWS IAM Permissions

Two IAM roles must exist in your AWS account **before** deploying. The Aviatrix Controller uses these roles to launch and manage gateways.

| Role | Policies Required | Purpose |
|------|------------------|---------|
| `aviatrix-role-app` | `PowerUserAccess` + `IAMReadOnlyAccess` + custom `AviatrixIAMAccess`* | Controller assumes this role to manage AWS resources |
| `aviatrix-role-ec2` | `AmazonS3ReadOnlyAccess` | Attached to gateway EC2 instances for software updates |

**\*Custom `AviatrixIAMAccess` policy actions required:**
`iam:CreateInstanceProfile`, `iam:DeleteInstanceProfile`, `iam:AddRoleToInstanceProfile`, `iam:RemoveRoleFromInstanceProfile`, `iam:GetInstanceProfile`, `iam:TagInstanceProfile`, `iam:UntagInstanceProfile`, `iam:PassRole`, `iam:GetRole`, `iam:GetRolePolicy`, `iam:ListInstanceProfiles`, `iam:ListRoles`

> **Trust relationships:** `aviatrix-role-app` must trust the AWS account where your Controller runs (`arn:aws:iam::<controller-account-id>:root`). `aviatrix-role-ec2` must trust the EC2 service (`ec2.amazonaws.com`).
>
> If these roles don't exist, see the [Aviatrix AWS account onboarding documentation](https://legacy.docs.aviatrix.com/documentation/latest/getting-started/onboard-account-controller-aws.html).

### Environment Variables

Set these before running Terraform:

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<your-controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<your-password>"

# AWS credentials (choose one method)
# Option A: Environment variables
export AWS_ACCESS_KEY_ID="<your-access-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret-key>"
export AWS_DEFAULT_REGION="us-east-1"

# Option B: AWS CLI profile
export AWS_PROFILE="<your-profile-name>"
```

### Verify Prerequisites

```bash
# Confirm AWS credentials are active
aws sts get-caller-identity

# EC2 key pair (optional — EC2 Instance Connect does not require a key pair)
# Only needed if you set test_vm_key_name in terraform.tfvars
# aws ec2 describe-key-pairs --region us-east-1 --query 'KeyPairs[].KeyName'

# Confirm sufficient Elastic IP quota (need 4 free EIPs)
aws ec2 describe-account-attributes --attribute-names max-elastic-ips --query 'AccountAttributes[0].AttributeValues[0].AttributeValue'
aws ec2 describe-addresses --query 'Addresses | length(@)'
# Available EIPs = quota - current count. Must be >= 4.

# Confirm sufficient VPC quota (need 4 free VPCs — default limit is 5/region)
aws ec2 describe-account-attributes --attribute-names max-instances --region us-east-1
aws ec2 describe-vpcs --query 'Vpcs | length(@)'
# Available VPCs = quota - current count. Must be >= 4.

# Confirm sufficient IGW quota (need 4 — default limit is 5/region, same as VPC)
aws ec2 describe-internet-gateways --query 'InternetGateways | length(@)'
```

Also confirm in the Aviatrix Controller that your AWS account is onboarded under **Accounts > Access Accounts** before proceeding. Gateway creation will time out if the account is not onboarded.

---

## Architecture Overview

![Architecture Diagram](architecture.svg)

> **For a detailed breakdown of every component and how they connect, see [ARCHITECTURE.md](ARCHITECTURE.md).**

This blueprint deploys the following into a single AWS region:

| Component | Count | Description |
|-----------|-------|-------------|
| Aviatrix Transit Gateway | 1 | Central hub connecting all spokes |
| Aviatrix Spoke Gateways | 3 | One each for Dev, Prod, and DB VPCs |
| AWS VPCs | 4 | Transit + Dev + Prod + DB |
| EC2 Test VMs | 3 | One per spoke VPC for connectivity testing |
| EC2 Instance Connect Endpoints (EICE) | 3 | AWS-managed tunnel enabling SSH to VMs in private subnets — no bastion, no VPN, no public IP, no key pair required. EICE injects traffic from inside the VPC, bridging your terminal to the private instance securely. |
| DCF SmartGroups | 3 | Tag-based groups: dev, prod, db |
| DCF Policies | 5 | Default-deny rules — see table below |
| Gatus Dashboard | 1 | Live connectivity dashboard (ALB-exposed, browser accessible) |

**DCF Policies configured:**

| Priority | Policy | Action | Watch | What it proves |
|----------|--------|--------|-------|----------------|
| 100 | `allow-prod-to-db` | PERMIT | | Legitimate business traffic flows |
| 110 | `allow-dev-to-prod-read-only` | PERMIT (ICMP only) | | Protocol-level granularity |
| 200 | `deny-dev-to-db` | DENY | ✓ | Lateral movement from dev to production data blocked — highlighted in CoPilot DCF Monitor when it fires |
| 210 | `deny-prod-to-dev` | DENY | | Compromised prod cannot reach dev |
| 1000 | `default-deny-all` | DENY | | Default-deny — no implicit trust |

---

## Resources Created

| Resource | Quantity | Estimated Cost/Hour |
|----------|----------|---------------------|
| Aviatrix Transit Gateway (t3.small) | 1 | $0.05 |
| Aviatrix Spoke Gateways (t3.small) | 3 | $0.15 |
| EC2 Test VMs (t3.micro) | 3 | $0.03 |
| EC2 Gatus Instance (t3.micro) | 1 | $0.01 |
| Application Load Balancer | 1 | $0.02 |
| Elastic IPs | 4 | $0.02 |
| EC2 Instance Connect Endpoints | 3 | Free |
| VPCs, Subnets, Route Tables, IGWs | Multiple | Free |
| DCF SmartGroups + Policies | 3 + 5 | Free |

**Total: ~$0.28/hour (~$6.70/day)**

> Destroy resources after testing to avoid ongoing charges.

---

## Quickstart

```bash
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/prevent-lateral-movement-vm-tags

# Set credentials (see Prerequisites)
export AVIATRIX_CONTROLLER_IP="<your-controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<your-password>"
export AWS_PROFILE="<your-profile>"

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform apply
```

**Total deployment time: ~15 minutes**

---

## Deployment Guide

### Step 1: Clone and Navigate

```bash
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/prevent-lateral-movement-vm-tags
```

### Step 2: Configure Variables

```bash
# Step 2a: Set credentials as environment variables
export AVIATRIX_CONTROLLER_IP="<your-controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<your-password>"

# AWS credentials (choose one)
export AWS_PROFILE="<your-profile>"        # Option A: named profile
# export AWS_ACCESS_KEY_ID="..."           # Option B: access keys
# export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"     # Required if not set in your AWS CLI config
```

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_account_name      = "my-aws-account"  # Must match account name in Controller > Accounts
aws_region            = "us-east-1"
name_prefix           = "plm"
test_vm_instance_type = "t3.micro"
```

> **Advanced options:** The `terraform.tfvars.example` file contains commented-out blocks for overriding the transit gateway CIDR/ASN/HA setting and spoke VPC CIDRs. The defaults work for most deployments — only uncomment if you need to change CIDRs or enable transit HA.

### Step 3: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted. **Deployment takes approximately 10–15 minutes.**

### Step 4: Open the Gatus Live Dashboard

```bash
terraform output gatus_dashboard_url
```

Open the URL in a browser. Wait 3–5 minutes after apply for the Gatus instance to boot and pass ALB health checks. If you see **503**, wait 60 seconds and refresh.

> **Note:** The Gatus "Prod → DB" tile may stay RED for the first 3–5 minutes after deployment. This is normal — the Aviatrix Controller takes a few minutes to index new EC2 instances into SmartGroups. Once the `plm-prod-smartgroup` includes the Gatus instance, the PERMIT rule kicks in and the tile turns GREEN. Check SmartGroup membership in CoPilot > Security > DCF > SmartGroups.

**What you'll see:**

| Tile | Status | What it proves |
|------|--------|----------------|
| Prod → DB ICMP (ALLOWED) | 🟢 Healthy | `allow-prod-to-db` policy permitting legitimate traffic |
| Prod → DB TCP:5432 (ALLOWED) | 🟢 Healthy | `allow-prod-to-db` permitting database port traffic end-to-end |
| Prod → Dev ICMP (BLOCKED) | 🔴 Unhealthy | `deny-prod-to-dev` blocking lateral movement |
| Prod → Dev TCP:22 (BLOCKED) | 🔴 Unhealthy | `default-deny-all` catching everything else |

Dashboard probes update every 10 seconds. Leave it open during testing — live DCF enforcement is visible without any commands.

### Step 5: Verify in CoPilot

1. Log into your CoPilot
2. **Cloud Fabric > Topology** — verify Transit + 3 Spoke gateways are visible and connected
3. **Groups > SmartGroups** — verify 3 SmartGroups exist with correct VM membership
4. **Security > Distributed Cloud Firewall > Policies** — verify all 5 policies are configured
5. **Security > Distributed Cloud Firewall > Monitor** — use this during test scenarios (Step 7) to see live PERMITTED/DENIED entries. The log will be empty until traffic flows through the gateways.
6. **Monitor > FlowIQ** — shows general NetFlow data across all gateways; useful for traffic visibility beyond DCF policy logs

---

## Test Scenarios

### Automated — Gatus Dashboard (from Prod)

| # | Flow | Protocol | Expected | DCF Policy |
|---|------|----------|----------|------------|
| G1 | Prod → DB | ICMP | 🟢 GREEN | `allow-prod-to-db` (priority 100) |
| G2 | Prod → Dev | ICMP | 🔴 RED | `deny-prod-to-dev` (priority 210) |
| G3 | Prod → Dev | TCP:22 | 🔴 RED | `default-deny-all` (priority 1000) |
| G4 | Prod → DB | TCP:5432 | 🟢 GREEN | `allow-prod-to-db` (priority 100) |

### Manual — SSH Testing

Connect to any test VM using EC2 Instance Connect Endpoint (EICE). The test VMs are in private subnets with no public IP addresses — EICE is what makes SSH possible without a bastion host or VPN. It creates a secure tunnel from your terminal through AWS's network directly into the private subnet. The `--connection-type eice` flag is required to tell the AWS CLI to route through the endpoint rather than attempting a direct connection (which would fail with no public IP).

```bash
# Get ready-to-run SSH commands for all VMs
terraform output ssh_commands

# Example output:
# dev  = "aws ec2-instance-connect ssh --instance-id i-0abc123 --region us-east-1 --connection-type eice"
# prod = "aws ec2-instance-connect ssh --instance-id i-0def456 --region us-east-1 --connection-type eice"
# db   = "aws ec2-instance-connect ssh --instance-id i-0ghi789 --region us-east-1 --connection-type eice"
```

| # | Flow | Protocol | Expected | DCF Policy |
|---|------|----------|----------|------------|
| M1 | Dev → DB | ICMP | ❌ BLOCKED | `deny-dev-to-db` (priority 200) |
| M2 | Prod → DB | ICMP | ✅ ALLOWED | `allow-prod-to-db` (priority 100) |
| M3a | Dev → Prod | ICMP | ✅ ALLOWED | `allow-dev-to-prod-read-only` (priority 110) |
| M3b | Dev → Prod | TCP | ❌ BLOCKED | `default-deny-all` (priority 1000) |
| M4 | Prod → Dev | ICMP | ❌ BLOCKED | `deny-prod-to-dev` (priority 210) |

> **Test label note:** `M3a` (Dev → Prod ICMP, ALLOWED) corresponds to **Test 2a** in the demo walkthrough script — they refer to the same test.

**Run a test:**

```bash
# ICMP test
ping <target-private-ip>

# TCP test (wait up to 10s for timeout — timeout means DCF blocked it)
nc -zv -w 10 <target-private-ip> 22
```

**Policy coverage matrix:**

| Priority | Policy | Gatus | Manual |
|----------|--------|-------|--------|
| 100 | `allow-prod-to-db` | ✅ G1 | ✅ M2 |
| 110 | `allow-dev-to-prod-read-only` | ❌ gap* | ✅ M3a |
| 200 | `deny-dev-to-db` | ❌ gap* | ✅ M1 |
| 210 | `deny-prod-to-dev` | ✅ G2 | ✅ M4 |
| 1000 | `default-deny-all` | ✅ G3 | ✅ M3b |

*Gatus runs in the prod spoke and cannot initiate probes from dev. Policies 110 and 200 require manual SSH testing from the dev VM.

---

## Walkthrough

Use this sequence to walk through how the blueprint prevents lateral movement (~15 minutes):

### 1. The Problem (2 min)
> *"Traditional security groups create flat networks — once two workloads are connected, everything can talk to everything. 83% of ransomware attacks succeed through lateral movement across unsegmented networks."*

**Show:** CoPilot > Topology — the hub-and-spoke architecture visually separating Dev, Prod, and DB.

### 2. SmartGroups: Automated Segmentation Boundaries (3 min)
> *"New workloads tagged `Environment=production` instantly inherit segmentation policies — no manual security group updates, no tickets, no delay."*

**Show:** Security > DCF > SmartGroups — click into `dev-smartgroup`, show the `Environment=development` selector.

### 3. Policies: Default-Deny + Explicit Allow (3 min)
**Show:** Security > DCF > Rules — walk through the policy list:
- Priority 100 (`allow-prod-to-db`): *"Explicit allow for legitimate business need"*
- Priority 200 (`deny-dev-to-db`): *"DCF blocks dev from production data — prevents lateral movement"*
- Priority 1000 (`default-deny-all`): *"No implicit trust — everything is blocked unless explicitly permitted"*

### 4. Live Testing: Proving it Works (5 min)
**Show the Gatus dashboard** — two red tiles proving lateral movement is blocked in real time.

Then SSH from dev VM and try to ping the DB:
```bash
ping <db-vm-private-ip>  # Times out — DCF blocked it
```

**Show CoPilot > DCF > Monitor** — the DENIED entry appears with source, destination, and policy name.

### 5. Business Value (2 min)
| Outcome | Traditional | Aviatrix DCF |
|---------|-------------|---------------------|
| Deployment time | 2–4 weeks (manual SG rules) | ⚡ 15 minutes |
| Lateral movement | ❌ Flat network | ✅ Blocked |
| Policy management | Manual per-workload | ✅ Tag-based automation |
| Compliance audit trail | VPC Flow Logs (delayed) | ✅ Real-time DCF Monitor |

---

## Cleanup

### Destroy Notes

This blueprint does not manage DCF enable/disable — only SmartGroups and policies. `terraform destroy` removes only the resources this blueprint created. Your Controller's DCF configuration remains untouched.

### Destroy

```bash
terraform destroy
```

Type `yes` when prompted. **Destroy takes approximately 8–10 minutes.**

### Manual Cleanup (if destroy fails)

Delete resources in this order:

1. **DCF Policies** — CoPilot: Security > DCF > Rules > delete all policies
2. **SmartGroups** — CoPilot: Security > DCF > SmartGroups > delete all groups
3. **Spoke Gateways** — CoPilot: Cloud Fabric > Gateways > delete each spoke
4. **Transit Gateway** — CoPilot: Cloud Fabric > Gateways > delete transit
5. **EC2 Instances** — AWS Console: EC2 > Instances > terminate all VMs
6. **VPCs** — AWS Console: VPC > Your VPCs > delete all VPCs

### Verify Cleanup

```bash
# Check for remaining VPCs
aws ec2 describe-vpcs \
  --filters "Name=tag:Blueprint,Values=prevent-lateral-movement-vm-tags" \
  --query 'Vpcs[].VpcId'

# Check for remaining instances
aws ec2 describe-instances \
  --filters "Name=tag:Blueprint,Values=prevent-lateral-movement-vm-tags" \
  --query 'Reservations[].Instances[].InstanceId'
```

Both commands should return `[]`.

---

## Troubleshooting

**Gateway creation times out**
- Verify AWS account is onboarded in the Controller under **Accounts > Access Accounts**
- Confirm `aviatrix-role-app` and `aviatrix-role-ec2` IAM roles exist in your AWS account
- Check sufficient EIP quota (need 4 free EIPs): `aws ec2 describe-addresses --query 'Addresses | length(@)'`

**DCF policies not enforcing**
- Verify DCF is enabled: Controller > Security > DCF > Configuration
- Check SmartGroup membership: Security > DCF > SmartGroups > click group > confirm VMs are listed
- Ensure test VMs have the correct `Environment` tag (verify in EC2 console)
- Wait 1–2 minutes for policy changes to propagate

**Gatus dashboard shows 503**
- ALB health check hasn't passed yet — wait 60 seconds and refresh
- The Gatus EC2 instance needs ~3–5 minutes to boot, pull Docker image, and start the container

**`terraform destroy` fails with DCF error**
- This should not occur as this blueprint does not manage DCF enable/disable
- If it does, verify you are running the latest version of the blueprint

**Can't SSH to test VMs**
- Use EC2 Instance Connect: `aws ec2-instance-connect ssh --instance-id <id> --region us-east-1 --connection-type eice`
- All three VMs (dev, prod, db) have EC2 Instance Connect Endpoints — no key pair or bastion needed
- The `--connection-type eice` flag is required because the VMs are in private subnets with no public IPs — without it, the CLI attempts a direct connection and fails
- Run `terraform output ssh_commands` to get the exact ready-to-run command for each VM

---

## Tested With

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 8.2.x |
| Aviatrix Terraform Provider | 8.2.x |
| Terraform | 1.9.x |
| AWS Provider | 6.32.x |

> Provider version must match your Controller version. See the [full compatibility matrix](https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs/guides/release-compatibility).

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `aws_account_name` | Aviatrix Access Account name for AWS (must match name in Controller > Accounts) | `string` | — | ✅ Yes |
| `aws_region` | AWS region for deployment | `string` | `"us-east-1"` | No |
| `name_prefix` | Prefix applied to all resource names | `string` | `"plm"` | No |
| `test_vm_instance_type` | EC2 instance type for test VMs | `string` | `"t3.micro"` | No |
| `test_vm_key_name` | EC2 key pair name for SSH. Optional — EICE is the primary access method and does not require a key pair | `string` | `null` | No |
| `gatus_allowed_cidr` | CIDR allowed to reach the Gatus dashboard ALB on port 80. Restrict to your IP for demos (e.g. `"1.2.3.4/32"`) | `string` | `"0.0.0.0/0"` | No |
| `transit_gateway` | Transit gateway configuration object: `cidr`, `asn`, `ha_enabled` | `object` | `cidr="10.0.0.0/23"`, `asn=64512`, `ha_enabled=false` | No |
| `spokes` | Map of spoke configurations. Each spoke requires `cidr` and `environment` (used as the AWS tag value for SmartGroup classification) | `map(object)` | dev `10.1.0.0/24`, prod `10.2.0.0/24`, db `10.3.0.0/24` | No |

---

## Outputs

| Name | Description |
|------|-------------|
| `gatus_dashboard_url` | URL of the live Gatus connectivity dashboard (available ~2–3 min after apply) |
| `ssh_commands` | Ready-to-run `aws ec2-instance-connect ssh` commands for each test VM |
| `test_vm_private_ips` | Map of private IP addresses for each test VM (`dev`, `prod`, `db`) |
| `test_vm_ids` | Map of EC2 instance IDs for each test VM |
| `spoke_gateways` | Map of Aviatrix spoke gateway names |
| `spoke_vpc_ids` | Map of AWS VPC IDs for each spoke |
| `transit_gateway_name` | Name of the Aviatrix Transit Gateway |
| `transit_gateway_id` | ID of the Aviatrix Transit Gateway |
| `smartgroup_uuids` | UUIDs of the three DCF SmartGroups (`dev`, `prod`, `db`) |
| `test_scenarios` | Pre-built test scenario descriptions with source, destination, expected result, and test command |
| `copilot_verification_steps` | Ordered checklist for verifying the deployment in CoPilot |

---

## Contributing

See the [Contributing Guide](../../CONTRIBUTING.md).

## License

Apache 2.0 — see [LICENSE](../../LICENSE).
