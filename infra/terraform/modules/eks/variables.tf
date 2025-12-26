# EKS モジュール変数

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

variable "kubernetes_version" {
  description = "Kubernetesバージョン"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "EKSを配置するサブネットID"
  type        = list(string)
}

variable "node_instance_types" {
  description = "ノードのインスタンスタイプ"
  type        = list(string)
}

variable "node_desired_size" {
  description = "希望ノード数"
  type        = number
}

variable "node_min_size" {
  description = "最小ノード数"
  type        = number
}

variable "node_max_size" {
  description = "最大ノード数"
  type        = number
}
