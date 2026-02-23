# AWS IAM Setup Guide for Aviatrix Blueprints

This guide provides step-by-step instructions for setting up AWS IAM roles and permissions required for Aviatrix gateway deployments.

---

## Prerequisites

- AWS CLI configured with administrator access
- Aviatrix Controller deployed and accessible
- Controller's AWS account number (found in CoPilot > Settings > Accounts)

---

## Quick Setup (5 minutes)

### Step 1: Set Variables

```bash
# Your AWS account number (where gateways will be deployed)
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Controller's AWS account number (where Controller is running)
CONTROLLER_ACCOUNT="<controller-aws-account-number>"

echo "Your AWS Account: $AWS_ACCOUNT"
echo "Controller Account: $CONTROLLER_ACCOUNT"
```

### Step 2: Create Trust Policy Files

**File: `aviatrix-app-trust-policy.json`**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${CONTROLLER_ACCOUNT}:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {}
    }
  ]
}
```

**File: `aviatrix-ec2-trust-policy.json`**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**File: `aviatrix-iam-policy.json`**
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

### Step 3: Create IAM Roles

```bash
# Create aviatrix-role-app
aws iam create-role \
  --role-name aviatrix-role-app \
  --assume-role-policy-document file://aviatrix-app-trust-policy.json \
  --description "Aviatrix Controller access role"

# Create aviatrix-role-ec2
aws iam create-role \
  --role-name aviatrix-role-ec2 \
  --assume-role-policy-document file://aviatrix-ec2-trust-policy.json \
  --description "Aviatrix Gateway EC2 instance role"
```

### Step 4: Attach Policies to aviatrix-role-app

```bash
# Attach PowerUserAccess (for AWS resource management)
aws iam attach-role-policy \
  --role-name aviatrix-role-app \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# Attach IAMReadOnlyAccess (for IAM read operations)
aws iam attach-role-policy \
  --role-name aviatrix-role-app \
  --policy-arn arn:aws:iam::aws:policy/IAMReadOnlyAccess

# Create and attach custom IAM policy
aws iam create-policy \
  --policy-name AviatrixIAMAccess \
  --policy-document file://aviatrix-iam-policy.json \
  --description "Aviatrix IAM permissions for managing instance profiles"

# Get the policy ARN and attach it
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT}:policy/AviatrixIAMAccess"
aws iam attach-role-policy \
  --role-name aviatrix-role-app \
  --policy-arn $POLICY_ARN
```

### Step 5: Attach Policies to aviatrix-role-ec2

```bash
# Attach S3 read access (for gateway software updates)
aws iam attach-role-policy \
  --role-name aviatrix-role-ec2 \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name aviatrix-role-ec2

# Add role to instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name aviatrix-role-ec2 \
  --role-name aviatrix-role-ec2
```

### Step 6: Add Account to Aviatrix Controller

**Option A: Using Controller API**

```bash
# Set Controller credentials
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"

# Get session token
CID=$(curl -k -s -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
  -d "action=login&username=${AVIATRIX_USERNAME}&password=${AVIATRIX_PASSWORD}" | \
  python3 -c "import sys, json; print(json.load(sys.stdin)['CID'])")

# Add AWS account
curl -k -s -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
  -d "action=setup_account_profile&CID=${CID}&account_name=<account-name>&cloud_type=1&aws_account_number=${AWS_ACCOUNT}&aws_iam=true&aws_role_arn=arn:aws:iam::${AWS_ACCOUNT}:role/aviatrix-role-app&aws_role_ec2=arn:aws:iam::${AWS_ACCOUNT}:role/aviatrix-role-ec2"
```

**Option B: Using CoPilot UI**

1. Navigate to **Settings > Accounts > +New Account**
2. Fill in the form:
   - **Account Name:** Choose a descriptive name (e.g., "my-lab-account")
   - **Cloud Type:** AWS
   - **AWS Account Number:** Your account number
   - **IAM Role:** Enable
   - **App Role ARN:** `arn:aws:iam::<account-number>:role/aviatrix-role-app`
   - **EC2 Role ARN:** `arn:aws:iam::<account-number>:role/aviatrix-role-ec2`
3. Click **Save**
4. Wait for audit to complete

---

## Verification

### Check IAM Roles

```bash
# Verify aviatrix-role-app exists
aws iam get-role --role-name aviatrix-role-app

# Verify attached policies
aws iam list-attached-role-policies --role-name aviatrix-role-app

# Verify aviatrix-role-ec2 exists
aws iam get-role --role-name aviatrix-role-ec2

# Verify instance profile
aws iam get-instance-profile --instance-profile-name aviatrix-role-ec2
```

### Check Controller Account

```bash
# Using API
curl -k -s -X GET "https://${AVIATRIX_CONTROLLER_IP}/v1/api?action=list_accounts&CID=${CID}" | \
  python3 -c "import sys, json; accounts = json.load(sys.stdin)['results']['account_list']; [print(f\"{a['account_name']}: {a['account_number']} ({a['iam_err']})\") for a in accounts if a['cloud_type'] == 1]"
```

Look for your account with status "Pass" or "Pass*"

---

## Troubleshooting

### Issue: "Account does not exist"
**Solution:** Ensure the account name in `terraform.tfvars` exactly matches the account name in the Controller.

```bash
# List accounts in Controller
curl -k -s -X GET "https://${AVIATRIX_CONTROLLER_IP}/v1/api?action=list_accounts&CID=${CID}" | python3 -m json.tool
```

### Issue: "Failed to launch Gateway - IAM permission denied"
**Solution:** Check that all required policies are attached:

```bash
# Check aviatrix-role-app policies
aws iam list-attached-role-policies --role-name aviatrix-role-app

# Should show:
# - PowerUserAccess
# - IAMReadOnlyAccess
# - AviatrixIAMAccess
```

### Issue: "iam:CreateInstanceProfile permission denied"
**Solution:** The AviatrixIAMAccess custom policy is missing or incomplete.

```bash
# Update the policy
aws iam create-policy-version \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/AviatrixIAMAccess \
  --policy-document file://aviatrix-iam-policy.json \
  --set-as-default
```

### Issue: "VPC does not exist"
**Solution:** Terraform is using a different AWS account than the one configured in the Controller.

```bash
# Check which account Terraform is using
aws sts get-caller-identity

# Compare with Controller account
# Update terraform.tfvars if needed
```

---

## Minimum Required Permissions

### aviatrix-role-app
This role needs broad permissions to manage AWS resources:

**AWS Managed Policies:**
- `PowerUserAccess` - Full access to AWS services except IAM
- `IAMReadOnlyAccess` - Read IAM roles, policies, and instance profiles

**Custom Policy (AviatrixIAMAccess):**
- `iam:CreateInstanceProfile` - Create instance profiles for gateways
- `iam:DeleteInstanceProfile` - Delete instance profiles during cleanup
- `iam:AddRoleToInstanceProfile` - Associate role with instance profile
- `iam:RemoveRoleFromInstanceProfile` - Disassociate role from instance profile
- `iam:GetInstanceProfile` - Read instance profile details
- `iam:TagInstanceProfile` - Add tags to instance profiles
- `iam:UntagInstanceProfile` - Remove tags from instance profiles
- `iam:PassRole` - Allow EC2 to assume the aviatrix-role-ec2 role
- `iam:GetRole` - Read role details
- `iam:GetRolePolicy` - Read inline policies
- `iam:ListInstanceProfiles` - List all instance profiles
- `iam:ListRoles` - List all roles

### aviatrix-role-ec2
This role is used by gateway EC2 instances:

**AWS Managed Policies:**
- `AmazonS3ReadOnlyAccess` - Download gateway software and updates from S3

---

## Security Best Practices

### 1. Use IAM Roles (Not Access Keys)
- ✅ Roles are temporary and automatically rotated
- ✅ No hardcoded credentials in code
- ✅ Easy to audit via CloudTrail
- ❌ Avoid using AWS access keys when possible

### 2. Least Privilege Principle
- Only grant permissions actually needed
- Review CloudTrail logs to identify unused permissions
- Use AWS Access Analyzer to identify external access

### 3. Enable CloudTrail
```bash
# Ensure CloudTrail is enabled for API auditing
aws cloudtrail describe-trails
```

### 4. Tag Resources
```bash
# Add tags to IAM roles for tracking
aws iam tag-role \
  --role-name aviatrix-role-app \
  --tags Key=ManagedBy,Value=Terraform Key=Project,Value=AviatrixBlueprints
```

### 5. Regular Audits
- Review IAM role trust relationships quarterly
- Check for unused roles and policies
- Monitor for privilege escalation attempts

---

## Cleanup

When you're done and no longer need the IAM roles:

```bash
# Detach policies from aviatrix-role-app
aws iam detach-role-policy \
  --role-name aviatrix-role-app \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

aws iam detach-role-policy \
  --role-name aviatrix-role-app \
  --policy-arn arn:aws:iam::aws:policy/IAMReadOnlyAccess

aws iam detach-role-policy \
  --role-name aviatrix-role-app \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/AviatrixIAMAccess

# Delete aviatrix-role-app
aws iam delete-role --role-name aviatrix-role-app

# Remove role from instance profile
aws iam remove-role-from-instance-profile \
  --instance-profile-name aviatrix-role-ec2 \
  --role-name aviatrix-role-ec2

# Delete instance profile
aws iam delete-instance-profile \
  --instance-profile-name aviatrix-role-ec2

# Detach policies from aviatrix-role-ec2
aws iam detach-role-policy \
  --role-name aviatrix-role-ec2 \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

# Delete aviatrix-role-ec2
aws iam delete-role --role-name aviatrix-role-ec2

# Delete custom policy (must detach from all roles first)
aws iam delete-policy \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/AviatrixIAMAccess
```

---

## Common Scenarios

### Scenario 1: New AWS Account, Existing Controller
Follow the full setup guide above.

### Scenario 2: Existing Account, Adding Permissions
Just create and attach the AviatrixIAMAccess custom policy:

```bash
aws iam create-policy \
  --policy-name AviatrixIAMAccess \
  --policy-document file://aviatrix-iam-policy.json

aws iam attach-role-policy \
  --role-name aviatrix-role-app \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/AviatrixIAMAccess
```

### Scenario 3: Multi-Account Setup
Repeat the setup for each AWS account, but reuse the same Controller account number in the trust policy.

---

## Reference ARNs

After setup, you'll have these resources:

```
Role ARNs:
  arn:aws:iam::<your-account>:role/aviatrix-role-app
  arn:aws:iam::<your-account>:role/aviatrix-role-ec2

Instance Profile ARN:
  arn:aws:iam::<your-account>:instance-profile/aviatrix-role-ec2

Policy ARN:
  arn:aws:iam::<your-account>:policy/AviatrixIAMAccess
```

---

## Additional Resources

- [Aviatrix Access Account Documentation](https://docs.aviatrix.com/documentation/latest/getting-started/onboarding-aws-access-account.html)
- [AWS IAM Roles Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

---

**Last Updated:** February 17, 2026
**Tested With:** Aviatrix Controller 7.x, AWS CLI 2.x
