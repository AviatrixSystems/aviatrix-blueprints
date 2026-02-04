# Blueprint Name

<!--
TEMPLATE: Replace this section with a brief description of your blueprint.
1-3 sentences covering what this blueprint deploys, the use case, and key Aviatrix features demonstrated.
-->

Brief description of what this blueprint deploys and demonstrates.

## Architecture

<!--
TEMPLATE: Include an architecture diagram showing:
- Cloud resources (VPCs, subnets, instances)
- Aviatrix components (gateways, transit, firewalls)
- Network connectivity and data flows
- Regions/availability zones

Save the diagram as architecture.png in this directory.
-->

![Architecture Diagram](architecture.png)

Brief explanation of the architecture and key data flows.

## Prerequisites

### Required Tools

<!-- TEMPLATE: Link to shared prerequisite docs. Add or remove as needed. -->

- [Aviatrix Control Plane](../../docs/prerequisites/aviatrix-controller.md) (v7.1+) - Controller and CoPilot
- [Terraform](../../docs/prerequisites/terraform.md) (v1.5+)
- [AWS CLI](../../docs/prerequisites/aws-cli.md)
<!-- - [Azure CLI](../../docs/prerequisites/azure-cli.md) -->
<!-- - [Google Cloud CLI](../../docs/prerequisites/gcloud-cli.md) -->
<!-- - [kubectl](../../docs/prerequisites/kubectl.md) -->

### Required Access

<!-- TEMPLATE: List cloud permissions and Aviatrix requirements -->

- AWS account with permissions to create VPCs, EC2 instances, etc.
- Aviatrix Control Plane with AWS account onboarded

### Blueprint-Specific Requirements

<!-- TEMPLATE: List any requirements unique to this blueprint -->

- At least 2 available Elastic IPs in the target region
- Service quota for X (if applicable)

## Resources Created

<!-- TEMPLATE: List ALL resources this blueprint creates -->

| Resource | Description | Quantity |
|----------|-------------|----------|
| AWS VPC | Main VPC for workloads | 1 |
| Aviatrix Transit Gateway | Primary transit gateway | 1 |
| Aviatrix Spoke Gateway | Spoke gateway for workloads | 1 |
| EC2 Instance | Test instance for connectivity | 1 |

**Estimated Cost**: ~$X/hour when running

<!-- Optional: Include cost breakdown for major components -->

## Deployment

### Step 1: Clone and Navigate

```bash
git clone https://github.com/aviatrix/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/<blueprint-name>
```

### Step 2: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values. See [Variables](#variables) section for details.

### Step 3: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted to confirm.

<!-- TEMPLATE: Note approximate deployment time -->
Deployment takes approximately X minutes.

### Step 4: Verify Deployment

<!-- TEMPLATE: Add verification steps specific to your blueprint -->

After deployment completes:

1. Check Terraform outputs: `terraform output`
2. Verify in Aviatrix CoPilot: Navigate to Topology to view deployed resources
3. Verify in cloud console: Check that VPCs/instances are created

## Variables

<!-- TEMPLATE: Document ALL input variables -->

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `controller_ip` | Aviatrix Control Plane (Controller) IP address | `string` | - | yes |
| `controller_username` | Controller admin username | `string` | `"admin"` | no |
| `controller_password` | Controller admin password | `string` | - | yes |
| `aws_region` | AWS region for deployment | `string` | `"us-east-1"` | no |
| `name_prefix` | Prefix for resource names | `string` | `"blueprint"` | no |

## Outputs

<!-- TEMPLATE: Document ALL outputs -->

| Output | Description |
|--------|-------------|
| `transit_gateway_id` | ID of the Aviatrix Transit Gateway |
| `spoke_vpc_id` | ID of the spoke VPC |
| `test_instance_ip` | Public IP of the test instance |

## Test Scenarios

<!-- TEMPLATE: Provide specific, repeatable test scenarios -->

### Scenario 1: Basic Connectivity

Verify basic connectivity between components:

```bash
# SSH to test instance
ssh -i <key.pem> ec2-user@<test_instance_ip>

# Ping another resource
ping <target-ip>
```

**Expected result**: Ping succeeds, traffic flows through Aviatrix gateway.

### Scenario 2: [Specific Feature Test]

<!-- TEMPLATE: Add scenarios for each key feature the blueprint demonstrates -->

1. Navigate to CoPilot > [relevant section]
2. Perform action
3. Verify expected behavior

**Expected result**: [describe expected outcome]

## Demo Walkthrough

<!-- TEMPLATE: Optional section for presentation/demo purposes -->

Use this section to guide a demonstration:

1. **Show the architecture**: Open CoPilot topology view
2. **Demonstrate feature X**: Walk through the configuration
3. **Generate traffic**: Run connectivity test
4. **Show visibility**: View in CoPilot monitoring

## Cleanup

### Standard Destroy

```bash
terraform destroy
```

Type `yes` when prompted to confirm.

### Manual Cleanup (if destroy fails)

<!-- TEMPLATE: List resources that might need manual cleanup -->

If Terraform destroy fails, manually delete:

1. Any load balancers created by applications
2. Any manually created resources

### Verify Cleanup

Confirm no resources remain:

```bash
# Check for remaining resources (adjust filter as needed)
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*<name_prefix>*"
```

## Troubleshooting

<!-- TEMPLATE: Document common issues and solutions -->

### Issue: Gateway creation fails

**Symptom**: Aviatrix gateway times out during creation

**Solution**:
1. Verify AWS account is onboarded in the Control Plane
2. Check security group allows Controller communication
3. Verify sufficient EIP quota in the region

### Issue: [Specific issue]

**Symptom**: Description of the problem

**Solution**: Steps to resolve

## Tested With

<!-- TEMPLATE: Document the versions this blueprint is tested against -->

This blueprint is currently tested with:

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 8.0.x |
| Aviatrix Terraform Provider | 3.2.0 |
| Terraform | 1.9.x |
| AWS Provider | 5.80.x |

> **Note**: The blueprint may work with other versions, but these are the versions used for validation.

## Contributing

See the [Contributing Guide](../../CONTRIBUTING.md) for information on how to contribute to this blueprint.

## License

Apache 2.0 - See [LICENSE](../../LICENSE)
