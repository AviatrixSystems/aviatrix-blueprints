# =============================================================================
# Outputs
# =============================================================================

output "eks_cluster_name" {
  description = "Name of the deployed EKS cluster"
  value       = module.eks.cluster_name
}

output "spoke_gateway_name" {
  description = "Name of the deployed Aviatrix spoke gateway"
  value       = module.spoke.spoke_gateway.gw_name
}

output "spoke_gateway_public_ip" {
  description = "Public IP of the Aviatrix spoke gateway. All MCP server pod egress SNATs to this IP."
  value       = module.spoke.spoke_gateway.eip
}

output "next_steps" {
  description = "Post-deployment actions"
  value       = <<-EOT
    Deployment complete. Next steps:

    1. Scale EKS nodes to desired count (was 0 on first apply to wait for routes):
       aws eks update-nodegroup-config --cluster-name ${module.eks.cluster_name} \
         --nodegroup-name system --scaling-config minSize=1,maxSize=4,desiredSize=2

    2. Access Obot UI:
       kubectl port-forward -n ${var.obot_namespace} svc/obot-obot 8080:80

    3. Enable DCF enforcement on Kubernetes (required once after deploy):
       CoPilot -> DCF -> Settings -> Enforcement on Kubernetes -> Enable

    4. Update obot-system pod CIDRs for scoped egress (re-apply required):
       kubectl get pods -n ${var.obot_namespace} -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}'
       # Add those IPs as /32 values to var.obot_system_pod_cidrs, then terraform apply

    5. After deploying MCP servers, update obot-mcp pod CIDRs for DENY enforcement:
       kubectl get pods -n ${var.obot_mcp_namespace} -o wide
       # Add pod IPs as /32 values to var.obot_mcp_pod_cidrs, then terraform apply
  EOT
}
