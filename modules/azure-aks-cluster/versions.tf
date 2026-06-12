terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aviatrix = {
      source = "AviatrixSystems/aviatrix"
      # Cross-major: this module only uses aviatrix_kubernetes_cluster (present in
      # 8.2 and 9.0). The effective provider is pinned by the consuming blueprint
      # layer (~> 9.0 by default, ~> 8.2.0 for the Controller-8.2 path), so this
      # constraint stays permissive to support both without editing the module.
      version = ">= 8.2, < 10.0"
    }
  }
}
