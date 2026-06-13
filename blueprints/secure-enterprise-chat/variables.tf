variable "kubeconfig_path" {
  description = "Path to the kubeconfig for the existing Aviatrix-protected cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use (the context for the target cluster). Empty uses the current context."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace to install LibreChat into. Must match the --namespace used when generating the FirewallPolicy CRD."
  type        = string
  default     = "librechat"
}

variable "release_name" {
  description = "Helm release name. Keep as 'librechat' so the pod label stays app.kubernetes.io/name=librechat (matched by the egress FirewallPolicy)."
  type        = string
  default     = "librechat"
}

variable "chart_version" {
  description = "Version of the official LibreChat Helm chart (oci://ghcr.io/danny-avila/librechat-chart/librechat)."
  type        = string
  default     = "2.0.2"
}

variable "ingress_host" {
  description = "Hostname for the LibreChat ingress (served by the cluster's existing ingress controller)."
  type        = string
  default     = "chat.example.com"
}
