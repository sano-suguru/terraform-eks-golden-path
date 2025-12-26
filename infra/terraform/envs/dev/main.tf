# メインエントリーポイント
# 各モジュールを呼び出してEKS環境を構築

# VPC モジュール
module "vpc" {
  source = "../../modules/vpc"

  project_name        = var.project_name
  env                 = var.env
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  cluster_name        = local.cluster_name
}

# EKS モジュール
module "eks" {
  source = "../../modules/eks"

  project_name        = var.project_name
  env                 = var.env
  cluster_name        = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.public_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

# IAM モジュール（AWS Load Balancer Controller用IRSA）
module "iam" {
  source = "../../modules/iam"

  project_name      = var.project_name
  env               = var.env
  cluster_name      = local.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}
