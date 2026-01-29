# /validate-blueprint

Run comprehensive validation checks on a blueprint to ensure it meets repository standards.

## Usage

```
/validate-blueprint [blueprint-path]
```

If no path is provided, validates the current directory or prompts for selection.

## What This Skill Does

1. **Terraform validation** - fmt, init, validate
2. **README completeness** - Checks for all required sections
3. **Standards compliance** - Verifies naming conventions and patterns
4. **Link verification** - Ensures all links in README are valid
5. **Security checks** - Looks for hardcoded credentials or sensitive data

## Validation Checks

### Terraform Checks

- [ ] `terraform fmt -check` passes
- [ ] `terraform init -backend=false` succeeds
- [ ] `terraform validate` passes
- [ ] All variables have descriptions
- [ ] All outputs have descriptions
- [ ] Provider versions are pinned

### Required Files

- [ ] `README.md` exists
- [ ] `main.tf` exists
- [ ] `variables.tf` exists
- [ ] `outputs.tf` exists
- [ ] `versions.tf` exists
- [ ] `terraform.tfvars.example` exists
- [ ] Architecture diagram exists (`.png` or `.svg`)

### README Sections

Per `docs/blueprint-standards.md`, README must include:

- [ ] Title and description
- [ ] Architecture diagram with explanation
- [ ] Prerequisites (linking to shared docs)
- [ ] Resources Created table
- [ ] Deployment instructions (step-by-step)
- [ ] Variables reference table
- [ ] Outputs reference table
- [ ] Test scenarios
- [ ] Cleanup/destroy instructions
- [ ] Troubleshooting section
- [ ] Version compatibility matrix

### Naming Conventions

- [ ] Blueprint directory is lowercase with hyphens
- [ ] Resources use `var.name_prefix` or `local.name_prefix`
- [ ] No hardcoded resource names

### Security Checks

- [ ] No hardcoded credentials
- [ ] Sensitive variables marked `sensitive = true`
- [ ] No AWS account IDs hardcoded
- [ ] No IP addresses hardcoded (except examples in docs)
- [ ] `.gitignore` includes `*.tfstate*` and `*.tfvars`

### Link Verification

- [ ] All relative links in README resolve
- [ ] Links to shared prerequisites docs are valid
- [ ] External links are accessible

## Instructions for Claude

When this skill is invoked:

1. **Run Terraform checks**:
   ```bash
   cd <blueprint-path>
   terraform fmt -check
   terraform init -backend=false
   terraform validate
   ```

2. **Check file existence**:
   - Verify all required files exist
   - Check for architecture diagram

3. **Parse README.md**:
   - Look for required section headers
   - Verify tables are properly formatted
   - Check for placeholder text that wasn't replaced

4. **Analyze Terraform files**:
   - Ensure variables have descriptions
   - Ensure outputs have descriptions
   - Check for hardcoded values
   - Verify naming conventions

5. **Verify links**:
   - Check relative links resolve to existing files
   - Optionally check external links

6. **Generate report**:
   - Show pass/fail for each check
   - Provide specific feedback for failures
   - Calculate overall compliance score

## Output Format

```
Validating blueprint: dcf-eks

## Terraform Validation
✅ terraform fmt -check passed
✅ terraform init succeeded
✅ terraform validate passed
✅ All 12 variables have descriptions
✅ All 8 outputs have descriptions
✅ Provider versions pinned

## Required Files
✅ README.md
✅ main.tf
✅ variables.tf
✅ outputs.tf
✅ versions.tf
✅ terraform.tfvars.example
✅ architecture.png

## README Completeness
✅ Title and description
✅ Architecture diagram
✅ Prerequisites section
⚠️ Resources Created table - missing 2 resources
✅ Deployment instructions
✅ Variables reference
✅ Outputs reference
⚠️ Test scenarios - only 1 scenario (recommend 2+)
✅ Cleanup instructions
❌ Troubleshooting section - MISSING
✅ Version compatibility

## Standards Compliance
✅ Directory naming (dcf-eks)
✅ Resource naming uses name_prefix
✅ No hardcoded credentials detected
⚠️ AWS region hardcoded in data source (line 45)

## Link Verification
✅ 8/8 internal links valid
✅ 3/3 external links accessible

---

**Overall Score: 87%** (26/30 checks passed)

### Required Fixes:
1. Add Troubleshooting section to README
2. Update Resources Created table (missing aws_nat_gateway, aws_eip)

### Recommendations:
1. Add more test scenarios
2. Remove hardcoded region on line 45
```
