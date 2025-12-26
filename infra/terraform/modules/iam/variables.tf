# IAM モジュール変数

variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "env" {
  description = "環境名"
  type        = string
}

variable "cluster_name" {
  description = "EKSクラスター名"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC Provider ARN"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC Provider URL（https://なし）"
  type        = string
}
