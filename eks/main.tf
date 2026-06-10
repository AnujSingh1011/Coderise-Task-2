# ================================================================
# Root Configuration — dev EKS cluster
# Calls the three child modules: vpc → iam → eks-cluster
# ================================================================

# ── VPC ─────────────────────────────────────────────────────────
module "vpc" {
  source = "./mnt/user-data/outputs/infra/terraform/modules/eks/vpc"

  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = true

  tags = local.common_tags
}

module "iam" {
  source = "./mnt/user-data/outputs/infra/terraform/modules/eks/iam"

  cluster_name = local.cluster_name
  tags         = local.common_tags
}

module "eks" {
  source = "./mnt/user-data/outputs/infra/terraform/modules/eks/eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  node_labels = {
    environment = "dev"
    managed-by  = "terraform"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = local.common_tags
}

locals {
  cluster_name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}
