# ── dev.tfvars ────────────────────────────────────────────────────────────
# Usage: terraform plan -var-file=dev.tfvars

aws_region         = "us-east-1"
project_name       = "eks-platform"
environment        = "dev"
kubernetes_version = "1.29"

# Networking
vpc_cidr        = "10.0.0.0/16"
private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# Allow public API access from your office/VPN CIDR in dev
cluster_public_access      = true
cluster_public_access_cidrs = ["10.0.0.0/8"]

# Smaller, cheaper nodes for dev
node_instance_types = ["t3.medium"]
node_capacity_type  = "SPOT"
node_desired_size   = 1
node_min_size       = 1
node_max_size       = 3
