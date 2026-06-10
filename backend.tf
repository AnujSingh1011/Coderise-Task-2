###############################################################################
# Remote Backend Configuration
# Stores Terraform state in S3 and uses DynamoDB for state locking.
#
# MIGRATION STEPS (one-time):
#   1. Run the backend-bootstrap module to create the S3 bucket & DynamoDB table.
#   2. Add this file (or uncomment the backend block) to your existing EKS config.
#   3. Run: terraform init -migrate-state
#   4. Confirm the prompt to copy local state to S3.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # ── Remote Backend ──────────────────────────────────────────────────────
  backend "s3" {
    bucket = "eks-platform-terraform-state-prod" # created by backend-bootstrap
    key    = "eks/terraform.tfstate"
    region = "us-east-1"

    # State locking – prevents concurrent runs from corrupting state
    dynamodb_table = "eks-platform-terraform-locks"

    # Always encrypt state at rest
    encrypt = true
  }
}
