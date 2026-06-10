variable "aws_region" {
  default = "ap-south-1"
}

variable "state_bucket_name" {
  default = "anuj-terraform-state-bucket-981777"
}

variable "dynamodb_table_name" {
  default = "anuj-terraform-locks"
}