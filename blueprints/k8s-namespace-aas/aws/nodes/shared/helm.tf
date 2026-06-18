#####################
# AWS Load Balancer Controller
#
# Manages ALB/NLB resources for Kubernetes Ingress and Service resources.
# Uses IRSA for IAM authentication (the AWS equivalent of Workload Identity).
#####################

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = data.terraform_remote_state.cluster.outputs.cluster_name

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
      }
    }

    vpcId  = data.terraform_remote_state.network.outputs.shared_vpc_id
    region = data.terraform_remote_state.network.outputs.aws_region

    # Use internal ALBs — traffic enters via Aviatrix spoke
    defaultTargetType = "ip"

    nodeSelector = {
      "nodepool-type" = "shared"
    }
  })]

  depends_on = [aws_eks_node_group.shared]
}

# ALB Controller IAM role with IRSA
resource "aws_iam_role" "alb_controller" {
  name = "${data.terraform_remote_state.network.outputs.name_prefix}-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${data.terraform_remote_state.cluster.outputs.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = aws_iam_role.alb_controller.name
}

data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${data.terraform_remote_state.network.outputs.name_prefix}-alb-controller"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.alb_controller_policy.response_body
}

#####################
# ExternalDNS
#
# Automatically creates Route53 records for Kubernetes Services/Ingresses.
# Uses IRSA for IAM authentication.
#####################

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    provider = {
      name = "aws"
    }

    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
      }
    }

    domainFilters = [data.terraform_remote_state.network.outputs.private_dns_zone_name]

    policy     = "sync"
    txtOwnerId = data.terraform_remote_state.cluster.outputs.cluster_name

    extraArgs = [
      "--aws-zone-type=private",
    ]

    sources = ["service", "ingress"]

    nodeSelector = {
      "nodepool-type" = "shared"
    }
  })]

  depends_on = [helm_release.aws_lb_controller]
}

# ExternalDNS IAM role with IRSA
resource "aws_iam_role" "external_dns" {
  name = "${data.terraform_remote_state.network.outputs.name_prefix}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${data.terraform_remote_state.cluster.outputs.oidc_provider}:sub" = "system:serviceaccount:kube-system:external-dns"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "external_dns" {
  name = "${data.terraform_remote_state.network.outputs.name_prefix}-external-dns"
  role = aws_iam_role.external_dns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
        ]
        Resource = "arn:aws:route53:::hostedzone/${data.terraform_remote_state.network.outputs.private_dns_zone_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
        ]
        Resource = "*"
      },
    ]
  })
}
