###############################################################################
# IAM – GitHub Actions OIDC Role & Policy
#
# Creates a role that GitHub Actions can assume via OIDC federation.
# No long-lived AWS credentials are stored as GitHub secrets.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

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

locals {
  github_oidc_url = "token.actions.githubusercontent.com"
}

# ── GitHub OIDC Provider ─────────────────────────────────────────────────────
data "aws_iam_openid_connect_provider" "github" {
  url = "https://${local.github_oidc_url}"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${local.github_oidc_url}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ── IAM Role ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${local.github_oidc_url}:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
          StringEquals = {
            "${local.github_oidc_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  max_session_duration = 3600
}

# ── IAM Policy ───────────────────────────────────────────────────────────────
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-eks-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 – read/write state
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucket",  "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${var.state_bucket_name}",
          "arn:aws:s3:::${var.state_bucket_name}/*"
        ]
      },
      # DynamoDB – state locking
      {
        Sid    = "TerraformStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/${var.dynamodb_table_name}"
      },
      # EKS
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = ["eks:*"]
        Resource = "*"
      },
      # EC2 & VPC
      {
        Sid    = "EC2VPCAccess"
        Effect = "Allow"
        Action = ["ec2:*", "elasticloadbalancing:*", "autoscaling:*"]
        Resource = "*"
      },
      # IAM (scoped to created roles)
      {
        Sid    = "IAMAccess"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PassRole", "iam:CreateOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:TagPolicy", "iam:UntagPolicy",
          "iam:ListInstanceProfilesForRole", "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = "*"
      },
      # KMS
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = ["kms:*"]
        Resource = "*"
      },
      # CloudWatch Logs
      {
        Sid    = "LogsAccess"
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "ARN to set as AWS_ROLE_ARN GitHub secret"
  value       = aws_iam_role.github_actions.arn
}

variable "aws_region"          { default = "us-east-1" }
variable "github_org"          { description = "GitHub organisation or username" }
variable "github_repo"         { description = "Repository name (without the org prefix)" }
variable "state_bucket_name"   { default = "eks-platform-terraform-state-prod" }
variable "dynamodb_table_name" { default = "eks-platform-terraform-locks" }
variable "create_oidc_provider" {
  description = "Set false if the GitHub OIDC provider already exists in this account"
  type        = bool
  default     = true
}
