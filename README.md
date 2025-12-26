# terraform-eks-golden-path

Platform Engineering ポートフォリオ：EKS + kind の二段構えで「Golden Path（標準化）+ Guardrails（強制力）+ Reproducibility（再現性）」を実証する。

## What / Why

このリポジトリは、新規サービスが**運用可能な形で立ち上がる標準ルート**を提供します。

- **Golden Path**: ログ・メトリクス・ヘルスチェック・デプロイ方式が標準化
- **Guardrails**: CI で品質・セキュリティを強制（人の善意に依存しない）
- **Reproducibility**: ローカル（kind）でもクラウド（EKS）でも同じ方法で動く

## Quickstart（5分）

### 前提ツール

- [kind](https://kind.sigs.k8s.io/) 0.20+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) 1.28+
- [Helm](https://helm.sh/) 3.x
- [Docker](https://www.docker.com/)

### 手順

```bash
# 1. kind クラスター作成（ingress-nginx 込み）
make kind-up

# 2. アプリをデプロイ
make kind-deploy

# 3. 動作確認
curl http://localhost/healthz
# => {"status":"ok"}

# 4. 片付け
make kind-down
```

## Architecture

```text
app/                    # Go HTTP API
deploy/
  helm/                 # Helm chart（kind/EKS 共通）
  kind/                 # kind 設定ファイル
infra/terraform/        # EKS インフラ（Terraform）
  envs/dev/             # 環境定義
  modules/              # vpc, eks, iam モジュール
```

### Endpoints

| Path       | Description                        |
| ---------- | ---------------------------------- |
| `/`        | Hello レスポンス                   |
| `/healthz` | Liveness probe（依存なし）         |
| `/readyz`  | Readiness probe（初期化完了後 OK） |
| `/metrics` | Prometheus メトリクス（内部のみ）  |

## Observability

### SLI

- **成功率**: 2xx / total（5 分窓）
- **レイテンシ**: p95（5 分窓）

### Grafana ダッシュボード

```bash
make obs-up        # kube-prometheus-stack をインストール
make kind-grafana  # http://localhost:3000 (admin/prom-operator)
```

## EKS デプロイ

> ⚠️ **注意**: AWS 料金が発生します。検証後は必ず `make eks-destroy` を実行してください。

### 前提条件

- AWS CLI 2.x（認証設定済み）
- Terraform 1.x
- kubectl / Helm 3.x
- EKS/EC2/VPC/IAM/ELB の作成権限

### コスト発生リソース

| リソース | 概算コスト |
|---------|-----------|
| EKS コントロールプレーン | ~$0.10/時 |
| EC2 ノード（t3.medium x2） | ~$0.08/時 |
| ALB | ~$0.02/時 + 転送量 |

**1日放置で約$5〜10 発生します。検証後は必ず削除してください。**

### 手順

```bash
# 1. Terraform 初期化
make tf-init

# 2. EKS 構築（約15分）
make eks-apply

# 3. kubeconfig 設定
make eks-kubeconfig

# 4. AWS Load Balancer Controller 導入（IRSA使用）
make eks-install-lbc

# 5. アプリデプロイ
make eks-deploy

# 6. ALB DNS 確認（払い出しに数分かかる）
make eks-url
# => http://xxxxx.elb.amazonaws.com

# 7. 動作確認
curl http://$(make eks-url)/healthz

# 8. 片付け（必須！）
make eks-destroy
```

### Terraform が作成するリソース

- VPC（3 AZ パブリックサブネット）
- EKS クラスター（v1.31）
- マネージドノードグループ（t3.medium x2）
- OIDC Provider（IRSA 用）
- IAM ロール（AWS Load Balancer Controller 用）

## CI/Guardrails

以下が CI で自動チェックされます：

- `go test` / `golangci-lint`
- `terraform fmt -check` / `terraform validate`
- `docker build`
- `helm lint`

## Runbooks

- [高エラー率への対応](docs/runbook-high-error-rate.md)
- [レイテンシ劣化への対応](docs/runbook-latency-regression.md)

## License

MIT
