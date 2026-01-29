## Description

<!-- Provide a brief description of the changes in this PR -->

## Type of Change

<!-- Mark the relevant option with an 'x' -->

- [ ] New blueprint
- [ ] Blueprint enhancement
- [ ] Bug fix
- [ ] Documentation update
- [ ] CI/CD improvement
- [ ] Other (describe):

## Blueprint Checklist (for new or modified blueprints)

<!-- Complete this checklist for blueprint changes -->

### Documentation
- [ ] README.md includes all required sections (see [Blueprint Standards](docs/blueprint-standards.md))
- [ ] Architecture diagram is included and accurate
- [ ] All variables are documented with descriptions
- [ ] terraform.tfvars.example includes all required variables
- [ ] Test scenarios are documented
- [ ] Troubleshooting section covers common issues

### Code Quality
- [ ] `terraform fmt` passes
- [ ] `terraform validate` passes
- [ ] No hardcoded values (use variables)
- [ ] Sensitive variables marked as `sensitive = true`
- [ ] Resource naming uses `var.name_prefix`

### Testing
- [ ] Full deploy/destroy cycle tested
- [ ] All test scenarios verified
- [ ] Tested on documented Control Plane version(s)
- [ ] Cleanup leaves no orphaned resources

### Catalog Update
- [ ] Blueprint added to catalog in root README.md (for new blueprints)

## Control Plane Version Tested

<!-- List the Aviatrix Control Plane version(s) tested against -->

- Control Plane version:

## Cloud Environment

<!-- List the cloud provider(s) and any specific configurations -->

- Cloud provider(s):
- Region(s) tested:

## Screenshots / Architecture

<!-- Include screenshots or architecture diagrams if applicable -->

## Additional Notes

<!-- Any additional information reviewers should know -->

---

**By submitting this PR, I confirm that:**
- [ ] I have read the [Contributing Guide](CONTRIBUTING.md)
- [ ] This PR does not include sensitive information (credentials, keys, etc.)
- [ ] I am willing to respond to review feedback
