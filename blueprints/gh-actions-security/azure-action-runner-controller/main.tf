provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

# Aviatrix credentials come from TF_VAR_* environment variables — never set in tfvars.
provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

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

# Aviatrix vpc_reg takes the region display name; azurerm wants singleword.
# data.azurerm_location bridges both off a single var.location.
data "azurerm_location" "this" {
  location = var.location
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}
