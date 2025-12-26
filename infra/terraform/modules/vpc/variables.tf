# VPC モジュール変数

variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "env" {
  description = "環境名"
  type        = string
}

variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public SubnetのCIDRブロック"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKSクラスター名（タグ用）"
  type        = string
}
