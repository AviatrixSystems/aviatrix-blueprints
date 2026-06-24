provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}
