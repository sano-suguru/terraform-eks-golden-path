# Terraform と Provider のバージョン制約
# spec 16.1: ローカルstateで動く前提で開始

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }

  # 本番環境では S3 backend + DynamoDB lock を推奨
  # backend "s3" {
  #   bucket         = "terraform-eks-golden-path-tfstate"
  #   key            = "dev/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   dynamodb_table = "terraform-eks-golden-path-tflock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}
