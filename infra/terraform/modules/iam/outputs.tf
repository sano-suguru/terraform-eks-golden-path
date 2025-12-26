# IAM モジュール出力

output "aws_load_balancer_controller_role_arn" {
  description = "AWS Load Balancer Controller用IAM Role ARN"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "aws_load_balancer_controller_role_name" {
  description = "AWS Load Balancer Controller用IAM Role名"
  value       = aws_iam_role.aws_load_balancer_controller.name
}

output "aws_load_balancer_controller_policy_arn" {
  description = "AWS Load Balancer Controller用IAM Policy ARN"
  value       = aws_iam_policy.aws_load_balancer_controller.arn
}
