# infra/terraform — EKS Cluster via Terraform Modules

Provisions a production-style AWS EKS cluster using reusable Terraform modules.

---

## What are Terraform Modules?

A **Terraform module** is a folder of `.tf` files that encapsulates a set of related resources.
Instead of copy-pasting the same VPC or IAM code across every environment, you write it once as
a module and *call* it with different inputs.

| Concept | Meaning |
|---|---|
| **Root module** | The folder you run `terraform apply` in (`environments/dev/`) |
| **Child module** | A reusable block called via a `module {}` block (`modules/eks/…`) |
| **Input variables** | `variables.tf` — what the caller must/can pass in |
| **Outputs** | `outputs.tf` — values the module exposes to the caller |

```
Root module calls child modules:

environments/dev/main.tf
  └── module "vpc"   → modules/eks/vpc/
  └── module "iam"   → modules/eks/iam/
  └── module "eks"   → modules/eks/eks-cluster/
```

---

## Repository Layout

```
infra/terraform/
├── .gitignore
├── README.md
│
├── modules/
│   └── eks/
│       ├── vpc/                  # VPC, subnets, NAT, route tables
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       ├── iam/                  # Cluster role + node role + policy attachments
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       └── eks-cluster/          # EKS control plane + managed node group
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── versions.tf
│
└── environments/
    └── dev/                      # Root module — deploy the dev cluster here
        ├── main.tf               # Calls all three modules
        ├── variables.tf
        ├── outputs.tf
        ├── providers.tf          # AWS + Kubernetes provider config
        └── terraform.tfvars.example
```

---

## What Gets Created

| Resource | Details |
|---|---|
| **VPC** | `/16` CIDR, DNS enabled |
| **Subnets** | 2× public + 2× private (across 2 AZs) |
| **NAT Gateway** | 1 (shared, cost-efficient for dev) |
| **IAM Roles** | EKS cluster role + worker node role with required AWS managed policies |
| **EKS Cluster** | Control plane with API + audit + authenticator logs |
| **Managed Node Group** | `t3.medium` × 2 nodes, auto-scaling 1–4 |

---

## Prerequisites

| Tool | Version |
|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | ≥ 1.5 |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | ≥ 2.x |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.27 |

You need an AWS account with permissions to create VPCs, IAM roles, and EKS clusters.

---

## Deploy the Dev Cluster

### 1. Configure credentials

```bash
aws configure          # enter Access Key, Secret Key, region
# or export AWS_PROFILE=your-named-profile
```

### 2. Set your variable values

```bash
cd infra/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — change project name, region, etc.
```

### 3. Initialise & preview

```bash
terraform init
terraform plan
```

`plan` shows every resource Terraform will create. Review it carefully before applying.

### 4. Deploy

```bash
terraform apply
# Type 'yes' when prompted
```

Cluster creation takes **10–15 minutes**.

### 5. Configure kubectl

After `apply` completes, Terraform prints a `kubeconfig_command` output.  Run it:

```bash
aws eks update-kubeconfig --region us-east-1 --name myapp-dev
```

### 6. Verify the cluster is running

```bash
kubectl get nodes
```

Expected output (node names will differ):

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-1-23.ec2.internal     Ready    <none>   3m    v1.29.x
ip-10-0-2-45.ec2.internal     Ready    <none>   3m    v1.29.x
```

Both nodes should show `Ready`. Done! ✅

---

## Tear Down

```bash
terraform destroy
# Type 'yes' to confirm
```

This removes **all** resources created by Terraform, including the VPC and EKS cluster.

---

## Module Inputs Reference

### `modules/eks/vpc`

| Variable | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | — | Cluster name (used for tagging) |
| `vpc_cidr` | string | `10.0.0.0/16` | VPC CIDR block |
| `az_count` | number | `2` | Number of AZs (2 or 3) |
| `single_nat_gateway` | bool | `true` | Use one NAT GW (dev) vs one per AZ (prod) |
| `tags` | map(string) | `{}` | Tags applied to all resources |

### `modules/eks/iam`

| Variable | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | — | Cluster name (prefix for role names) |
| `tags` | map(string) | `{}` | Tags applied to IAM roles |

### `modules/eks/eks-cluster`

| Variable | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | — | EKS cluster name |
| `kubernetes_version` | string | `1.29` | Kubernetes version |
| `vpc_id` | string | — | VPC ID |
| `public_subnet_ids` | list(string) | — | Public subnet IDs |
| `private_subnet_ids` | list(string) | — | Private subnet IDs |
| `cluster_role_arn` | string | — | IAM role ARN for control plane |
| `node_role_arn` | string | — | IAM role ARN for nodes |
| `node_instance_types` | list(string) | `["t3.medium"]` | EC2 instance types |
| `node_capacity_type` | string | `ON_DEMAND` | `ON_DEMAND` or `SPOT` |
| `node_desired_size` | number | `2` | Desired node count |
| `node_min_size` | number | `1` | Minimum node count |
| `node_max_size` | number | `4` | Maximum node count |

---

## Promoting to Staging / Prod

This repo uses the **environments-as-directories** pattern.  To add a staging cluster:

```bash
cp -r environments/dev environments/staging
# Edit staging/terraform.tfvars — change instance types, node counts, single_nat_gateway = false
```

The modules are shared; only the inputs change.

---

## Useful Commands

```bash
# Format all Terraform files
terraform fmt -recursive

# Validate configs without making API calls
terraform validate

# Show current state
terraform show

# Target a single module (useful for debugging)
terraform plan -target=module.vpc
```
