# 環境変数定義
# spec 16.3: 最低限の変数

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名（リソース命名のprefix）"
  type        = string
  default     = "terraform-eks-golden-path"
}

variable "env" {
  description = "環境名（dev/stg/prod）"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public SubnetのCIDRブロック（AZ毎）"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "kubernetes_version" {
  description = "EKSのKubernetesバージョン"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "EKSノードのインスタンスタイプ"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "ノードグループの希望ノード数"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "ノードグループの最小ノード数"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "ノードグループの最大ノード数"
  type        = number
  default     = 3
}

# 導出変数（ローカル値）
locals {
  cluster_name = "${var.project_name}-${var.env}"

  common_tags = {
    Project     = var.project_name
    Environment = var.env
  }
}
