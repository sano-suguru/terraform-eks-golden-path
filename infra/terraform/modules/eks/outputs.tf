# EKS モジュール出力

output "cluster_name" {
  description = "EKSクラスター名"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS APIエンドポイント"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS CA証明書（base64）"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKSクラスターのセキュリティグループID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN（IRSA用）"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC Provider URL（IRSA用）"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "node_group_name" {
  description = "ノードグループ名"
  value       = aws_eks_node_group.main.node_group_name
}
