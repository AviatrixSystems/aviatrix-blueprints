---
name: analyze-blueprint
description: Analyze a blueprint directory and generate comprehensive documentation about what it creates and requires. Use when the user asks to analyze, understand, or document a blueprint.
argument-hint: [blueprint-path]
---

# Analyze Blueprint

Analyze a blueprint directory and generate comprehensive documentation about what it creates and requires.

## Usage

```
/analyze-blueprint [blueprint-path]
```

If no path is provided, analyzes the current directory or prompts for selection.

## What This Skill Does

1. **Reads all Terraform files** in the blueprint directory
2. **Extracts resources** from `resource` blocks
3. **Identifies data sources** from `data` blocks
4. **Parses variables** from `variables.tf`
5. **Collects outputs** from `outputs.tf`
6. **Checks provider requirements** from `versions.tf`

## Output Generated

### Resources Created Table

| Resource Type | Resource Name | Description | Cloud |
|---------------|---------------|-------------|-------|
| aws_vpc | main | Primary VPC for workloads | AWS |
| aviatrix_spoke_gateway | spoke | Spoke gateway attached to transit | Aviatrix |

### Prerequisites Checklist

- [ ] Aviatrix Control Plane v8.1+ accessible (Controller and CoPilot)
- [ ] AWS CLI configured with appropriate permissions
- [ ] Terraform v1.5+ installed
- [ ] Sufficient EIP quota (X required)

### Required IAM Permissions

Lists the AWS/Azure/GCP permissions needed based on resources created.

### Estimated Costs

Provides hourly and monthly cost estimates for the resources.

### Variable Reference

Complete table of all input variables with types, defaults, and whether required.

### Output Reference

Complete table of all outputs with descriptions.

## Instructions for Claude

When this skill is invoked:

1. Read all `.tf` files in the specified blueprint directory
2. Parse each file to extract:
   - `resource` blocks → Resources Created
   - `data` blocks → Data sources (may indicate prerequisites)
   - `variable` blocks → Variables Reference
   - `output` blocks → Output Reference
   - `terraform.required_providers` → Provider versions
3. For each resource, determine:
   - Cloud provider (AWS, Azure, GCP, Aviatrix)
   - Approximate cost (use known pricing or estimate)
   - Required permissions
4. Generate a comprehensive markdown report
5. Optionally update the blueprint's README.md with the generated content

## Example

```
> /analyze-blueprint blueprints/dcf-eks

Analyzing blueprint: dcf-eks

## Resources Created (14 total)

| Resource | Name | Description | Count |
|----------|------|-------------|-------|
| aws_vpc | transit | Transit VPC | 1 |
| aws_vpc | spoke | Spoke VPCs for workloads | 2 |
| aws_subnet | public | Public subnets | 6 |
| aviatrix_transit_gateway | main | Primary transit gateway | 1 |
| aviatrix_spoke_gateway | spoke | Spoke gateways | 2 |
| aws_eks_cluster | main | EKS cluster | 1 |
...

## Prerequisites

### Required Tools
- Terraform >= 1.5.0
- AWS CLI v2
- kubectl
- Aviatrix Control Plane v8.1+ (Controller and CoPilot)

### Required Access
- AWS account with VPC, EC2, EKS permissions
- Aviatrix account onboarded to the Control Plane

### Resource Quotas
- 3 Elastic IPs
- 1 EKS cluster
- 3 VPCs

## Estimated Cost

| Resource | Hourly | Monthly |
|----------|--------|---------|
| Aviatrix Transit Gateway | $0.50 | $365 |
| Aviatrix Spoke Gateways (2) | $1.00 | $730 |
| EKS Cluster | $0.10 | $73 |
| NAT Gateways (3) | $0.135 | $98 |
| **Total** | **$1.735** | **~$1,266** |
```
