variable "aviatrix_controller_ip" {
  description = "Aviatrix controller hostname or IP (no https://). TF_VAR_aviatrix_controller_ip env var preferred."
  type        = string
  sensitive   = true
}

variable "aviatrix_username" {
  description = "Aviatrix controller username. TF_VAR_aviatrix_username env var preferred."
  type        = string
  sensitive   = true
}

variable "aviatrix_password" {
  description = "Aviatrix controller password. TF_VAR_aviatrix_password env var preferred."
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region (e.g. eu-west-2, us-east-1)."
  type        = string
}

variable "aviatrix_account_name" {
  description = "Aviatrix-side account name that maps to the AWS account this blueprint runs in."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to all named resources. A 6-digit deployment ID is auto-appended."
  type        = string
  default     = "gh-eks-runner"
}

variable "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name. When null, auto-derived from local.name_prefix."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "Spoke VPC address space."
  type        = string
  default     = "10.20.30.0/24"
}

variable "gw_subnet_cidr" {
  description = "Aviatrix spoke gateway subnet CIDR (public, single AZ)."
  type        = string
  default     = "10.20.30.0/26"
}

variable "eks_primary_subnet_cidr" {
  description = "Primary EKS subnet CIDR (AZ[0])."
  type        = string
  default     = "10.20.30.64/26"
}

variable "eks_secondary_subnet_cidr" {
  description = "Secondary EKS subnet CIDR (AZ[1]) — required by EKS control plane."
  type        = string
  default     = "10.20.30.128/26"
}

variable "spoke_gw_size" {
  description = "EC2 instance type for the Aviatrix spoke gateway."
  type        = string
  default     = "t3.medium"
}

variable "eks_node_count" {
  description = "Number of EKS managed node group instances."
  type        = number
  default     = 1
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "eks_kubernetes_version" {
  description = "Kubernetes version for the EKS cluster. When null, EKS picks the default."
  type        = string
  default     = null
}

variable "cluster_admin_arns" {
  description = "IAM principal ARNs (users or roles) that get EKS cluster-admin access. Add your deployer ARN here so kubectl works after apply."
  type        = list(string)
  default     = []
}

variable "github_pat" {
  description = "GitHub PAT with repo scope — used by ARC to register runners. Set via tfvars; do not commit."
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repository URL for ARC runner scale set registration (e.g. https://github.com/org/repo)."
  type        = string
}

variable "gh_runner_required_fqdns" {
  description = "FQDNs required by ARC + GitHub Actions runner pods (HTTPS 443)."
  type        = list(string)
  default = [
    "github.com",
    "api.github.com",
    "*.actions.githubusercontent.com",
    "objects.githubusercontent.com",
    "codeload.github.com",
    "*.pkg.github.com",
    "ghcr.io",
    "*.ghcr.io",
    "raw.githubusercontent.com",
    "release-assets.githubusercontent.com",
  ]
}

variable "tool_call_fqdns" {
  description = "FQDNs runner pods may reach for agent/tool calls (HTTP 80 + HTTPS 443). When empty, the DCF rule is omitted."
  type        = list(string)
  default     = []
}

variable "aviatrix_mitm_ca_pem" {
  description = "PEM-encoded Aviatrix MITM CA certificate. Mounted into the TLS-decrypt probe pod so curl trusts GW-resigned certificates. Fetch once: GET https://<controller>/v2.5/api/mitm/ca with Authorization: cid <token>. Required only when deploy_probes=true."
  type        = string
  default     = ""
}

variable "arc_runner_name" {
  description = "ARC runner scale set name — becomes the runs-on label in workflows. Must be unique per controller/repo."
  type        = string
  default     = "aws-arc"
}

variable "deploy_probes" {
  description = "Deploy TLS-probe and ipify-probe pods. Set false to skip probe workloads (e.g. initial infra validation)."
  type        = bool
  default     = true
}
