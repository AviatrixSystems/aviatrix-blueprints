provider "aws" {
  region = var.aws_region
}

# Aviatrix credentials come from TF_VAR_* environment variables — never set in tfvars:
#   export TF_VAR_aviatrix_controller_ip=...
#   export TF_VAR_aviatrix_username=...
#   export TF_VAR_aviatrix_password=...
provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

# Stable 6-digit suffix appended to every named resource so multiple deployments
# of this blueprint (same controller, same account) don't collide on names.
resource "random_integer" "deployment_id" {
  min = 100000
  max = 999999
}

locals {
  name_prefix = "${var.name_prefix}-${random_integer.deployment_id.result}"

  common_tags = {
    blueprint = "gh-pipeline-sec"
  }
}

# Pick the first AZ available in the region. The blueprint runs everything in a
# single AZ to keep the layout small; bump to a list if you need HA later.
data "aws_availability_zones" "available" {
  state = "available"
}

# Ubuntu 22.04 LTS amd64 AMI from Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
