terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "aviatrix" {
  controller_ip = var.avx_controller_ip
  username      = var.avx_username
  password      = var.avx_password
}
