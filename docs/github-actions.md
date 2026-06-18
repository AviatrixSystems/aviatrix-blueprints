# GitHub Actions Deployment Guide

Automated deployment of Aviatrix Kubernetes blueprints via GitHub Actions.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  workflow_dispatch (pattern, csp, action, layer)             │
└────────────────────────────┬─────────────────────────────────┘
                             │
              ┌──────────────▼──────────────┐
              │         Setup Job           │
              │  Validate inputs, compute   │
              │  matrix targets             │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │      Approval Gate          │
              │  (skipped for plan)         │
              │  Environment: production    │
              │  or destroy                 │
              └──────────────┬──────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │ action=plan/apply│                   │ action=destroy
          ▼                  │                   ▼
   ┌─────────────┐          │          ┌──────────────────┐
   │ L1: Network │          │          │ Destroy L3: Nodes│
   └──────┬──────┘          │          └────────┬─────────┘
          ▼                 │                   ▼
   ┌─────────────┐          │          ┌──────────────────┐
   │ L2: Clusters│ (matrix) │          │Destroy L2: Clust.│ (matrix)
   └──────┬──────┘          │          └────────┬─────────┘
          ▼                 │                   ▼
   ┌─────────────┐          │          ┌──────────────────┐
   │ L3: Nodes   │ (matrix) │          │Destroy L1: Netw. │
   └──────┬──────┘          │          └──────────────────┘
          ▼                 │
   ┌─────────────┐          │
   │ L4: CRDs    │          │
   └──────┬──────┘          │
          ▼                 │
   ┌─────────────┐          │
   │  Validate   │          │
   └─────────────┘          │
```

**State is stored in S3** (not GitHub artifacts), so layers can be run independently across separate workflow runs.

---

## One-Time Setup

### Quick Setup (Recommended)

Choose either the **GUI** or the **CLI** to run the interactive setup:

#### Option A: Web GUI

```bash
cd .github
python3 setup_gui.py
```

Opens a local browser UI at `http://127.0.0.1:8471` with a form for all configuration values, live prerequisite status indicators, and real-time streaming output. No external dependencies — uses only the Python standard library.

#### Option B: CLI

```bash
cd .github
chmod +x setup.sh
./setup.sh
```

Both options perform the same steps:
1. Check prerequisites (aws, gh, terraform, jq)
2. Create the S3 state bucket
3. Configure all GitHub secrets and variables
4. Create GitHub environments
5. Check for the AWS OIDC provider

After setup completes, add required reviewers to the environments (link provided in the output).

---

### Manual Setup (Alternative)

If you prefer to configure manually, follow the steps below.

#### 1. Bootstrap the S3 State Bucket

```bash
cd .github/bootstrap
aws sso login  # or configure credentials

terraform init
terraform apply

# Note the output:
# bucket_name = "aviatrix-blueprints-tfstate-a1b2c3d4"
```

**Optional: Enable state locking** (recommended for team environments):

```bash
terraform apply -var="enable_state_locking=true"

# Additional output:
# dynamodb_table_name = "aviatrix-blueprints-tfstate-lock"
```

When enabled, set the table name as GitHub variable `TF_LOCK_TABLE`.

#### 2. Configure GitHub Repository

##### Secrets

Go to **Settings > Secrets and variables > Actions > Secrets** and add:

| Secret | Description | Example |
|--------|-------------|---------|
| `AVIATRIX_CONTROLLER_IP` | Aviatrix controller IP address | `52.1.2.3` |
| `AVIATRIX_USERNAME` | Aviatrix admin username | `admin` |
| `AVIATRIX_PASSWORD` | Aviatrix admin password | `•••••` |
| `AWS_ROLE_ARN` | IAM role ARN for GitHub OIDC | `arn:aws:iam::123456789012:role/github-actions` |
| `AWS_ACCOUNT_ID` | AWS account ID | `123456789012` |
| `AVIATRIX_AWS_ACCOUNT` | Aviatrix-onboarded AWS account name | `lab-test-aws` |

Optional (for Azure/GCP):

| Secret | Description |
|--------|-------------|
| `AZURE_CREDENTIALS` | Azure service principal JSON |
| `GCP_CREDENTIALS` | GCP service account JSON |
| `AVIATRIX_AZURE_ACCOUNT` | Aviatrix-onboarded Azure account name |
| `AVIATRIX_GCP_ACCOUNT` | Aviatrix-onboarded GCP account name |

##### Variables

Go to **Settings > Secrets and variables > Actions > Variables** and add:

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_REGION` | Target AWS region | `us-east-2` |
| `TF_STATE_BUCKET` | S3 bucket from bootstrap step | `aviatrix-blueprints-tfstate-a1b2c3d4` |
| `TF_LOCK_TABLE` | DynamoDB table (if `enable_state_locking=true`) | `aviatrix-blueprints-tfstate-lock` |

##### Environments (Approval Gates)

Go to **Settings > Environments** and create:

1. **`production`** — for apply actions
   - Add "Required reviewers" (1 or more team members)
   - Optional: restrict to `main` branch

2. **`destroy`** — for destroy actions
   - Add "Required reviewers" (recommend 2+ reviewers)
   - Optional: restrict to `main` branch

#### 3. Configure AWS OIDC for GitHub Actions

The workflow uses OIDC (no long-lived credentials). Create a trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
      }
    }
  }]
}
```

The role needs these permissions:
- `AmazonEKSFullAccess`
- `AmazonVPCFullAccess`
- `IAMFullAccess` (for IRSA roles — base + recommendation components)
- `AmazonRoute53FullAccess`
- `ElasticLoadBalancingFullAccess`
- `AmazonS3FullAccess` (or scoped to state bucket + Velero backup bucket)
- `ServiceQuotasReadOnlyAccess`
- `CloudWatchLogsFullAccess` (if `enable_fluent_bit` or `enable_control_plane_logging`)
- `AmazonDynamoDBFullAccess` (if `enable_state_locking`, or scope to lock table only)

#### 4. Request AWS Service Quotas

Before deploying, ensure sufficient quotas in your target region:

| Quota | Pattern A | Pattern B | Pattern C | Default |
|-------|-----------|-----------|-----------|---------|
| VPCs | 6 | 3 | 5 | 5 |
| Elastic IPs | 12 | 4 | 10 | 5 |
| EKS Clusters | 3 | 1 | 2 | 100 |

```bash
# Request VPC increase
aws service-quotas request-service-quota-increase \
  --service-code vpc --quota-code L-F678F1CE \
  --desired-value 20 --region us-east-2

# Request EIP increase
aws service-quotas request-service-quota-increase \
  --service-code ec2 --quota-code L-0263D0A3 \
  --desired-value 20 --region us-east-2
```

---

## Usage

### Running Deployments

Go to **Actions > Deploy Aviatrix K8s Blueprints > Run workflow** and select:

| Parameter | Options | Description |
|-----------|---------|-------------|
| Pattern | `cluster-aas`, `namespace-aas`, `prod-nonprod-hybrid` | Blueprint architecture |
| CSP | `aws`, `azure`, `gcp` | Cloud provider |
| Action | `plan`, `apply`, `destroy` | Terraform action |
| Layer | `all`, `network`, `clusters`, `nodes`, `crds` | Which layer(s) |

### Recommended Deployment Flow

#### First deployment (full stack)

```
1. plan  + layer=all     → Review plan output in job summary
2. apply + layer=all     → Approve in GitHub, deploys all 4 layers sequentially
```

#### Incremental changes

```
1. plan  + layer=nodes   → Review what changes in the nodes layer
2. apply + layer=nodes   → Apply just the nodes layer (downloads network/cluster state from S3)
```

#### Tear down

```
1. destroy + layer=all   → Approve in GitHub, destroys in reverse order (nodes → clusters → network)
```

### Layer Dependencies

```
network ← clusters ← nodes ← crds
```

- Each layer depends on the previous layer's state
- You can run individual layers if upstream state already exists in S3
- `layer=all` runs all layers sequentially in the correct order
- Destroy reverses the order automatically

### Pattern Matrix Targets

| Pattern | Matrix targets | Description |
|---------|---------------|-------------|
| `cluster-aas` | `team-a`, `team-b`, `team-c` | 3 dedicated clusters |
| `namespace-aas` | `shared` | 1 shared cluster |
| `prod-nonprod-hybrid` | `prod`, `nonprod` | 2 environment clusters |

Matrix targets run in parallel (up to 3 concurrent) within each layer.

---

## Customizing Variables

### Default Behavior

All Terraform variables have sensible defaults. The only truly required variables (Aviatrix account names) are injected automatically from GitHub secrets.

### Overriding Defaults

To customize CIDR ranges, instance types, cluster versions, etc., create a `terraform.tfvars` file **in the specific layer directory** and commit it:

```
blueprints/
└── prod-nonprod-hybrid/
    └── aws/
        ├── network/
        │   └── terraform.tfvars          ← network variable overrides
        ├── clusters/
        │   ├── prod/
        │   │   └── terraform.tfvars      ← prod cluster overrides (+ recommendation toggles)
        │   └── nonprod/
        │       └── terraform.tfvars      ← nonprod cluster overrides (+ recommendation toggles)
        └── nodes/
            ├── prod/
            │   └── terraform.tfvars      ← prod node overrides (+ recommendation toggles)
            └── nonprod/
                └── terraform.tfvars      ← nonprod node overrides (+ recommendation toggles)
```

Each layer has its own variable declarations — use the `terraform.tfvars.example` at the pattern level as a reference for available variables per layer.

**Example** — customize the network layer for Pattern C:

```hcl
# blueprints/prod-nonprod-hybrid/aws/network/terraform.tfvars
environment_prefix = "myprefix"
aws_region         = "us-west-2"
prod_vpc_cidr      = "10.100.0.0/20"
nonprod_vpc_cidr   = "10.200.0.0/20"
enable_ha          = false
```

### Architecture Recommendation Toggles

Best-practice hardening is available via opt-in boolean variables. All default to `false`.

**Cluster layer** (`clusters/*/terraform.tfvars`):
```hcl
enable_private_endpoint      = true   # Private-only EKS API endpoint
enable_control_plane_logging = true   # Full control plane audit logging
```

**Nodes layer** (`nodes/*/terraform.tfvars`):
```hcl
# Security (defense-in-depth alongside Aviatrix DCF)
enable_network_policy   = true   # Calico NetworkPolicy
enable_gatekeeper       = true   # OPA Gatekeeper admission control
enable_external_secrets = true   # External Secrets Operator
enable_falco            = true   # Falco runtime threat detection

# Observability
enable_prometheus_stack = true   # Prometheus + Grafana + alerting
enable_fluent_bit       = true   # Log aggregation to CloudWatch

# Resilience
enable_node_termination_handler = true   # SPOT instance graceful drain
enable_cluster_autoscaler       = true   # Dynamic node scaling
enable_velero                   = true   # Cluster backup to S3
```

**Bootstrap** (`.github/bootstrap/terraform.tfvars`):
```hcl
enable_state_locking = true   # DynamoDB state lock table
```

These toggles can also be passed via CI/CD environment variables:
```yaml
env:
  TF_VAR_enable_control_plane_logging: "true"
  TF_VAR_enable_network_policy: "true"
```

See `ARCHITECTURE-ANALYSIS.md` for full rationale, references, and suggested profiles (demo vs. minimum prod vs. full hardening).

---

## State Management

### How It Works

- Terraform uses **local backend** (no code changes to existing modules)
- The workflow **downloads** state from S3 before `terraform init`
- After `terraform apply`, state is **uploaded** back to S3
- Artifacts are also uploaded as a 30-day backup

### S3 Key Convention

```
s3://{TF_STATE_BUCKET}/blueprints/{pattern}/{csp}/{layer}/{target}/terraform.tfstate
```

Examples:
```
blueprints/cluster-aas/aws/network/terraform.tfstate
blueprints/cluster-aas/aws/clusters/team-a/terraform.tfstate
blueprints/cluster-aas/aws/nodes/team-b/terraform.tfstate
blueprints/prod-nonprod-hybrid/aws/clusters/prod/terraform.tfstate
```

### Inspecting State

```bash
# List all state files
aws s3 ls "s3://${TF_STATE_BUCKET}/blueprints/" --recursive

# Download state for local inspection
aws s3 cp "s3://${TF_STATE_BUCKET}/blueprints/prod-nonprod-hybrid/aws/network/terraform.tfstate" .
terraform show terraform.tfstate
```

### Recovering State

If state is accidentally deleted from S3, check:
1. **S3 versioning** — previous versions are retained
2. **GitHub artifacts** — 30-day backup artifacts per workflow run

```bash
# Restore from S3 versioning
aws s3api list-object-versions \
  --bucket "$TF_STATE_BUCKET" \
  --prefix "blueprints/prod-nonprod-hybrid/aws/network/terraform.tfstate"

aws s3api get-object \
  --bucket "$TF_STATE_BUCKET" \
  --key "blueprints/prod-nonprod-hybrid/aws/network/terraform.tfstate" \
  --version-id "VERSION_ID" \
  terraform.tfstate
```

---

## Concurrency & Safety

### Concurrency Control

The workflow uses GitHub Actions concurrency groups:
```
deploy-{pattern}-{csp}
```

This means:
- Two deployments of `cluster-aas/aws` cannot run simultaneously
- `cluster-aas/aws` and `namespace-aas/aws` CAN run simultaneously
- Queued runs wait (they are not cancelled)

### Approval Gates

| Action | Environment | Required |
|--------|-------------|----------|
| `plan` | (none) | No approval |
| `apply` | `production` | Reviewer approval |
| `destroy` | `destroy` | Reviewer approval |

Reviewers see the plan output in the job summary before approving.

### Recommended Workflow

```
Developer                    GitHub Actions              Reviewer
    │                             │                          │
    ├─ Run workflow (plan) ──────►│                          │
    │                             ├─ Execute plan            │
    │◄── Review plan summary ─────┤                          │
    │                             │                          │
    ├─ Run workflow (apply) ─────►│                          │
    │                             ├─ Wait for approval ─────►│
    │                             │◄── Approve ──────────────┤
    │                             ├─ Execute apply           │
    │◄── Validate results ────────┤                          │
```

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Network state not found" | Running clusters/nodes without prior network apply | Run `layer=network` with `action=apply` first |
| Terraform plan fails on unknown variable | `terraform.tfvars` contains variables from wrong layer | Each layer has its own variables — check `variables.tf` in the layer directory |
| Approval timeout | No reviewer approved within environment timeout | Re-run the workflow and approve promptly |
| Concurrent run queued indefinitely | Previous run stuck or failed | Cancel the stuck run, then re-run |
| EKS cluster CREATING timeout | EKS takes 10-15 min | Normal — wait for the cluster job to complete |
| "No existing state found" | First deployment of this layer | Normal for first runs — state is created by apply |
| Aviatrix provider auth error | Controller IP/credentials wrong | Check `AVIATRIX_CONTROLLER_IP`, `AVIATRIX_USERNAME`, `AVIATRIX_PASSWORD` secrets |
| S3 download permission denied | IAM role missing S3 access | Add `s3:GetObject`/`s3:PutObject` to the OIDC role for the state bucket |

### Checking Workflow Logs

1. Go to **Actions** tab in GitHub
2. Click on the workflow run
3. Each job shows:
   - **Plan output** in the Step Summary (bottom of the job page)
   - **Validation results** table after apply
4. Click individual steps to see full terraform output

### Manual State Recovery

If the workflow fails mid-apply and state is inconsistent:

```bash
# 1. Download the current state
aws s3 cp "s3://${TF_STATE_BUCKET}/blueprints/{pattern}/{csp}/{layer}/terraform.tfstate" .

# 2. Navigate to the layer directory locally
cd blueprints/{pattern}/{csp}/{layer}
cp /path/to/downloaded/terraform.tfstate .

# 3. Run terraform locally to fix
export AVIATRIX_CONTROLLER_IP="..."
export AVIATRIX_USERNAME="..."
export AVIATRIX_PASSWORD="..."
terraform init
terraform plan   # assess the damage
terraform apply  # or: terraform state rm <resource> for orphaned resources

# 4. Upload fixed state back to S3
aws s3 cp terraform.tfstate "s3://${TF_STATE_BUCKET}/blueprints/{pattern}/{csp}/{layer}/terraform.tfstate"
```

---

## Examples

### Deploy Pattern C (Prod/Non-Prod) from scratch

```
Step 1: Plan everything
  Pattern: prod-nonprod-hybrid | CSP: aws | Action: plan | Layer: all

Step 2: Review plan output in each job's summary

Step 3: Apply everything
  Pattern: prod-nonprod-hybrid | CSP: aws | Action: apply | Layer: all
  → Approve when prompted
  → Wait ~30-40 min for full deployment

Step 4: Verify in Aviatrix CoPilot
  - Security > Distributed Cloud Firewall — verify rules
  - Cloud Assets > Kubernetes — verify clusters discovered
```

### Update node groups only (e.g., scale up)

```
1. Edit blueprints/prod-nonprod-hybrid/aws/nodes/prod/terraform.tfvars
   (change desired_size, instance_type, etc.)

2. Commit and push

3. Run workflow:
   Pattern: prod-nonprod-hybrid | CSP: aws | Action: plan | Layer: nodes
   → Review plan

4. Run workflow:
   Pattern: prod-nonprod-hybrid | CSP: aws | Action: apply | Layer: nodes
   → Approve
```

### Tear down Pattern A completely

```
Run workflow:
  Pattern: cluster-aas | CSP: aws | Action: destroy | Layer: all
  → Approve in the "destroy" environment
  → Destroys: nodes → clusters → network (reverse order)
```
