# =============================================================================
# Blueprint: obot-mcp-egress-aws
# Deploys an EKS cluster with Aviatrix spoke gateway and Obot, enforcing
# zero-trust egress on all MCP server pods via DCF + MCPNetworkPolicy.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  # Blueprints use local state by design.
  # Add your own backend block here for team/production use.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
