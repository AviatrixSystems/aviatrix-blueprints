# =============================================================================
# Outputs
# =============================================================================

locals {
  # EKS module node_group_id format: "cluster-name:nodegroup-name" (documented contract).
  # Extracted here once so outputs and next_steps stay in sync.
  eks_nodegroup_name = split(":", module.eks.eks_managed_node_groups["system"].node_group_id)[1]
}

output "eks_cluster_name" {
  description = "Name of the deployed EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_nodegroup_name" {
  description = "Name of the EKS managed node group (use in aws eks update-nodegroup-config --nodegroup-name)"
  value       = local.eks_nodegroup_name
}

output "spoke_gateway_name" {
  description = "Name of the deployed Aviatrix Gateway (Policy Enforcement Point)"
  value       = module.spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "spoke_gateway_public_ip" {
  description = "Public IP of the Aviatrix Gateway (Policy Enforcement Point). All MCP server pod egress SNATs to this IP."
  value       = module.spoke.spoke_gateway.eip
  sensitive   = true
}

output "next_steps" {
  description = "Post-deployment actions"
  value       = <<-EOT
    Deployment complete. Next steps:

    1. If nodes did not start (e.g. node_desired_size was overridden to 0), scale up:
       aws eks update-nodegroup-config \
         --cluster-name ${module.eks.cluster_name} \
         --nodegroup-name ${local.eks_nodegroup_name} \
         --scaling-config minSize=1,maxSize=4,desiredSize=2 \
         --region ${var.aws_region}

    2. Access Obot UI:
       kubectl port-forward -n ${var.obot_namespace} svc/obot-obot 8080:80

    3. Verify DCF enforcement was applied (automated by terraform apply):
       CoPilot -> DCF -> Settings -> Enforcement on Kubernetes (should show Enabled)
       CoPilot -> DCF -> Settings -> Log Enrichment (should show On)
       CoPilot -> Cloud Resources -> Cloud Workloads -> Kubernetes Clusters (cluster should show as onboarded)

    4. (Optional) Populate obot_mcp_pod_cidrs for explicit V1 DENY SmartGroup:
       kubectl get pods -n ${var.obot_mcp_namespace} -o wide
       # Default Action deny-all enforces without this; only needed for explicit V1 DENY rule
  EOT
}
