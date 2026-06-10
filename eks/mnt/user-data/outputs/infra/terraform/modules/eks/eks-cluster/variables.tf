variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster (e.g. '1.29')."
  type        = string
  default     = "1.30"
}

# ── Networking ────────────────────────────────────────
variable "vpc_id" {
  description = "VPC ID where the cluster will be created."
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (used for the cluster endpoint)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (where worker nodes are placed)."
  type        = list(string)
}

# ── IAM ───────────────────────────────────────────────
variable "cluster_role_arn" {
  description = "ARN of the IAM role for the EKS control plane."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the IAM role for the EKS worker nodes."
  type        = string
}

# ── Logging ───────────────────────────────────────────
variable "enabled_cluster_log_types" {
  description = "List of control plane log types to enable (api, audit, authenticator, controllerManager, scheduler)."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

# ── Node Group ────────────────────────────────────────
variable "node_group_name" {
  description = "Suffix for the managed node group name."
  type        = string
  default     = "default"
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Node capacity type: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_labels" {
  description = "Kubernetes labels to apply to nodes."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all EKS resources."
  type        = map(string)
  default     = {}
}
