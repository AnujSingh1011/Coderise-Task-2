variable "cluster_name" {
  description = "Name of the EKS cluster — used as a prefix for IAM role names."
  type        = string
}

variable "tags" {
  description = "Tags to apply to IAM roles."
  type        = map(string)
  default     = {}
}
