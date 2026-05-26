locals {
  acr_name        = data.terraform_remote_state.foundry.outputs.acr_name
  subscription_id = data.terraform_remote_state.foundry.outputs.subscription_id
}

variable "image_name" {
  description = "Container image name"
  type        = string
  default     = "hotel-rogue-agent"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}
