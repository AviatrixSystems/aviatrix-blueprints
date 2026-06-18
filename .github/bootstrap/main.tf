# ─────────────────────────────────────────────────────────────
# Bootstrap: S3 bucket for Terraform state storage
#
# Run once before using the GitHub Actions workflow:
#   cd .github/bootstrap
#   terraform init
#   terraform apply
#
# The bucket name output must be set as GitHub variable TF_STATE_BUCKET.
# ─────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-east-2"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name (a random suffix is appended)"
  type        = string
  default     = "aviatrix-blueprints-tfstate"
}

variable "enable_state_locking" {
  description = <<-EOT
    Create a DynamoDB table for Terraform state locking.
    Prevents concurrent state corruption from parallel workflow runs.
    Ref: https://developer.hashicorp.com/terraform/language/backend/s3
  EOT
  type        = bool
  default     = false
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.bucket_prefix}-${random_id.suffix.hex}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────────────────────────────────────
# DynamoDB State Lock Table (opt-in)
#
# Prevents concurrent Terraform operations from corrupting state.
# When enabled, configure each layer's backend with:
#   dynamodb_table = "<table_name output>"
#
# Ref: https://developer.hashicorp.com/terraform/language/backend/s3
# Analysis: Section 4 — "Add DynamoDB state locking"
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "lock" {
  count = var.enable_state_locking ? 1 : 0

  name         = "${var.bucket_prefix}-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Purpose   = "terraform-state-locking"
    Terraform = "true"
  }
}

output "bucket_name" {
  description = "Set this as GitHub variable TF_STATE_BUCKET"
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket (for IAM policy)"
  value       = aws_s3_bucket.state.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table for state locking (empty if disabled). Set as GitHub variable TF_LOCK_TABLE."
  value       = var.enable_state_locking ? aws_dynamodb_table.lock[0].name : ""
}
