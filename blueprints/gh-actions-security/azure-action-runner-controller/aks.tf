# AKS cluster — Azure CNI gives every pod a VNet IP directly from the AKS
# subnet. depends_on enforces that the Aviatrix spoke gateway is up + the
# AKS subnet's RT is programmed by the controller (private_route_table_config
# on the spoke). Without that ordering AKS nodes can't reach the internet to
# pull container images and cluster creation fails.
resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "aks-${local.name_prefix}"
  kubernetes_version  = var.aks_kubernetes_version
  oidc_issuer_enabled = true # Azure auto-enables; declaring matches state so provider stops trying to disable.
  tags                = local.common_tags

  default_node_pool {
    name           = "system"
    node_count     = var.aks_node_count
    vm_size        = var.aks_node_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure" # Azure CNI: pod IPs from VNet
    service_cidr   = var.aks_service_cidr
    dns_service_ip = var.aks_dns_service_ip
    outbound_type  = "userDefinedRouting" # egress via the AKS subnet's RT (programmed to spoke GW by Aviatrix)
  }

  # Cluster creation reaches mcr.microsoft.com / registry.k8s.io etc. for
  # image pulls — that only works once egress flows via the spoke. The spoke
  # gateway resource also programs the AKS RT via private_route_table_config;
  # by the time terraform considers it complete, the RT default route points
  # at the spoke ENI.
  depends_on = [
    aviatrix_spoke_gateway.this,
    azurerm_subnet_route_table_association.aks,
  ]
}

# Disable SNAT for all outbound pod traffic so pod IPs are preserved at the
# spoke GW (required for DCF k8s SmartGroup matching). The azure-ip-masq-agent-v2
# in AKS reads "ip-masq-agent-reconciled" from the reconciled ConfigMap by
# preference. We override it by patching that ConfigMap directly.
# Azure CNI assigns real VNet IPs to pods, so no address space collision.
resource "kubernetes_config_map" "disable_snat" {
  metadata {
    name      = "azure-ip-masq-agent-config"
    namespace = "kube-system"
  }

  data = {
    "ip-masq-agent" = <<-YAML
      nonMasqueradeCIDRs:
        - 0.0.0.0/0
      masqLinkLocal: false
    YAML
  }

  depends_on = [azurerm_kubernetes_cluster.this]
}

# Trigger a rollout restart of azure-ip-masq-agent by patching its pod template
# annotation. This forces the DaemonSet to pick up the disable_snat ConfigMap
# immediately without needing kubectl on the Terraform host.
resource "kubernetes_annotations" "restart_masq_agent" {
  api_version = "apps/v1"
  kind        = "DaemonSet"
  metadata {
    name      = "azure-ip-masq-agent"
    namespace = "kube-system"
  }
  template_annotations = {
    "kubectl.kubernetes.io/restartedAt" = sha256(jsonencode(kubernetes_config_map.disable_snat.data))
  }
  depends_on = [kubernetes_config_map.disable_snat]
}

# Grant the AKS cluster identity Network Contributor on the AKS subnet so
# LoadBalancer Services can attach kubelet VMSS NICs to it (subnets/join).
# Assign at both subnet AND VNet scope — subnet alone is sometimes
# insufficient for the linked-authorization check when the VMSS is in a
# different RG (AKS-managed mc_* RG).
resource "azurerm_role_assignment" "aks_subnet_join" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "aks_vnet_join" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

# Aviatrix SP needs AKS Cluster User Role to call listClusterUserCredential
# (used by use_csp_credentials=true on aviatrix_kubernetes_cluster).
resource "azurerm_role_assignment" "aviatrix_aks_cluster_user" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.aviatrix_sp_object_id
}
