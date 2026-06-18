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
  version    = var.alb_controller_chart_version

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
    value = data.terraform_remote_state.network.outputs.vpc_id
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
