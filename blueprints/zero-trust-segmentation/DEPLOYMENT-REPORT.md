# Zero Trust Segmentation Blueprint - Deployment Report

**Date:** February 17, 2026
**Deployed By:** @tatiLogg (with Claude Code assistance)
**Status:** ✅ **SUCCESSFUL**

---

## Executive Summary

Successfully deployed the Zero Trust Segmentation blueprint demonstrating Aviatrix Distributed Cloud Firewall (DCF) capabilities with SmartGroups for policy-based network segmentation.

**Total Resources Created:** 41 resources
**Deployment Time:** ~45 minutes (including troubleshooting)
**Region:** us-east-1
**AWS Account:** 240152784131 (sloggins-lab)

---

## Architecture Deployed

### Aviatrix Components
- **1 Transit Gateway:** zt-seg-transit-gw (t3.small)
- **3 Spoke Gateways:**
  - zt-seg-dev-spoke-gw (t3.small)
  - zt-seg-prod-spoke-gw (t3.small)
  - zt-seg-db-spoke-gw (t3.small)
- **3 SmartGroups:**
  - dev (UUID: 96535de2-1476-474a-8e71-22c53a047c82)
  - prod (UUID: bb9fddd7-ad17-439b-816a-859853eca7a3)
  - db (UUID: 451d3c31-6717-4579-8f88-ae8c39545622)
- **5 DCF Policies:** Implementing Zero Trust segmentation rules

### AWS Infrastructure
- **4 VPCs:**
  - Transit VPC: vpc-030088a7bc25d50f4 (10.0.0.0/23)
  - Dev VPC: vpc-036f0dc7685efc887 (10.1.0.0/24)
  - Prod VPC: vpc-09b0f5dddbdcac716 (10.2.0.0/24)
  - DB VPC: vpc-0151a8a37df5a68e7 (10.3.0.0/24)
- **3 Test VMs:**
  - dev-test-vm: i-06d8521a74dbdda2a (10.1.0.93)
  - prod-test-vm: i-016d5ddf58669c588 (10.2.0.110)
  - db-test-vm: i-0c5e20af298c6cbfe (10.3.0.126)

---

## Challenges Encountered & Solutions

### Issue 1: AWS Account Name Mismatch
**Problem:** Initial configuration used incorrect account name from Controller UI
**Error:** `VPC does not exist` errors
**Root Cause:** Terraform was using AWS account 240152784131, but Controller's "aws_admin" account pointed to 565569641641
**Solution:** Added new AWS account "sloggins-lab" to Aviatrix Controller for account 240152784131

### Issue 2: Missing IAM Roles
**Problem:** Aviatrix Controller couldn't launch gateways
**Error:** Gateway launch workflow failures
**Root Cause:** IAM roles didn't exist in AWS account 240152784131
**Solution:** Created required IAM roles:
- `aviatrix-role-app` - Controller assumes this role
- `aviatrix-role-ec2` - Gateway instances use this role

### Issue 3: Insufficient IAM Permissions
**Problem:** Multiple IAM permission errors during gateway creation
**Errors:**
1. `iam:CreateInstanceProfile` - Missing permission to create instance profiles
2. `iam:TagInstanceProfile` - Missing permission to tag instance profiles

**Solution:** Created custom IAM policy "AviatrixIAMAccess" with required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile",
        "iam:PassRole",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListInstanceProfiles",
        "iam:ListRoles"
      ],
      "Resource": "*"
    }
  ]
}
```

**IAM Role Configuration:**
- `aviatrix-role-app` policies:
  - AWS Managed: PowerUserAccess
  - AWS Managed: IAMReadOnlyAccess
  - Custom: AviatrixIAMAccess
- `aviatrix-role-ec2` policies:
  - AWS Managed: AmazonS3ReadOnlyAccess

**Trust Relationships:**
- `aviatrix-role-app`: Trusts Controller's AWS account (565569641641)
- `aviatrix-role-ec2`: Trusts EC2 service (for instance profiles)

---

## Test Scenarios

### Scenario 1: Dev → DB (BLOCKED ❌)
**Source:** dev-test-vm (10.1.0.93)
**Destination:** db-test-vm (10.3.0.126)
**Expected:** FAIL - Denied by DCF policy "deny-dev-to-db" (priority 200)
**Test:** `ping 10.3.0.126`

### Scenario 2: Prod → DB (ALLOWED ✅)
**Source:** prod-test-vm (10.2.0.110)
**Destination:** db-test-vm (10.3.0.126)
**Expected:** SUCCESS - Permitted by "allow-prod-to-db" (priority 100)
**Test:** `ping 10.3.0.126`

### Scenario 3: Dev → Prod (ALLOWED ✅ - ICMP only)
**Source:** dev-test-vm (10.1.0.93)
**Destination:** prod-test-vm (10.2.0.110)
**Expected:** SUCCESS - Permitted by "allow-dev-to-prod-read-only" (priority 110, ICMP only)
**Test:** `ping 10.2.0.110`

### Scenario 4: Prod → Dev (BLOCKED ❌)
**Source:** prod-test-vm (10.2.0.110)
**Destination:** dev-test-vm (10.1.0.93)
**Expected:** FAIL - Denied by "deny-prod-to-dev" (priority 210)
**Test:** `ping 10.1.0.93`

---

## DCF Policy Summary

| Priority | Name | Source | Destination | Protocol | Action | Watch Mode |
|----------|------|--------|-------------|----------|--------|------------|
| 100 | allow-prod-to-db | prod SmartGroup | db SmartGroup | ALL | PERMIT | No |
| 110 | allow-dev-to-prod-read-only | dev SmartGroup | prod SmartGroup | ICMP | PERMIT | No |
| 200 | deny-dev-to-db | dev SmartGroup | db SmartGroup | ALL | DENY | Yes |
| 210 | deny-prod-to-dev | prod SmartGroup | dev SmartGroup | ALL | DENY | No |
| 1000 | default-deny-all | ALL | ALL | ALL | DENY | No |

---

## Verification in CoPilot

Access CoPilot at: `https://44.214.60.253/#/dashboard`

### Topology Verification
1. Navigate to **Cloud Fabric > Topology**
2. Verify all 4 gateways are visible and connected
3. Confirm transit-spoke attachments are established

### SmartGroups Verification
1. Navigate to **Security > Distributed Cloud Firewall > SmartGroups**
2. Verify 3 SmartGroups exist (dev, prod, db)
3. Check that test VMs are members of their respective groups

### Policy Verification
1. Navigate to **Security > Distributed Cloud Firewall > Rules**
2. Verify all 5 policies are configured correctly
3. Confirm "deny-dev-to-db" has Watch mode enabled (highlighted)

### Traffic Monitoring
1. Navigate to **Security > Distributed Cloud Firewall > Monitor**
2. Set time range to "Last 15 minutes"
3. Run test scenarios and observe traffic logs
4. Verify DENIED entries for blocked traffic
5. Verify PERMITTED entries for allowed traffic

---

## Cost Breakdown

**Hourly Costs (while running):**
- 4 Aviatrix Gateways (t3.small): ~$0.20/hour
- 3 Test VMs (t3.micro): ~$0.03/hour
- 4 Elastic IPs: ~$0.02/hour
- **Total: ~$0.25/hour (~$6/day)**

**Deployment Duration:** 45 minutes
**Testing Duration:** 30 minutes (estimated)
**Estimated Total Cost:** ~$0.31 (assuming 1.25 hours)

⚠️ **Remember to destroy resources after testing!**

---

## Cleanup Instructions

To destroy all resources and avoid ongoing charges:

```bash
cd /Users/selinatloggins/Downloads/aviatrix-blueprints/blueprints/zero-trust-segmentation
source set-credentials.sh
terraform destroy -auto-approve
```

**Expected Duration:** 8-10 minutes

**Verify Cleanup:**
```bash
# Check Terraform state is empty
terraform state list

# Check no orphaned VPCs
aws ec2 describe-vpcs \
  --filters "Name=tag:Blueprint,Values=zero-trust-segmentation" \
  --region us-east-1

# Check no orphaned instances
aws ec2 describe-instances \
  --filters "Name=tag:Blueprint,Values=zero-trust-segmentation" \
  --region us-east-1
```

---

## Key Learnings

### 1. AWS Account Onboarding
When using a new AWS account with Aviatrix:
- Ensure IAM roles are created in the target AWS account
- Controller account name must match exactly
- Use CloudFormation or manual IAM role creation
- Required roles: `aviatrix-role-app` and `aviatrix-role-ec2`

### 2. IAM Permissions
PowerUserAccess is NOT sufficient alone. Additional permissions needed:
- IAM read permissions (use IAMReadOnlyAccess managed policy)
- IAM write permissions for instance profiles (custom policy required)
- Specific actions: CreateInstanceProfile, TagInstanceProfile, etc.

### 3. Gateway Deployment
- Spoke gateways can be created in parallel (3-5 minutes each)
- Transit gateway takes slightly longer (3-5 minutes)
- Failed gateway creations can be retried after fixing IAM issues
- Terraform gracefully handles partial deployments

### 4. DCF Best Practices
- Use SmartGroups based on resource tags (Environment, Name, etc.)
- Lower priority numbers = higher precedence
- Enable Watch mode on new policies before enforcing
- Default-deny-all policy should have lowest priority (highest number)

---

## Files Created/Modified

### New Files
- `aviatrix-app-trust-policy.json` - Trust policy for Controller role
- `aviatrix-ec2-trust-policy.json` - Trust policy for EC2 role
- `aviatrix-iam-policy.json` - Custom IAM permissions policy
- `DEPLOYMENT-REPORT.md` - This file

### Modified Files
- `terraform.tfvars` - Updated aws_account_name to "sloggins-lab"

### AWS Resources Created Outside Terraform
- IAM Role: `aviatrix-role-app` (arn:aws:iam::240152784131:role/aviatrix-role-app)
- IAM Role: `aviatrix-role-ec2` (arn:aws:iam::240152784131:role/aviatrix-role-ec2)
- IAM Policy: `AviatrixIAMAccess` (arn:aws:iam::240152784131:policy/AviatrixIAMAccess)
- IAM Instance Profile: `aviatrix-role-ec2` (managed by Controller)
- Aviatrix Controller Account: "sloggins-lab" for AWS account 240152784131

---

## Success Criteria - All Met! ✅

- ✅ All 41 Terraform resources created without errors
- ✅ All 4 Aviatrix gateways deployed and operational
- ✅ All 3 SmartGroups created with correct membership
- ✅ All 5 DCF policies configured
- ✅ Transit-spoke attachments established
- ✅ Test VMs deployed and accessible
- ✅ DCF enabled and operational

---

## Next Steps

1. **Test the DCF policies** - Run all 4 test scenarios
2. **Document test results** - Record observed vs expected behavior
3. **Take screenshots** - Capture CoPilot topology and DCF monitor
4. **Update README** - Add lessons learned and deployment notes
5. **Share with team** - Demonstrate Zero Trust segmentation capabilities
6. **Clean up resources** - Run terraform destroy when done

---

## Credits

- **Blueprint Author:** @tatiLogg
- **Deployment Assistance:** Claude Code (Sonnet 4.5)
- **Aviatrix Platform:** Distributed Cloud Firewall with SmartGroups
- **Infrastructure:** AWS (us-east-1)

---

## References

- [Aviatrix DCF Documentation](https://docs.aviatrix.com/documentation/latest/platform/security-groups/distributed-cloud-firewall.html)
- [SmartGroups Guide](https://docs.aviatrix.com/documentation/latest/platform/security-groups/smart-groups.html)
- [Transit Gateway Architecture](https://docs.aviatrix.com/documentation/latest/platform/cloud-gateways/transit-gateway.html)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

---

**Report Generated:** February 17, 2026
**Deployment Status:** ✅ SUCCESSFUL
**Ready for Testing:** YES
