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

```bash
# 1. Terraform で EKS 構築
make tf-init
make eks-apply

# 2. kubeconfig 設定
make eks-kubeconfig

# 3. AWS Load Balancer Controller 導入
make eks-install-lbc

# 4. アプリデプロイ
make eks-deploy

# 5. ALB DNS 確認
make eks-url

# 6. 片付け
make eks-destroy
```

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
