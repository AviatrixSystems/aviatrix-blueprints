variable "eks_cluster_name" {
  description = "EKS cluster name. When set, Terraform looks up the cluster's OIDC issuer and creates the Bedrock IRSA role (trust policy scoped to system:serviceaccount:<namespace>:<release_name>), then annotates the ServiceAccount with it. Empty = skip IRSA (non-AWS cluster, or bring-your-own model auth). Requires AWS credentials in the environment when set."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region of the EKS cluster (the aws_eks_cluster lookup is region-scoped). Independent of bedrock_region. Empty falls back to AWS_REGION / shared config. Only used when eks_cluster_name is set."
  type        = string
  default     = ""
}

variable "bedrock_region" {
  description = "AWS region for Bedrock. Sets BEDROCK_AWS_DEFAULT_REGION in the credentials Secret and drives the bedrock-runtime.<region> egress permit. Enable Anthropic model access for this region in the Bedrock console (account-level, not Terraform-able)."
  type        = string
  default     = "us-east-1"
}

variable "bedrock_models" {
  description = "Comma-separated Bedrock inference-profile model ids shown in the LibreChat UI (BEDROCK_AWS_MODELS)."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0,us.anthropic.claude-sonnet-4-6"
}

variable "ingress_class_name" {
  description = "Ingress class to install with. Empty = auto-detect the cluster's IngressClass objects (alb -> nginx -> none/disabled). Set to force a specific class."
  type        = string
  default     = ""
}

variable "ingress_host" {
  description = "Hostname for the LibreChat ingress. Empty = host-less rule (open the load balancer address directly). Set to use a real hostname."
  type        = string
  default     = ""
}

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
  description = "Namespace to install LibreChat into. Used in the IRSA trust policy and the FirewallPolicy CRD."
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
