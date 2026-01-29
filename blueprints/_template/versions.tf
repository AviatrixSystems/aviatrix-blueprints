# =============================================================================
# Terraform and Provider Versions
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = ">= 3.1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }

  # Note: Blueprints use local state by design.
  # Users can add their own backend configuration if needed.
}
