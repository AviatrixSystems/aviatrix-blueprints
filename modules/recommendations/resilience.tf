# ─────────────────────────────────────────────────────────────────────────────
# Resilience Recommendations
#
# Cluster resilience and cost optimization:
#   - AWS Node Termination Handler (SPOT graceful drain)
#   - Cluster Autoscaler (dynamic node scaling)
#   - Velero (cluster backup & disaster recovery)
# ─────────────────────────────────────────────────────────────────────────────

#####################
# AWS Node Termination Handler
#
# Handles SPOT interruption notices, scheduled maintenance events,
# and rebalance recommendations. Cordons and drains nodes gracefully.
#
# Uses IMDS polling mode (no SQS infrastructure needed).
#
# Ref: https://github.com/aws/aws-node-termination-handler
# Analysis: Section 3 — "SPOT instances in production"
#####################

resource "helm_release" "node_termination_handler" {
  count = var.enable_node_termination_handler ? 1 : 0

  name             = "aws-node-termination-handler"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-node-termination-handler"
  version          = var.nth_chart_version
  namespace        = "kube-system"
  create_namespace = false

  # IMDS polling mode — no SQS needed
  set {
    name  = "enableSpotInterruptionDraining"
    value = "true"
  }

  set {
    name  = "enableRebalanceMonitoring"
    value = "true"
  }

  set {
    name  = "enableScheduledEventDraining"
    value = "true"
  }

  set {
    name  = "enableRebalanceDraining"
    value = "true"
  }

  wait    = true
  timeout = 300
}

#####################
# Cluster Autoscaler
#
# Dynamically adjusts the number of nodes based on pending pod
# scheduling and node utilization. Uses IRSA for EC2 Auto Scaling API.
#
# Ref: https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler
# Analysis: Section 3 — "Add Karpenter or cluster autoscaler"
#####################

resource "helm_release" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = var.cluster_autoscaler_chart_version
  namespace        = "kube-system"
  create_namespace = false

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler[0].arn
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  # Scale-down settings
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "5m"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "true"
  }

  wait    = true
  timeout = 300
}

#####################
# Velero — Cluster Backup & DR
#
# Backs up Kubernetes resources and persistent volumes to S3.
# Enables disaster recovery with scheduled and on-demand backups.
#
# Ref: https://velero.io/
# Analysis: Section 7 — "Cluster backup"
#####################

resource "aws_s3_bucket" "velero" {
  count  = var.enable_velero ? 1 : 0
  bucket = "${var.cluster_name}-velero-backups"

  tags = merge(var.tags, {
    Purpose = "velero-backups"
  })
}

resource "aws_s3_bucket_versioning" "velero" {
  count  = var.enable_velero ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  count  = var.enable_velero ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  count                   = var.enable_velero ? 1 : 0
  bucket                  = aws_s3_bucket.velero[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "helm_release" "velero" {
  count = var.enable_velero ? 1 : 0

  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = var.velero_chart_version
  namespace        = "velero"
  create_namespace = true

  set {
    name  = "serviceAccount.server.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.velero[0].arn
  }

  set {
    name  = "serviceAccount.server.name"
    value = "velero"
  }

  set {
    name  = "configuration.backupStorageLocation[0].provider"
    value = "aws"
  }

  set {
    name  = "configuration.backupStorageLocation[0].bucket"
    value = aws_s3_bucket.velero[0].id
  }

  set {
    name  = "configuration.backupStorageLocation[0].config.region"
    value = var.aws_region
  }

  set {
    name  = "configuration.volumeSnapshotLocation[0].provider"
    value = "aws"
  }

  set {
    name  = "configuration.volumeSnapshotLocation[0].config.region"
    value = var.aws_region
  }

  set {
    name  = "initContainers[0].name"
    value = "velero-plugin-for-aws"
  }

  set {
    name  = "initContainers[0].image"
    value = "velero/velero-plugin-for-aws:v1.9.0"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].name"
    value = "plugins"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].mountPath"
    value = "/target"
  }

  # Schedule daily backups
  set {
    name  = "schedules.daily-backup.schedule"
    value = "0 2 * * *"
  }

  set {
    name  = "schedules.daily-backup.template.ttl"
    value = "168h"
  }

  set {
    name  = "schedules.daily-backup.template.includedNamespaces[0]"
    value = "*"
  }

  wait    = true
  timeout = 300

  depends_on = [aws_s3_bucket.velero]
}
