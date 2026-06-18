# -----------------------------------------------------------------------------
# Pattern C: AKS Production Nodes — Data Sources
# -----------------------------------------------------------------------------

data "azurerm_kubernetes_cluster" "prod" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}
