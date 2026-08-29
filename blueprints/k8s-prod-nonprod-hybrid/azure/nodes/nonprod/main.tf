# -----------------------------------------------------------------------------
# Pattern C: AKS Non-Production Nodes — Helm Deployments
# Aviatrix k8s-firewall for DCF Layer 2 enforcement
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
}

provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.nonprod.kube_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.nonprod.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.nonprod.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.nonprod.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.nonprod.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.nonprod.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.nonprod.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.nonprod.kube_config[0].cluster_ca_certificate)
}

# ---------------------------------------------------------------------------
# Aviatrix Kubernetes Cluster Onboarding
# ---------------------------------------------------------------------------

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = var.cluster_id
  use_csp_credentials = true
}

# ---------------------------------------------------------------------------
# Aviatrix Kubernetes Firewall (DCF Layer 2 enforcement)
# ---------------------------------------------------------------------------

resource "helm_release" "aviatrix_k8s_firewall" {
  name             = "aviatrix-k8s-firewall"
  namespace        = "aviatrix-system"
  create_namespace = true
  repository       = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart            = "k8s-firewall"
  version          = "9.0.0"
  wait             = false

  set {
    name  = "controllerIP"
    value = var.aviatrix_controller_ip
  }

  set {
    name  = "controllerUsername"
    value = var.aviatrix_username
  }

  set_sensitive {
    name  = "controllerPassword"
    value = var.aviatrix_password
  }

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "cloud"
    value = "Azure"
  }

  set {
    name  = "enableCRD"
    value = "true"
  }
}
