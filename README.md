# terraform-eks-golden-path

Platform Engineering ポートフォリオ：EKS + kind の二段構えで「Golden Path（標準化）+ Guardrails（強制力）+ Reproducibility（再現性）」を実証する。

## What / Why

このリポジトリは、新規サービスが**運用可能な形で立ち上がる標準ルート**を提供します。

- **Golden Path**: ログ・メトリクス・ヘルスチェック・デプロイ方式が標準化
- **Guardrails**: CI で品質・セキュリティを強制（人の善意に依存しない）
- **Reproducibility**: ローカル（kind）でもクラウド（EKS）でも同じ方法で動く

## Golden Path（標準ルート）

このリポジトリが定義する「新規サービスの標準」：

### ロギング

- **形式**: JSON 構造化ログ（`log/slog`）
- **必須フィールド**: `method`, `path`, `status`, `latency_ms`
- **除外**: `/healthz`, `/readyz`, `/metrics` はログ出力しない（ノイズ回避）

### メトリクス

- **形式**: Prometheus 形式（`/metrics` エンドポイント）
- **必須メトリクス**:
  - `http_requests_total{method,path,status}` - リクエストカウンター
  - `http_request_duration_seconds{method,path}` - レイテンシヒストグラム

### ヘルスチェック

| エンドポイント | 用途 | 仕様 |
|---------------|------|------|
| `/healthz` | Liveness | 常に 200（依存なし） |
| `/readyz` | Readiness | 初期化完了後に 200 |

### デプロイ

- **方式**: Helm チャート（kind/EKS 共通）
- **環境差分**: `values-kind.yaml` / `values-eks.yaml` で吸収
- **イメージ配布**: GHCR（GitHub Container Registry）で Public イメージ

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

### ローカル CI 実行

PR 作成前にローカルで CI チェックを一括実行できます：

```bash
# 全 CI チェック（lint, test, docker build, helm lint, terraform fmt/validate）
make ci

# クイックチェック（lint + test のみ）
make ci-quick
```

### Git Hooks（開発者体験の向上）

[lefthook](https://github.com/evilmartians/lefthook) を使用して、コミット/プッシュ前に自動チェックを実行します：

```bash
# Git hooks をインストール
make hooks-install

# hooks をスキップしたい場合
LEFTHOOK=0 git commit -m "skip hooks"
```

| フック | タイミング | 実行内容 | スキップ条件 |
|-------|-----------|---------|-------------|
| pre-commit | コミット前 | Go lint/fmt, Terraform fmt | merge, rebase |
| pre-push | プッシュ前 | Go test | merge, rebase |

> 💡 **hooks は任意です**。CI が最終的なガードレールとして機能するため、hooks をスキップしても品質は担保されます。merge/rebase 時は自動的にスキップされます。

## Architecture

詳細なアーキテクチャ図は [docs/architecture.md](docs/architecture.md) を参照してください。

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

### SLO（Service Level Objectives）

| 指標 | 目標 | 計測窓 |
|-----|------|-------|
| 成功率 | 99.9% | 5分 |
| p95 レイテンシ | < 200ms | 5分 |

### SLI（Service Level Indicators）

- **成功率**: `100 * (1 - sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])))`
- **p95 レイテンシ**: `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))`

### Grafana ダッシュボード

```bash
make obs-up        # kube-prometheus-stack をインストール
make kind-grafana  # http://localhost:3000 (admin/prom-operator)
```

#### ダッシュボード一覧

| ファイル | 説明 |
|---------|------|
| `grafana-dashboard.json` | 基本メトリクス（RPS, Error Rate, Latency） |
| `grafana-slo-dashboard.json` | SLO/SLI 専用（目標達成率、Error Budget） |

**SLO ダッシュボードのインポート手順**:

1. Grafana にログイン（admin / prom-operator）
2. Dashboards → Import
3. `deploy/kind/grafana-slo-dashboard.json` をアップロード

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

| チェック | 説明 | 失敗条件 |
|---------|------|----------|
| `go test` | ユニットテスト | テスト失敗 |
| `golangci-lint` | Go コード品質 | lint 違反 |
| `docker build` | イメージビルド | ビルド失敗 |
| **Trivy** | 脆弱性スキャン | CRITICAL/HIGH 検出 |
| **Syft SBOM** | SBOM 生成 | - |
| `helm lint` | Helm チャート検証 | lint 違反 |
| `terraform fmt` | フォーマットチェック | 未フォーマット |
| `terraform validate` | 構文チェック | 構文エラー |
| **Conftest/OPA** | Policy as Code | ポリシー違反 |

### SBOM（Software Bill of Materials）

CI でビルドされた Docker イメージから [Syft](https://github.com/anchore/syft) を使用して SBOM を自動生成します：

- **形式**: SPDX JSON（業界標準）
- **保存期間**: 90 日間
- **用途**: サプライチェーンセキュリティ、脆弱性追跡、ライセンスコンプライアンス

SBOM は GitHub Actions のアーティファクトからダウンロード可能です。

### Policy as Code

`infra/terraform/policies/` に OPA/Rego ポリシーを定義し、Terraform plan に対してセキュリティチェックを実行します：

| ポリシー | 説明 |
|---------|------|
| `deny_public_sg.rego` | 0.0.0.0/0 からの SSH / 全ポート開放を禁止 |
| `deny_public_s3.rego` | S3 バケットの public ACL を禁止 |
| `required_tags.rego` | 必須タグ（Environment, Project, ManagedBy）の警告 |

ローカルで実行：

```bash
cd infra/terraform/envs/dev
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
conftest test tfplan.json -p ../../policies
```

### GitHub Actions OIDC（AWS認証）

PR 時に自動で `terraform plan` を実行するには、AWS OIDC Provider の設定が必要です：

#### 1. AWS OIDC Provider の作成

```bash
# AWS コンソールまたは CLI で作成
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### 2. IAM ロールの作成

信頼ポリシー例：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:*"
        }
      }
    }
  ]
}
```

#### 3. GitHub リポジトリ変数の設定

Settings → Variables → Repository variables に以下を追加：

| 変数名 | 値 |
|--------|-----|
| `AWS_OIDC_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>` |

設定完了後、PR を作成すると自動で `terraform plan` が実行され、結果が PR コメントに投稿されます。

## Security

### Pod Security Standards (PSS)

Kubernetes の Pod Security Standards に準拠し、**restricted** レベルを適用：

- `runAsNonRoot: true` - root ユーザーでの実行を禁止
- `allowPrivilegeEscalation: false` - 特権昇格を禁止
- `seccompProfile: RuntimeDefault` - Seccomp プロファイルを強制
- `capabilities.drop: [ALL]` - すべての Linux capability を削除

```yaml
# Namespace に PSS ラベルを適用
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/warn: restricted
pod-security.kubernetes.io/audit: restricted
```

### 脆弱性スキャン（Trivy）

CI で Docker イメージの脆弱性をスキャン：

- **検出レベル**: CRITICAL, HIGH
- **動作**: 脆弱性検出時に CI を失敗させる
- **スキップ**: 修正未提供の脆弱性は無視（`ignore-unfixed: true`）

### 公開面（Exposure）

- 外部公開は**必要なパスのみ**（`/`, `/healthz`, `/readyz`）
- `/metrics` は外部公開しない（クラスター内からのみアクセス可能）
- 管理系エンドポイント（`/debug` 等）は実装しない

### 権限（Least Privilege）

- AWS Load Balancer Controller は **IRSA** で最小権限
- Terraform 実行権限は環境分離を想定（dev/stg/prod）
- CI からの AWS 認証は **OIDC** を推奨（長期認証情報を避ける）

### 機密（Secrets）

- 機密情報は Git に置かない
- Kubernetes Secret または外部 Secret 管理（AWS Secrets Manager 等）を使用
- このリポジトリはダミー値で動作し、実運用時に Secret を投入する設計

### 変更管理（Change Management）

- すべての変更は PR 経由（main への直接 push 禁止）
- CI で自動チェック（lint, test, terraform validate, policy check）
- Terraform plan は PR コメントで可視化

## 設計上のトレードオフ

このリポジトリは**ローカルで即座に動作確認できる**ことを優先した設計です。

| 選択 | 理由 | 本番向け代替 |
|-----|------|-------------|
| HTTP のみ | 独自ドメイン不要で即座に検証可能 | Route53 + ACM で HTTPS 化 |
| Public Subnet | NAT Gateway 不要でコスト最小 | Private Subnet + NAT 構成 |
| ローカル state | 追加の AWS 設定不要 | S3 + DynamoDB でチーム共有 |

## 本番環境への拡張

### HTTPS 対応（Route53 + ACM）

```yaml
# values-eks.yaml に追加
ingress:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
```

### Private Subnet 構成

NAT Gateway を追加し、ノードを Private Subnet に配置：

```hcl
# modules/vpc で private_subnets を追加
# modules/eks で subnet_ids を private に変更
```

### Terraform State のリモート管理

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "terraform-eks-golden-path/dev/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}
```

## Runbooks

- [高エラー率への対応](docs/runbook-high-error-rate.md)
- [レイテンシ劣化への対応](docs/runbook-latency-regression.md)

## License

MIT
