provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
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
# of this blueprint (same controller, same subscription) don't collide on names.
# Without keepers the value is generated once per workspace and stays put across
# subsequent applies until the resource is explicitly destroyed.
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

# Aviatrix's vpc_reg expects the Azure region display name ("Central India"),
# while azurerm accepts the singleword form ("centralindia"). Looking it up via
# data.azurerm_location keeps a single var.location value working for both and
# avoids a hand-maintained mapping.
data "azurerm_location" "this" {
  location = var.location
}
