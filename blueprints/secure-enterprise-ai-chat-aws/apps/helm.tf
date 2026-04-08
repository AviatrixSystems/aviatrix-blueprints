#####################
# AWS Load Balancer Controller
#####################

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.13.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.infra.outputs.cluster_name
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
    value = data.terraform_remote_state.infra.outputs.alb_controller_role_arn
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.infra.outputs.vpc_id
  }

  set {
    name  = "region"
    value = data.terraform_remote_state.infra.outputs.aws_region
  }
}

#####################
# Aviatrix K8s Firewall CRD
#####################

resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"

  wait = false
}

#####################
# MongoDB (for LibreChat)
#####################

resource "helm_release" "mongodb" {
  name       = "mongodb"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "mongodb"
  version    = "16.5.13"
  namespace  = "default"

  set {
    name  = "auth.enabled"
    value = "false"
  }

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "250m"
  }
}
