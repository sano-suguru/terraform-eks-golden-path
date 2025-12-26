# IAM モジュール
# AWS Load Balancer Controller用のIRSA（IAM Role for Service Account）

# AWS Load Balancer Controller用IAMポリシー
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${var.project_name}-${var.env}-aws-lb-controller-policy"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = file("${path.module}/policies/aws-load-balancer-controller-policy.json")

  tags = {
    Name = "${var.project_name}-${var.env}-aws-lb-controller-policy"
  }
}

# AWS Load Balancer Controller用IAMロール（IRSA）
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.project_name}-${var.env}-aws-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.env}-aws-lb-controller-role"
  }
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# ServiceAccount（Kubernetes側で作成するための情報をOutputで提供）
# 実際のServiceAccountはHelmまたはkubectlで作成する
