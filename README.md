# EKS Terraform — Remote State & CI/CD

> **Terraform state stored in S3 · State locking with DynamoDB · CI/CD via GitHub Actions**

---

## Table of Contents

1. [Repository Structure](#repository-structure)
2. [Architecture Overview](#architecture-overview)
3. [Prerequisites](#prerequisites)
4. [Backend Configuration](#backend-configuration)
5. [State Migration Steps](#state-migration-steps)
6. [GitHub Actions Workflow Overview](#github-actions-workflow-overview)
7. [How to Run and Validate the Configuration](#how-to-run-and-validate-the-configuration)
8. [GitHub Secrets Reference](#github-secrets-reference)
9. [Troubleshooting](#troubleshooting)

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml          # CI/CD pipeline
├── backend-bootstrap/
│   ├── main.tf                    # S3 bucket + DynamoDB table
│   ├── variables.tf
│   ├── outputs.tf
│   └── iam_github_actions.tf      # OIDC role for GitHub Actions
├── eks/
│   ├── backend.tf                 # Remote backend declaration
│   ├── main.tf                    # EKS cluster, VPC, node groups
│   ├── variables.tf
│   ├── outputs.tf
│   └── dev.tfvars                 # Per-environment variable overrides
├── .gitignore
└── README.md
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     GitHub Actions                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐  │
│  │   Init   │→ │   Fmt    │→ │ Validate │→ │  Plan  │  │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘  │
│                                                  │        │
│                                            ┌─────▼────┐  │
│                                            │  Apply   │  │
│                                            │(main only)│  │
└────────────────────────────────────────────┴─────┬────┘──┘
                                                   │ OIDC
                              ┌────────────────────▼──────────────────┐
                              │               AWS                      │
                              │  ┌─────────────┐  ┌────────────────┐  │
                              │  │  S3 Bucket  │  │  DynamoDB      │  │
                              │  │  (state)    │  │  (lock table)  │  │
                              │  └─────────────┘  └────────────────┘  │
                              │                                        │
                              │  ┌──────────────────────────────────┐  │
                              │  │         EKS Cluster              │  │
                              │  │  VPC · Node Groups · OIDC · KMS  │  │
                              │  └──────────────────────────────────┘  │
                              └────────────────────────────────────────┘
```

**State management flow:**

- Each `terraform apply` writes the updated state file to `s3://eks-platform-terraform-state-prod/eks/terraform.tfstate`.
- Before writing, Terraform acquires a lock by writing a record to the `eks-platform-terraform-locks` DynamoDB table. Concurrent runs are blocked until the lock is released.
- S3 versioning is enabled, so every previous state is recoverable.

---

## Prerequisites

| Tool | Min version | Install |
|------|------------|---------|
| Terraform | 1.6.0 | `brew install terraform` / [tfenv](https://github.com/tfutils/tfenv) |
| AWS CLI | 2.x | `brew install awscli` |
| kubectl | 1.29 | `brew install kubectl` |
| Git | 2.x | system package manager |

You also need:
- An AWS account with Admin or power-user permissions.
- A GitHub repository for this code.

---

## Backend Configuration

### What is the remote backend?

By default Terraform stores state locally (`terraform.tfstate`). Local state is dangerous for teams:
it cannot be shared, is not locked, and is easily lost. The **S3 remote backend** solves all three issues:

| Concern | Solution |
|---------|----------|
| State sharing | S3 bucket (accessible to all authorised AWS identities) |
| Concurrent apply | DynamoDB lock table (row-level lock on `LockID`) |
| History / rollback | S3 versioning (90-day non-current-version retention) |
| Encryption at rest | S3 SSE-S3 (`AES256`) |

### Resources created by `backend-bootstrap`

```hcl
# S3 — stores the .tfstate file
resource "aws_s3_bucket" "terraform_state" { ... }           # versioning + SSE + public-block

# DynamoDB — one row per workspace lock
resource "aws_dynamodb_table" "terraform_locks" {
  hash_key     = "LockID"
  billing_mode = "PAY_PER_REQUEST"
}
```

### Backend block in `eks/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "eks-platform-terraform-state-prod"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eks-platform-terraform-locks"
    encrypt        = true
  }
}
```

> **Tip:** Never hard-code the bucket name — pass it at `init` time via `-backend-config` or environment variables so the same code can target different environments.

---

## State Migration Steps

Follow these steps **once** when moving from local to remote state.

### Step 1 — Bootstrap the backend infrastructure

```bash
cd backend-bootstrap

# Initialise locally (no remote state yet for the bootstrap itself)
terraform init

# Review what will be created (S3 bucket, DynamoDB table, IAM role)
terraform plan -var="github_org=YOUR_ORG" -var="github_repo=YOUR_REPO"

# Apply — this provisions the backend infrastructure
terraform apply -var="github_org=YOUR_ORG" -var="github_repo=YOUR_REPO"
```

Note the outputs — you will need `state_bucket_name` and `dynamodb_table_name`.

### Step 2 — Configure GitHub Secrets

Copy the `github_actions_role_arn` output from Step 1 and add these secrets to
your GitHub repository (**Settings → Secrets and variables → Actions**):

| Secret name | Value |
|-------------|-------|
| `AWS_ROLE_ARN` | ARN from `github_actions_role_arn` output |
| `TF_STATE_BUCKET` | `eks-platform-terraform-state-prod` |
| `TF_LOCK_TABLE` | `eks-platform-terraform-locks` |

### Step 3 — Migrate existing local state

```bash
cd ../eks

# terraform init detects the new backend and offers to migrate state
terraform init -migrate-state \
  -backend-config="bucket=eks-platform-terraform-state-prod" \
  -backend-config="dynamodb_table=eks-platform-terraform-locks"
```

When prompted:

```
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend
  to the newly configured "s3" backend. No existing state was found in the
  newly configured "s3" backend. Do you want to copy this state to the new
  "s3" backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value: yes
```

### Step 4 — Verify the migration

```bash
# Confirm Terraform reads state from S3 with no drift
terraform plan -var-file=dev.tfvars

# Should end with: No changes. Your infrastructure matches the configuration.

# Also verify the state object exists in S3
aws s3 ls s3://eks-platform-terraform-state-prod/eks/
```

### Step 5 — Delete local state file

```bash
rm terraform.tfstate terraform.tfstate.backup
```

---

## GitHub Actions Workflow Overview

File: `.github/workflows/terraform.yml`

### Triggers

| Event | When it fires |
|-------|--------------|
| `push` to `main` | Any change under `eks/` or the workflow file |
| `pull_request` to `main` | Same path filters — runs plan only, posts result as PR comment |
| `workflow_dispatch` | Manual trigger with environment selector |

### Jobs

```
terraform-checks (Lint & Validate)
        │
        ▼
terraform-plan (Plan)
        │
        ▼ (main branch + push events only)
terraform-apply (Apply)
```

#### Job: `terraform-checks`

| Step | Command | Purpose |
|------|---------|---------|
| Checkout | `actions/checkout@v4` | Fetch repo |
| AWS Auth | `aws-actions/configure-aws-credentials@v4` | OIDC role assumption — no static keys |
| Setup TF | `hashicorp/setup-terraform@v3` | Pin Terraform version |
| **Init** | `terraform init` | Download providers, configure backend |
| **Fmt** | `terraform fmt -check -recursive -diff` | Enforce canonical formatting — fails if any file is not formatted |
| **Validate** | `terraform validate` | Static syntax/type check |
| PR Comment | `actions/github-script@v7` | Posts a pass/fail table to the pull request |

#### Job: `terraform-plan`

Runs after `terraform-checks`. Executes `terraform plan -var-file=<env>.tfvars` and:
- Saves the plan to a `.tfplan` binary artifact (retained 5 days).
- Posts full plan output as a PR comment (truncated at 65 000 chars to stay within GitHub limits).

#### Job: `terraform-apply`

Runs only on **push to `main`**. Downloads the plan artifact from the previous job and executes `terraform apply tfplan` — ensuring apply uses the exact plan that was reviewed, preventing drift.

### OIDC Authentication (no static AWS keys)

The workflow authenticates to AWS using [GitHub's OIDC provider](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services). The IAM role created in `backend-bootstrap/iam_github_actions.tf` trusts GitHub's token issuer, scoped to your specific repository:

```json
"Condition": {
  "StringLike": {
    "token.actions.githubusercontent.com:sub":
      "repo:YOUR_ORG/YOUR_REPO:*"
  }
}
```

This means **no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` secrets are needed**.

---

## How to Run and Validate the Configuration

### Local development workflow

```bash
# 1. Export your AWS credentials
export AWS_PROFILE=my-dev-profile   # or set AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY

# 2. Move into the EKS module
cd eks

# 3. Initialise (downloads providers, connects to remote state)
terraform init \
  -backend-config="bucket=eks-platform-terraform-state-prod" \
  -backend-config="dynamodb_table=eks-platform-terraform-locks"

# 4. Check formatting
terraform fmt -check -recursive -diff

# 5. Validate configuration
terraform validate

# 6. Plan against dev environment
terraform plan -var-file=dev.tfvars

# 7. Apply (interactive confirmation)
terraform apply -var-file=dev.tfvars
```

### Triggering the CI/CD pipeline

**Via Pull Request:**
1. Create a branch, make changes under `eks/`.
2. Open a PR to `main`.
3. GitHub Actions automatically runs Init → Fmt → Validate → Plan.
4. Review the plan comment posted to the PR.
5. Merge the PR → Apply runs automatically.

**Manual trigger:**
1. Go to **Actions** → **Terraform CI/CD** → **Run workflow**.
2. Select the target environment (`dev` / `staging` / `prod`).
3. Click **Run workflow**.

### Validating state locking

To confirm locking works, attempt two concurrent plans:

```bash
# Terminal 1
terraform plan -var-file=dev.tfvars

# Terminal 2 (immediately after Terminal 1)
terraform plan -var-file=dev.tfvars
# Expected output:
# Error: Error acquiring the state lock
# Lock Info:
#   ID:   <uuid>
#   ...
#   Info: terraform plan
```

### Viewing state in S3

```bash
# List state versions
aws s3api list-object-versions \
  --bucket eks-platform-terraform-state-prod \
  --prefix eks/terraform.tfstate \
  --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified}'

# Download a specific version for inspection
aws s3api get-object \
  --bucket eks-platform-terraform-state-prod \
  --key eks/terraform.tfstate \
  --version-id <VERSION_ID> \
  state-backup.json
```

### Verifying the EKS cluster

```bash
# Update local kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-platform-prod

# Confirm connectivity
kubectl get nodes
kubectl get namespaces
```

---

## GitHub Secrets Reference

| Secret | Description | Required |
|--------|-------------|----------|
| `AWS_ROLE_ARN` | IAM role ARN for OIDC auth | ✅ |
| `TF_STATE_BUCKET` | S3 bucket name for state storage | ✅ |
| `TF_LOCK_TABLE` | DynamoDB table name for locks | ✅ |
| `AWS_ACCESS_KEY_ID` | Fallback: static key (avoid in favour of OIDC) | ⚠️ |
| `AWS_SECRET_ACCESS_KEY` | Fallback: static secret (avoid in favour of OIDC) | ⚠️ |

---

## Troubleshooting

### `Error: Failed to get existing workspaces: S3 bucket does not exist`

The backend S3 bucket has not been created yet. Run the `backend-bootstrap` module first (see [Step 1](#step-1--bootstrap-the-backend-infrastructure)).

### `Error: Error acquiring the state lock`

Another process holds the lock. If you are sure no other apply is running (e.g. a previous run crashed), force-unlock:

```bash
terraform force-unlock <LOCK_ID>
# LOCK_ID is printed in the error message
```

### `Error: No valid credential sources found`

AWS credentials are not configured. Check `AWS_PROFILE`, `AWS_ACCESS_KEY_ID`, or the OIDC role trust policy.

### `terraform fmt -check` fails in CI

Run `terraform fmt -recursive` locally, commit the formatted files, and push again.

### Plan artifact not found during Apply

The apply job downloads the artifact uploaded by the Plan job. If the Plan job was skipped or failed, the artifact does not exist. Re-run the workflow from the Plan stage.

---

## Security Considerations

- **State encryption** — all state files are encrypted with AES-256 at rest (SSE-S3). For stricter requirements, switch to `aws:kms`.
- **Least-privilege IAM** — the GitHub Actions role in `iam_github_actions.tf` grants only the permissions needed for EKS, VPC, and state operations. Review and tighten before production use.
- **No secrets in state** — sensitive outputs (`cluster_endpoint`, `cluster_certificate_authority`) are marked `sensitive = true` to prevent accidental logging.
- **Prevent-destroy lifecycle** — the S3 bucket and DynamoDB table have `prevent_destroy = true`. Remove this only when intentionally decommissioning the backend.
