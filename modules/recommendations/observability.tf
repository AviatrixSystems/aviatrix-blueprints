# ─────────────────────────────────────────────────────────────────────────────
# Observability Recommendations
#
# Cluster monitoring and log aggregation:
#   - kube-prometheus-stack (metrics + dashboards + alerts)
#   - Fluent Bit (log forwarding to CloudWatch Logs)
# ─────────────────────────────────────────────────────────────────────────────

#####################
# kube-prometheus-stack — Metrics & Dashboards
#
# Deploys Prometheus, Grafana, Alertmanager, and node-exporter
# with preconfigured Kubernetes dashboards and alerting rules.
#
# Ref: https://github.com/prometheus-community/helm-charts
# Analysis: Section 6 — "Cluster monitoring"
#####################

resource "helm_release" "prometheus_stack" {
  count = var.enable_prometheus_stack ? 1 : 0

  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_stack_chart_version
  namespace        = "monitoring"
  create_namespace = true

  # Grafana defaults
  set {
    name  = "grafana.adminPassword"
    value = "aviatrix-demo"
  }

  set {
    name  = "grafana.service.type"
    value = "ClusterIP"
  }

  # Persistent storage for Prometheus
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "20Gi"
  }

  # Scrape interval
  set {
    name  = "prometheus.prometheusSpec.scrapeInterval"
    value = "30s"
  }

  wait    = true
  timeout = 600
}

#####################
# Fluent Bit — Log Aggregation
#
# Collects container logs and forwards to CloudWatch Logs.
# Runs as a DaemonSet on all nodes.
#
# Ref: https://docs.fluentbit.io/manual/
# Analysis: Section 6 — "Log aggregation"
#####################

resource "aws_cloudwatch_log_group" "fluent_bit" {
  count = var.enable_fluent_bit ? 1 : 0

  name              = "/aws/eks/${var.cluster_name}/containers"
  retention_in_days = 30

  tags = var.tags
}

resource "helm_release" "fluent_bit" {
  count = var.enable_fluent_bit ? 1 : 0

  name             = "fluent-bit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  version          = var.fluent_bit_chart_version
  namespace        = "logging"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.fluent_bit[0].arn
  }

  set {
    name  = "serviceAccount.name"
    value = "fluent-bit"
  }

  values = [yamlencode({
    config = {
      outputs = <<-EOF
        [OUTPUT]
            Name              cloudwatch_logs
            Match             *
            region            ${var.aws_region}
            log_group_name    /aws/eks/${var.cluster_name}/containers
            log_stream_prefix from-fluent-bit-
            auto_create_group false
      EOF
    }
  })]

  wait    = true
  timeout = 300

  depends_on = [aws_cloudwatch_log_group.fluent_bit]
}
