# Golden Path Starter - 技術解説

このドキュメントでは、本リポジトリの設計思想と実装のポイントを解説します。

## システムの目的

「新規サービスを運用可能な形で立ち上げる」 - これが Platform Engineering の最重要課題です。

新しいサービスを作るたびに、ログ形式、メトリクス、ヘルスチェック、デプロイ方法を一から決めていては、チームごとに異なる方式が乱立し、運用負荷が増大します。本システムは、**Golden Path（標準ルート）+ Guardrails（強制力）+ Reproducibility（再現性）** の3つの仕組みでこの課題を解決しています。

## プロジェクト構成

```
terraform-eks-golden-path/
├── app/                          # Go HTTP API
│   ├── cmd/api/main.go           # エントリーポイント、グレースフルシャットダウン
│   └── internal/                 # ハンドラー、ミドルウェア
├── deploy/
│   ├── helm/golden-path-api/     # Helm チャート（kind/EKS 共通）
│   │   ├── values.yaml           # 共通設定
│   │   ├── values-kind.yaml      # kind 用オーバーライド
│   │   └── values-eks.yaml       # EKS 用オーバーライド
│   └── kind/                     # kind 設定、Prometheus values
├── infra/terraform/              # EKS インフラ
│   ├── envs/dev/                 # 環境定義
│   ├── modules/                  # vpc, eks, iam モジュール
│   └── policies/                 # OPA/Conftest ポリシー
└── docs/                         # ドキュメント
```

**設計方針**: 依存関係は「外側から内側へ」の一方向のみ。アプリケーションは Kubernetes に依存せず、Kubernetes マニフェストは Terraform に依存しません。

## Golden Path（標準ルート）

このリポジトリが定義する「新規サービスの標準」：

### ロギング

**問題**: チームごとに異なるログ形式では、集約・分析が困難。

**解決**: JSON 構造化ログを標準化。

```go
// internal/middleware/logging.go より
slog.Info("request completed",
    "method", r.Method,
    "path", r.URL.Path,
    "status", ww.status,
    "latency_ms", latency.Milliseconds(),
)
```

**出力例**:
```json
{"time":"2025-12-27T10:00:00Z","level":"INFO","msg":"request completed","method":"GET","path":"/healthz","status":200,"latency_ms":1}
```

**ノイズ回避**: `/healthz`, `/readyz`, `/metrics` はログ出力しない（Kubernetes の probe が大量に来るため）。

### メトリクス

**問題**: 各サービスで異なるメトリクス形式では、統一的な監視ができない。

**解決**: Prometheus 形式を標準化。

```go
// internal/handler/handler.go より
var (
    requestsTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "path", "status"},
    )
    requestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "HTTP request duration in seconds",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "path"},
    )
)
```

| メトリクス | 種類 | 用途 |
|-----------|------|------|
| `http_requests_total` | Counter | RPS、エラー率の計算 |
| `http_request_duration_seconds` | Histogram | レイテンシ分布（p50/p95/p99） |

### ヘルスチェック

**問題**: ヘルスチェックの実装がバラバラだと、Kubernetes が正しく判断できない。

**解決**: Liveness と Readiness を明確に分離。

| エンドポイント | 用途 | 実装 |
|---------------|------|------|
| `/healthz` | Liveness | 常に 200（プロセス生存確認） |
| `/readyz` | Readiness | 初期化完了後に 200（トラフィック受付可否） |

```go
// internal/handler/handler.go より
type Handler struct {
    ready atomic.Bool  // Readiness 状態管理
}

func (h *Handler) SetReady(ready bool) {
    h.ready.Store(ready)
}
```

**なぜ分離するか**: Liveness 失敗 → Pod 再起動、Readiness 失敗 → トラフィック停止。混同すると不要な再起動ループが発生。

### デプロイ

**問題**: 環境ごとにデプロイ方法が異なると、「ローカルでは動いたのに本番で動かない」が起きる。

**解決**: Helm チャートを kind/EKS で共通化し、環境差分は values ファイルで吸収。

| 設定 | kind (`values-kind.yaml`) | EKS (`values-eks.yaml`) |
|------|---------------------------|-------------------------|
| IngressClass | `nginx` | `alb` |
| HPA | disabled | enabled (2-10) |
| resources | 最小 (10m CPU) | 本番想定 (100m CPU) |
| ServiceMonitor | enabled | enabled |

## Observability（観測性）

### SLO/SLI 設計

**SLO（Service Level Objectives）** - サービスの目標値：

| 指標 | 目標 | 計測窓 |
|------|------|--------|
| 成功率 | 99.9% | 5分 |
| p95 レイテンシ | < 200ms | 5分 |

**SLI（Service Level Indicators）** - 実測値の計算式：

```promql
# 成功率
100 * (1 - sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])))

# p95 レイテンシ
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

### Grafana ダッシュボード

2種類のダッシュボードを提供：

| ファイル | 用途 |
|---------|------|
| `grafana-dashboard.json` | 基本メトリクス（RPS, Error Rate, Latency） |
| `grafana-slo-dashboard.json` | SLO/SLI 専用（目標達成率、Error Budget） |

**ダッシュボードパネル**:

| パネル名 | 説明 |
|---------|------|
| Request Rate | 秒間リクエスト数 |
| Error Rate | エラー率（5xx） |
| p95 Latency | 95パーセンタイルレイテンシ |
| Success Rate vs SLO | 成功率と目標値の比較 |
| Error Budget | 残り許容エラー量 |

### アラート条件例

```yaml
# 高エラー率
- alert: HighErrorRate
  expr: |
    100 * sum(rate(http_requests_total{status=~"5.."}[5m])) 
    / sum(rate(http_requests_total[5m])) > 1
  for: 5m

# レイテンシ劣化
- alert: HighLatency
  expr: |
    histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 0.2
  for: 5m
```

## Guardrails（ガードレール）

人の善意に依存せず、品質・セキュリティを**強制**する仕組み。

### CI チェック一覧

| チェック | ツール | 失敗条件 |
|---------|--------|----------|
| Go Lint | golangci-lint | lint 違反 |
| Go Test | go test -race | テスト失敗 |
| Docker Build | docker build | ビルド失敗 |
| 脆弱性スキャン | Trivy | CRITICAL/HIGH 検出 |
| SBOM 生成 | Syft | - |
| Helm Lint | helm lint | lint 違反 |
| Terraform Format | terraform fmt -check | 未フォーマット |
| Terraform Validate | terraform validate | 構文エラー |
| Policy Check | Conftest/OPA | ポリシー違反 |

### Policy as Code（OPA/Rego）

Terraform plan に対してセキュリティポリシーを強制：

```rego
# policies/deny_public_sg.rego
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group_rule"
    resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
    resource.change.after.from_port == 22
    msg := sprintf("SSH from 0.0.0.0/0 is not allowed: %s", [resource.address])
}
```

| ポリシー | 説明 |
|---------|------|
| `deny_public_sg.rego` | 0.0.0.0/0 からの SSH / 全ポート開放を禁止 |
| `deny_public_s3.rego` | S3 バケットの public ACL を禁止 |
| `required_tags.rego` | 必須タグの警告 |

### SBOM（Software Bill of Materials）

ソフトウェア部品表を自動生成し、サプライチェーンセキュリティを確保：

- **ツール**: Syft
- **形式**: SPDX JSON
- **用途**: 脆弱性追跡、ライセンスコンプライアンス

## Terraform（EKS 構築）

### モジュール構成

```
infra/terraform/
├── envs/dev/          # 環境定義
│   ├── main.tf        # モジュール呼び出し
│   ├── variables.tf   # 変数定義
│   └── outputs.tf     # 出力定義
└── modules/
    ├── vpc/           # VPC、サブネット、IGW
    ├── eks/           # EKS クラスター、ノードグループ
    └── iam/           # IRSA（AWS LBC 用）
```

### VPC モジュール

```hcl
# modules/vpc/main.tf より
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"  # ALB 用
  }
}
```

**重要**: サブネットタグがないと ALB が作成されない。

### EKS モジュール

```hcl
# modules/eks/main.tf より
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }
}
```

### IRSA（IAM Roles for Service Accounts）

AWS Load Balancer Controller に最小権限を付与：

```hcl
# modules/iam/main.tf より
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.cluster_name}-aws-lbc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}
```

## Security

### Pod Security Standards (PSS)

Kubernetes の Pod Security Standards に準拠し、**restricted** レベルを適用：

```yaml
# Deployment より
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  allowPrivilegeEscalation: false
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
      - ALL
```

| 設定 | 効果 |
|------|------|
| `runAsNonRoot` | root での実行を禁止 |
| `allowPrivilegeEscalation` | 特権昇格を禁止 |
| `seccompProfile` | syscall を制限 |
| `capabilities.drop` | すべての capability を削除 |

### 脆弱性スキャン

```yaml
# .github/workflows/ci.yaml より
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE }}
    format: 'table'
    exit-code: '1'
    severity: 'CRITICAL,HIGH'
    ignore-unfixed: true
```

### 公開面の最小化

| エンドポイント | 外部公開 | 用途 |
|---------------|---------|------|
| `/` | ✅ | アプリケーション |
| `/healthz` | ✅ | ヘルスチェック |
| `/readyz` | ✅ | ヘルスチェック |
| `/metrics` | ❌ | 内部監視のみ |

## CI/CD パイプライン

### ワークフロー構成

```
.github/workflows/
├── ci.yaml           # Go lint/test, Docker build, Helm lint
└── terraform.yaml    # Terraform fmt/validate/plan
```

### CI ワークフロー（ci.yaml）

```yaml
jobs:
  lint:
    # golangci-lint
  test:
    # go test -v -race -coverprofile
  build:
    # docker build + trivy scan + syft sbom
  helm:
    # helm lint + helm template
```

### Terraform ワークフロー（terraform.yaml）

```yaml
on:
  push:
    paths:
      - 'infra/terraform/**'

jobs:
  validate:
    # terraform fmt -check
    # terraform validate
  plan:
    # terraform plan（OIDC 認証）
    # conftest test（Policy as Code）
```

### GitHub Actions OIDC

PR 時に `terraform plan` を自動実行：

1. AWS OIDC Provider を作成
2. IAM ロールを作成（信頼ポリシーで GitHub を許可）
3. リポジトリ変数に `AWS_OIDC_ROLE_ARN` を設定

## 設計上のトレードオフ

| 選択 | 理由 | 本番向け代替 |
|-----|------|-------------|
| HTTP のみ | 独自ドメイン不要で即座に検証可能 | Route53 + ACM で HTTPS 化 |
| Public Subnet | NAT Gateway 不要でコスト最小 | Private Subnet + NAT 構成 |
| ローカル state | 追加の AWS 設定不要 | S3 + DynamoDB でチーム共有 |

### 本番環境への拡張例

#### HTTPS 対応

```yaml
# values-eks.yaml に追加
ingress:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/ssl-redirect: "443"
```

#### Private Subnet 構成

```hcl
# modules/vpc で private_subnets を追加
# modules/eks で subnet_ids を private に変更
```

#### Terraform State のリモート管理

```hcl
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

## まとめ

本システムは以下の仕組みで「新規サービスが運用可能な形で立ち上がる」ことを実現しています：

| 課題 | 解決策 |
|------|--------|
| ログ形式がバラバラ | JSON 構造化ログを標準化 |
| メトリクスが統一されていない | Prometheus 形式を強制 |
| ヘルスチェックの実装が曖昧 | Liveness/Readiness を明確に分離 |
| 環境ごとにデプロイ方法が異なる | Helm チャートを共通化 |
| セキュリティ設定が属人的 | CI で自動チェック（Trivy, OPA） |
| 品質が人の善意に依存 | Guardrails で強制 |
