#####################
# AKS Node Layer (Layer 3) - Team-C
#
# Refactored to inline azurerm_kubernetes_cluster_node_pool — the previously
# referenced module ../../../../azure-aks-multicluster/modules/aks-node-group
# does not exist.
#####################

provider "azurerm" {
  features {}
}

provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)
  client_certificate     = base64decode(data.terraform_remote_state.cluster.outputs.client_certificate)
  client_key             = base64decode(data.terraform_remote_state.cluster.outputs.client_key)
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)
    client_certificate     = base64decode(data.terraform_remote_state.cluster.outputs.client_certificate)
    client_key             = base64decode(data.terraform_remote_state.cluster.outputs.client_key)
  }
}

#####################
# Aviatrix Kubernetes Cluster Onboarding
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = data.terraform_remote_state.cluster.outputs.cluster_id
  use_csp_credentials = true
}

resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"
  wait       = false

  depends_on = [azurerm_kubernetes_cluster_node_pool.default]
}

resource "azurerm_kubernetes_cluster_node_pool" "default" {
  name                  = "default"
  kubernetes_cluster_id = data.terraform_remote_state.cluster.outputs.cluster_id

  vm_size              = var.node_pool_config.vm_size
  node_count           = var.node_pool_config.node_count
  min_count            = var.node_pool_config.min_count
  max_count            = var.node_pool_config.max_count
  auto_scaling_enabled = true
  priority             = var.node_pool_config.priority
  eviction_policy      = var.node_pool_config.priority == "Spot" ? "Delete" : null
  spot_max_price       = var.node_pool_config.priority == "Spot" ? -1 : null

  vnet_subnet_id = data.terraform_remote_state.network.outputs.team_c_aks_system_subnet_id

  node_labels = {
    "nodepool-type" = "user"
    "team"          = "team-c"
  }

  tags = {
    Environment = "demo"
    Team        = "team-c"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

resource "kubernetes_config_map_v1_data" "coredns_custom" {
  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }
  data = {
    "private-dns.server" = <<-EOF
      ${data.terraform_remote_state.network.outputs.private_dns_zone_name}:53 {
          forward . 168.63.129.16
          cache 30
          log
          errors
      }
    EOF
  }
  force      = true
  depends_on = [azurerm_kubernetes_cluster_node_pool.default]
}
