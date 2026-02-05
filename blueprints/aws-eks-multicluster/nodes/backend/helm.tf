#####################
# Kubernetes Add-ons (Helm Charts)
#####################
# These add-ons are automatically installed after the cluster and nodes are ready
# Deployed in Layer 3 to ensure cluster and nodes exist before installation

# AWS Load Balancer Controller
# Manages ALB/NLB for Kubernetes Service and Ingress resources
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.10.1" # Pin version for stability

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.cluster.outputs.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.cluster.outputs.alb_controller_role_arn
  }

  # IMPORTANT: vpcId and region are required when using VPC CNI custom networking
  # Pods can't access EC2 metadata due to secondary CIDR, so these must be explicit
  set {
    name  = "vpcId"
    value = data.terraform_remote_state.network.outputs.backend_vpc_id
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  # Wait for nodes to be ready before installing
  depends_on = [
    module.default_node_group,
    aws_eks_addon.coredns
  ]
}

# ExternalDNS
# Automatically creates Route53 DNS records for Kubernetes Service and Ingress resources
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = "1.19.0" # Pin version

  # Using values instead of multiple set blocks for complex configurations
  # This is more maintainable and avoids shell escaping issues
  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = data.terraform_remote_state.cluster.outputs.external_dns_role_arn
        }
      }

      provider = {
        name = "aws"
      }

      # Only manage records in this domain
      domainFilters = [data.terraform_remote_state.network.outputs.route53_zone_name]

      # Sync mode: ExternalDNS will create AND delete records
      policy = "sync"

      # Unique identifier for this cluster's records
      txtOwnerId = data.terraform_remote_state.cluster.outputs.cluster_name

      # AWS-specific settings
      extraArgs = [
        "--aws-zone-type=private",
        "--aws-prefer-cname"
      ]
    })
  ]

  # Install after ALB controller
  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}
