terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
  }

  # ── Remote state backend (uncomment and fill in for team use) ──
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "dev/eks/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# The kubernetes provider must be configured dynamically using the
# cluster endpoint and certificate from the EKS module outputs.
 provider "kubernetes" {
  config_path = "~/.kube/config"
}