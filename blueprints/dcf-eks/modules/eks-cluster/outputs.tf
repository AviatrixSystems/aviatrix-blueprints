output "vpc_id" {
  description = "VPC ID where the EKS cluster is deployed"
  value       = var.vpc_id
}

output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_service_cidr" {
  description = "Kubernetes service CIDR"
  value       = try(module.eks.cluster.kubernetes_network_config[0].service_ipv4_cidr, "172.20.0.0/16")
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "Primary security group ID of the EKS cluster (for node groups)"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "pod_security_group_id" {
  description = "Security group ID for EKS pods"
  value       = aws_security_group.pod.id
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.iam_irsa_alb_controller.arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS"
  value       = module.external_dns_irsa_role.arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
}

output "route53_zone_id" {
  description = "Route53 zone ID (if configured)"
  value       = var.route53_zone_id
}

output "route53_zone_name" {
  description = "Route53 zone name (if configured)"
  value       = var.route53_zone_name
}

output "external_dns_helm_values" {
  description = "Helm values for ExternalDNS deployment"
  value = var.route53_zone_id != "" ? {
    serviceAccount = {
      create = true
      annotations = {
        "eks.amazonaws.com/role-arn" = module.external_dns_irsa_role.arn
      }
      name = "external-dns"
    }
    provider      = "aws"
    sources       = ["service", "ingress"]
    domainFilters = [var.route53_zone_name]
    policy        = "sync"
    txtOwnerId    = var.cluster_name
    extraArgs = [
      "--aws-zone-type=private",
      "--aws-prefer-cname"
    ]
  } : null
}

output "eniconfig_manifests" {
  description = "ENIConfig YAML manifests to apply via kubectl"
  value = join("\n---\n", [
    for az, config in { for idx, az in var.availability_zones : az => {
      subnet_id = var.pod_subnet_ids[idx]
      az        = az
    } } : <<-EOT
    apiVersion: crd.k8s.amazonaws.com/v1alpha1
    kind: ENIConfig
    metadata:
      name: ${config.az}
    spec:
      subnet: ${config.subnet_id}
      securityGroups:
        - ${aws_security_group.pod.id}
    EOT
  ])
}

output "eniconfig_apply_command" {
  description = "Command to apply ENIConfig resources"
  value       = "terraform output -raw ${var.cluster_name}_eniconfig_manifests | kubectl apply -f -"
}
