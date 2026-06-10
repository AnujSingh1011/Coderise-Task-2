terraform {
  backend "s3" {
    bucket         = "anuj-terraform-state-bucket-981777"
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "anuj-terraform-locks"
    encrypt        = true
  }
}