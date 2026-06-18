variable "aviatrix_controller_ip" {
  description = "Aviatrix controller hostname (no https://). Set via TF_VAR_aviatrix_controller_ip env var — do NOT commit in tfvars."
  type        = string
  sensitive   = true
}

variable "aviatrix_username" {
  description = "Aviatrix controller username. Set via TF_VAR_aviatrix_username env var — do NOT commit in tfvars."
  type        = string
  sensitive   = true
}

variable "aviatrix_password" {
  description = "Aviatrix controller password. Set via TF_VAR_aviatrix_password env var — do NOT commit in tfvars."
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region (e.g. eu-west-3, us-east-2). Singleword form is accepted by both the aws provider and Aviatrix vpc_reg."
  type        = string
}

variable "aviatrix_account_name" {
  description = "Aviatrix-side account name that maps to the AWS account this blueprint runs in."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to all named resources (VPC, subnets, SG, DCF groups, etc.). A 6-digit deployment ID is auto-appended."
  type        = string
  default     = "gh-runner"
}

variable "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name. When null, auto-derived from local.name_prefix so multiple deployments don't collide."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "VPC address space"
  type        = string
  default     = "10.20.10.0/24"
}

variable "gw_subnet_cidr" {
  description = "Aviatrix GW (public) subnet CIDR"
  type        = string
  default     = "10.20.10.0/26"
}

variable "runner_subnet_cidr" {
  description = "Runner (private) subnet CIDR"
  type        = string
  default     = "10.20.10.64/26"
}

variable "github_pat" {
  description = "GitHub PAT with repo scope — used at VM boot to generate a fresh runner registration token via API. Must be SSO-authorized for the target org if applicable."
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repo URL for runner registration"
  type        = string
}

variable "runner_instance_type" {
  description = "EC2 instance type for the runner VM"
  type        = string
  default     = "t3.small"
}

variable "aviatrix_gw_size" {
  description = "EC2 instance type for the Aviatrix spoke gateway"
  type        = string
  default     = "t3.medium"
}

variable "aws_key_pair_name" {
  description = "Existing AWS key pair name to attach to the runner for SSH access (optional). When null the runner has no SSH key — use SSM/Serial Console as fallback."
  type        = string
  default     = null
}

variable "runner_version" {
  description = "GitHub Actions runner version (e.g. 2.334.0)"
  type        = string
  default     = "2.334.0"
}

variable "runner_package_hash" {
  description = "SHA-256 hash of the runner linux-x64 tarball for the specified version"
  type        = string
  default     = "048024cd2c848eb6f14d5646d56c13a4def2ae7ee3ad12122bee960c56f3d271"
}

variable "gh_runner_required_fqdns" {
  description = "FQDNs required by the GitHub Actions runner (HTTPS 443): registration API, runner binary download, Actions service, artifact/cache, container registry, packages."
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

variable "linux_pkg_install_fqdns" {
  description = "Ubuntu APT FQDNs for cloud-init package installation (HTTP 80 + HTTPS 443)."
  type        = list(string)
  default = [
    "archive.ubuntu.com",
    "security.ubuntu.com",
    "esm.ubuntu.com",
    "entropy.ubuntu.com",
    "api.snapcraft.io",
  ]
}

variable "tool_call_fqdns" {
  description = "FQDNs the runner is allowed to reach for agent/tool calls (HTTP 80 + HTTPS 443). Set per deployment via tfvars; when empty the corresponding WebGroup and DCF rule are omitted entirely."
  type        = list(string)
  default     = []
}
