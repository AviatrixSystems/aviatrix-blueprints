#####################
# AWS ALB Controller
#
# Manages AWS Application Load Balancers for Kubernetes Ingress resources.
# Uses IRSA for authentication (role created in Layer 2).
#####################

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = data.terraform_remote_state.cluster.outputs.cluster_name
    region      = data.terraform_remote_state.network.outputs.aws_region
    vpcId       = data.terraform_remote_state.network.outputs.team_a_vpc_id

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = data.terraform_remote_state.cluster.outputs.alb_controller_role_arn
      }
    }

    # Use internal LBs by default - traffic enters via Aviatrix spoke
    defaultTargetType = "ip"

    nodeSelector = {
      "nodepool-type" = "user"
    }
  })]

  depends_on = [aws_eks_node_group.default]
}

#####################
# ExternalDNS
#
# Automatically creates Route53 records for Kubernetes Services/Ingresses.
# Uses IRSA for authentication (role created in Layer 2).
#####################

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    provider = "aws"

    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = data.terraform_remote_state.cluster.outputs.external_dns_role_arn
      }
    }

    domainFilters = [data.terraform_remote_state.network.outputs.private_dns_zone_name]
    policy        = "sync"
    txtOwnerId    = data.terraform_remote_state.cluster.outputs.cluster_name

    extraArgs = [
      "--aws-zone-type=private"
    ]

    nodeSelector = {
      "nodepool-type" = "user"
    }
  })]

  depends_on = [helm_release.alb_controller]
}
