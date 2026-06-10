variable "cluster_name" {
  description = "Name of the EKS cluster — used for tagging and naming VPC resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to span (creates one public + one private subnet per AZ)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 for EKS HA requirements."
  }
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cheaper for dev). Set false for HA in prod."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}
