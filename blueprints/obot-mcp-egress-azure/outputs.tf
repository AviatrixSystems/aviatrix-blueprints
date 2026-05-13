# =============================================================================
# Outputs
# =============================================================================

output "spoke_gateway_name" {
  description = "Name of the deployed Aviatrix spoke gateway"
  value       = aviatrix_spoke_gateway.obot.gw_name
}

output "spoke_gateway_public_ip" {
  description = "Public IP (EIP) of the Aviatrix spoke gateway. All MCP server pod egress SNATs to this IP."
  value       = aviatrix_spoke_gateway.obot.eip
}

output "obot_namespace" {
  description = "Kubernetes namespace where Obot is deployed"
  value       = var.obot_namespace
}

output "obot_mcp_namespace" {
  description = "Kubernetes namespace where Obot deploys MCP server pods"
  value       = var.obot_mcp_namespace
}

output "next_steps" {
  description = "Post-deployment actions"
  value       = <<-EOT
    Deployment complete. Next steps:

    1. Access Obot UI:
       kubectl port-forward -n ${var.obot_namespace} svc/obot-obot 8080:80

    2. Enable DCF enforcement on Kubernetes (required once after deploy):
       CoPilot -> DCF -> Settings -> Enforcement on Kubernetes -> Enable

    3. Enable Log Enrichment for pod-level FlowIQ identity:
       CoPilot -> Feature Previews -> Log Enrichment -> Enable

    4. Apply an MCPNetworkPolicy to allow egress for an MCP server:
       kubectl apply -f k8s/example-mcpnetworkpolicy.yaml

    5. Verify enforcement in CoPilot:
       CoPilot -> DCF -> Monitor -> filter by MCP server SmartGroup
  EOT
}
