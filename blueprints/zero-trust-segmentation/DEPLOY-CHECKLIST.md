# Deployment Checklist - Zero Trust Segmentation Blueprint

Use this checklist to ensure a successful deployment and test.

## Pre-Deployment (5 minutes)

### 1. Verify Prerequisites

- [ ] **Aviatrix Controller** is accessible and running
- [ ] **AWS account** is onboarded in Aviatrix Controller
- [ ] **AWS CLI** is configured with valid credentials
- [ ] **EC2 key pair** exists in target AWS region
- [ ] **Terraform** v1.5+ is installed
- [ ] You know your **AWS account name** (as configured in Controller)

**Quick verification:**
```bash
# Check Terraform
terraform version

# Check AWS credentials
aws sts get-caller-identity

# Check AWS key pairs
aws ec2 describe-key-pairs --region us-east-1

# Test Controller connectivity
curl -k https://<controller-ip>/v1/api
```

### 2. Check AWS Quotas

- [ ] At least **4 Elastic IPs** available in region
- [ ] VPC limit allows for 4+ VPCs
- [ ] EC2 instance limit allows for 3+ t3.micro/t3.small instances

**Check quotas:**
```bash
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0263D0A3 \
  --region us-east-1
```

### 3. Estimate Costs

**Expected costs while running:**
- 4 Aviatrix gateways (t3.small): ~$0.20/hour
- 3 EC2 test VMs (t3.micro): ~$0.03/hour
- 4 Elastic IPs: ~$0.02/hour
- **Total: ~$0.25/hour (~$6/day)**

**Plan to destroy:** Don't leave running overnight unless needed!

---

## Deployment (15 minutes)

### 4. Set Environment Variables

```bash
cd /Users/selinatloggins/Downloads/aviatrix-blueprints/blueprints/zero-trust-segmentation

# Aviatrix Controller
export AVIATRIX_CONTROLLER_IP="<your-controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<your-password>"

# AWS (if not using AWS CLI profile)
export AWS_REGION="us-east-1"
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY should already be set
```

### 5. Configure Variables

```bash
# Copy template
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
# REQUIRED:
#   - aws_account_name (must match Controller exactly)
#   - test_vm_key_name (must exist in your AWS account)
```

**Critical:** Your `terraform.tfvars` should look like:
```hcl
aws_account_name      = "your-account-name-in-controller"
aws_region            = "us-east-1"
name_prefix           = "zt-seg"
test_vm_key_name      = "your-existing-keypair"
test_vm_instance_type = "t3.micro"
```

### 6. Initialize Terraform

```bash
terraform init
```

- [ ] Initialization successful
- [ ] Providers downloaded (Aviatrix, AWS)

### 7. Plan Deployment

```bash
terraform plan
```

**Expected resources:** ~42 resources to create

Review the plan and verify:
- [ ] 1 transit gateway
- [ ] 3 spoke gateways
- [ ] 4 VPCs
- [ ] 3 EC2 instances
- [ ] 3 SmartGroups
- [ ] DCF policies

### 8. Deploy

```bash
terraform apply
```

Type `yes` when prompted.

**Expected duration:** 10-15 minutes

Watch for:
- [ ] Transit gateway created (~5 minutes)
- [ ] Spoke gateways created (~3 minutes each, parallel)
- [ ] Test VMs launched
- [ ] DCF enabled
- [ ] SmartGroups created
- [ ] Policies configured

**If errors occur:** Note the error message and check Troubleshooting section in README.md

### 9. Save Outputs

```bash
terraform output > deployment-outputs.txt
terraform output -json > deployment-outputs.json

# View test scenarios
terraform output test_scenarios
```

- [ ] Outputs saved
- [ ] Test VM IPs noted

---

## Testing (10 minutes)

### 10. Verify in CoPilot

Open CoPilot and check:

**Topology:**
- [ ] Navigate to **Cloud Fabric > Topology**
- [ ] Transit gateway visible
- [ ] 3 spoke gateways connected to transit
- [ ] Architecture matches diagram

**SmartGroups:**
- [ ] Navigate to **Security > Distributed Cloud Firewall > SmartGroups**
- [ ] 3 SmartGroups visible: `zt-seg-dev-smartgroup`, `zt-seg-prod-smartgroup`, `zt-seg-db-smartgroup`
- [ ] Click each group and verify test VMs are members

**Policies:**
- [ ] Navigate to **Security > Distributed Cloud Firewall > Rules**
- [ ] 5 policies visible in priority order
- [ ] `deny-dev-to-db` has Watch mode enabled (highlighted)

### 11. Run Automated Tests

```bash
# If you have AWS Systems Manager configured
chmod +x test-scenarios.sh
./test-scenarios.sh
```

**Expected results:**
- [ ] Scenario 1: Dev → DB: **BLOCKED** ✓
- [ ] Scenario 2: Prod → DB: **ALLOWED** ✓
- [ ] Scenario 3: Dev → Prod: **ALLOWED** ✓
- [ ] Scenario 4: Prod → DB: **BLOCKED** ✓

### 12. Manual Testing (Alternative)

If automated testing doesn't work, test manually:

```bash
# Get VM IPs
DEV_IP=$(terraform output -json test_vm_private_ips | jq -r '.dev')
PROD_IP=$(terraform output -json test_vm_private_ips | jq -r '.prod')
DB_IP=$(terraform output -json test_vm_private_ips | jq -r '.db')

DEV_ID=$(terraform output -json test_vm_ids | jq -r '.dev')
PROD_ID=$(terraform output -json test_vm_ids | jq -r '.prod')
DB_ID=$(terraform output -json test_vm_ids | jq -r '.db')

echo "Dev VM:  $DEV_ID ($DEV_IP)"
echo "Prod VM: $PROD_ID ($PROD_IP)"
echo "DB VM:   $DB_ID ($DB_IP)"

# SSH via Systems Manager
aws ssm start-session --target $DEV_ID

# Once connected to Dev VM, try pinging DB
ping $DB_IP
# Should FAIL (timeout or no response)

# Exit and try Prod → DB
aws ssm start-session --target $PROD_ID
ping $DB_IP
# Should SUCCEED
```

### 13. Verify in CoPilot Monitor

- [ ] Navigate to **Security > Distributed Cloud Firewall > Monitor**
- [ ] Set time range: **Last 15 minutes**
- [ ] See traffic entries (both PERMITTED and DENIED)
- [ ] Verify DENIED traffic from Dev → DB
- [ ] Verify PERMITTED traffic from Prod → DB

### 14. Take Screenshots (Optional)

For documentation or demo:
- [ ] Topology view
- [ ] SmartGroups with members
- [ ] Policies list
- [ ] Monitor showing blocked traffic

---

## Post-Testing (10 minutes)

### 15. Document Results

Create a test report:
```bash
cat > test-report.txt << EOF
Zero Trust Segmentation Blueprint - Test Report
Date: $(date)
Tester: @tatiLogg

Deployment:
- Duration: XX minutes
- Resources created: $(terraform state list | wc -l)
- Errors: None / [describe any issues]

Test Results:
- Scenario 1 (Dev → DB): PASS/FAIL
- Scenario 2 (Prod → DB): PASS/FAIL
- Scenario 3 (Dev → Prod): PASS/FAIL
- Scenario 4 (Prod → Dev): PASS/FAIL

CoPilot Verification:
- Topology: VERIFIED
- SmartGroups: VERIFIED
- Policies: VERIFIED
- Monitor: VERIFIED

Notes:
[Any observations, issues, or improvements]
EOF
```

### 16. Destroy Resources

**IMPORTANT:** Don't forget to destroy to avoid charges!

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected duration:** 8-10 minutes

Watch for:
- [ ] Spoke gateways deleted
- [ ] Transit gateway deleted
- [ ] Test VMs terminated
- [ ] VPCs deleted
- [ ] All resources cleaned up

### 17. Verify Cleanup

```bash
# Check for remaining resources
terraform state list
# Should be empty

# Check AWS for orphaned resources
aws ec2 describe-vpcs \
  --filters "Name=tag:Blueprint,Values=zero-trust-segmentation" \
  --region us-east-1

aws ec2 describe-instances \
  --filters "Name=tag:Blueprint,Values=zero-trust-segmentation" \
  --region us-east-1
```

- [ ] No Terraform state remaining
- [ ] No VPCs remaining
- [ ] No EC2 instances remaining
- [ ] No orphaned Elastic IPs

---

## Troubleshooting

### Gateway creation timeout
- Check Controller can reach AWS
- Verify IAM roles and permissions
- Check EIP quota

### DCF policies not enforcing
- Wait 1-2 minutes for propagation
- Verify DCF is enabled
- Check SmartGroup membership
- Verify instance tags are correct

### Can't SSH to test VMs
- Use AWS Systems Manager instead
- Check security group rules
- Verify VPC networking

### High costs
- Remember to destroy after testing
- Check for orphaned resources
- Use t3.micro for test VMs

---

## Success Criteria

Your deployment is successful if:
- ✅ All 42 resources created without errors
- ✅ All 4 test scenarios show expected results
- ✅ CoPilot shows topology, SmartGroups, and policies correctly
- ✅ Monitor shows traffic being allowed/denied per policies
- ✅ Destroy completes successfully with no orphaned resources

---

## Next Steps After Successful Test

1. Update README.md with any corrections
2. Add actual architecture diagram (replace placeholder)
3. Commit test report and screenshots
4. Create PR to AviatrixSystems repository
5. Share with team!

---

**Estimated Total Time:** ~40 minutes (deploy + test + destroy)
**Estimated Cost:** ~$0.17 (40 minutes at $0.25/hour)
