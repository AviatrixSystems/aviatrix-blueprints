output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  description = "AKS cluster API server endpoint"
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate for the AKS cluster"
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "external_dns_identity_client_id" {
  description = "Client ID of the managed identity used by ExternalDNS"
  value       = azurerm_user_assigned_identity.external_dns.client_id
}

output "ingress_identity_client_id" {
  description = "Client ID of the managed identity used by the ingress controller"
  value       = azurerm_user_assigned_identity.ingress.client_id
}

output "external_dns_helm_values" {
  description = "Pre-rendered Helm values for ExternalDNS with workload identity annotations"
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

output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "cluster_id" {
  description = "AKS cluster ID for Aviatrix onboarding"
  value       = azurerm_kubernetes_cluster.this.id
}
