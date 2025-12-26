# 出力値定義
# spec 16.4: 必要なoutputs

output "cluster_name" {
  description = "EKSクラスター名"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS APIエンドポイント"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "EKS CA証明書（base64）"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "aws_load_balancer_controller_role_arn" {
  description = "AWS Load Balancer Controller用IAM Role ARN（IRSA）"
  value       = module.iam.aws_load_balancer_controller_role_arn
}

# kubeconfig更新コマンド
output "kubeconfig_command" {
  description = "kubectlの認証情報を更新するコマンド"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}
