#####################
# Cluster Identity
#####################

output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

#####################
# Cluster Endpoints
#####################

output "cluster_endpoint" {
  description = "AKS cluster API server endpoint"
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the cluster"
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

#####################
# Network
#####################

output "cluster_service_cidr" {
  description = "Kubernetes service CIDR"
  value       = azurerm_kubernetes_cluster.this.network_profile[0].service_cidr
}

output "node_resource_group" {
  description = "Auto-generated resource group for AKS node infrastructure"
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

#####################
# Workload Identity
#####################

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "external_dns_identity_client_id" {
  description = "Client ID of the ExternalDNS managed identity"
  value       = azurerm_user_assigned_identity.external_dns.client_id
}

output "ingress_identity_client_id" {
  description = "Client ID of the ingress controller managed identity"
  value       = azurerm_user_assigned_identity.ingress.client_id
}

#####################
# Configuration Helpers
#####################

output "kubectl_config_command" {
  description = "az CLI command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}

output "external_dns_helm_values" {
  description = "Helm values for ExternalDNS with Azure Private DNS provider"
  value = yamlencode({
    provider = {
      name = "azure-private-dns"
    }

    secretConfiguration = {
      enabled   = true
      mountPath = "/etc/kubernetes"
      data = {
        "azure.json" = jsonencode({
          tenantId                     = data.azurerm_client_config.current.tenant_id
          subscriptionId               = data.azurerm_client_config.current.subscription_id
          resourceGroup                = data.terraform_remote_state.network.outputs.private_dns_zone_resource_group
          useWorkloadIdentityExtension = true
          userAssignedIdentityID       = azurerm_user_assigned_identity.external_dns.client_id
        })
      }
    }

    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "azure.workload.identity/client-id" = azurerm_user_assigned_identity.external_dns.client_id
      }
    }

    podLabels = {
      "azure.workload.identity/use" = "true"
    }

    domainFilters = [data.terraform_remote_state.network.outputs.private_dns_zone_name]

    sources = ["service", "ingress"]

    logLevel = "info"
  })
}
