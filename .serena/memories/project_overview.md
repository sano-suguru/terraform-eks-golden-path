# terraform-eks-golden-path プロジェクト概要

## 目的

Platform Engineering ポートフォリオとして、EKS + kind の二段構えで以下を実証する：

- **Golden Path（標準化）**: 新規サービスが迷わず立ち上がる標準ルート
- **Guardrails（強制力）**: CI で品質・セキュリティを強制
- **Reproducibility（再現性）**: ローカル（kind）でもクラウド（EKS）でも同じ方法で動作

## Tech Stack

### アプリケーション

- **言語**: Go 1.25
- **フレームワーク**: 標準ライブラリ（net/http）
- **ロギング**: log/slog（JSON構造化ログ）
- **メトリクス**: prometheus/client_golang

### インフラ

- **IaC**: Terraform 1.7.0
- **コンテナオーケストレーション**: Kubernetes
  - ローカル: kind
  - クラウド: AWS EKS (v1.31)
- **パッケージ管理**: Helm 3.x
- **Ingress**: 
  - kind: ingress-nginx
  - EKS: AWS Load Balancer Controller (ALB)
- **観測性**: kube-prometheus-stack（Prometheus + Grafana）

### CI/CD

- **CI**: GitHub Actions
- **Policy as Code**: Conftest/OPA (Rego)
- **イメージレジストリ**: GHCR (GitHub Container Registry)

## ディレクトリ構造

```
app/                          # Go HTTP API
  cmd/api/main.go             # エントリーポイント
  internal/handler/           # HTTPハンドラー + メトリクス
  internal/middleware/        # ロギングミドルウェア
deploy/
  helm/golden-path-api/       # Helm chart（kind/EKS共通）
  kind/                       # kind設定、Prometheus values
infra/terraform/
  envs/dev/                   # 環境定義
  modules/vpc/                # VPC, サブネット
  modules/eks/                # EKSクラスター
  modules/iam/                # IRSA (AWS LBC用)
  policies/                   # OPA/Rego ポリシー
.github/workflows/            # CI ワークフロー
docs/                         # ドキュメント、Runbook
```
