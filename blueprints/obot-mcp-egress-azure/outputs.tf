# =============================================================================
# Outputs
# =============================================================================

output "spoke_gateway_name" {
  description = "Name of the deployed Aviatrix Gateway (Policy Enforcement Point)"
  value       = aviatrix_spoke_gateway.obot.gw_name
  sensitive   = true
}

output "spoke_gateway_public_ip" {
  description = "Public IP (EIP) of the Aviatrix Gateway (Policy Enforcement Point). All MCP server pod egress SNATs to this IP."
  value       = aviatrix_spoke_gateway.obot.eip
  sensitive   = true
}

output "obot_namespace" {
  description = "Kubernetes namespace where Obot is deployed"
  value       = var.obot_namespace
}

output "obot_mcp_namespace" {
  description = "Kubernetes namespace where Obot deploys MCP server pods"
  value       = var.obot_mcp_namespace
}

output "aks_cluster_name" {
  description = "Name of the deployed AKS cluster"
  value       = azurerm_kubernetes_cluster.obot.name
}

output "resource_group_name" {
  description = "Name of the Azure resource group containing all resources"
  value       = azurerm_kubernetes_cluster.obot.resource_group_name
}

output "next_steps" {
  description = "Post-deployment actions"
  value       = <<-EOT
    Deployment complete. Next steps:

    1. Update kubeconfig:
       az aks get-credentials \
         --resource-group ${azurerm_kubernetes_cluster.obot.resource_group_name} \
         --name ${azurerm_kubernetes_cluster.obot.name}

    2. Access Obot UI:
       kubectl port-forward -n ${var.obot_namespace} svc/obot-obot 8080:80

    3. Verify DCF enforcement was applied (automated by terraform apply):
       CoPilot -> DCF -> Settings -> Enforcement on Kubernetes (should show Enabled)
       CoPilot -> DCF -> Settings -> Log Enrichment (should show On)
       CoPilot -> Cloud Resources -> Cloud Workloads -> Kubernetes Clusters (cluster should show as onboarded)
  EOT
}
