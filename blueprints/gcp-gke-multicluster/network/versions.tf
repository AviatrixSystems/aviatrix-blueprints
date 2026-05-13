terraform {
  required_version = ">= 1.5"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
