# Copilot Instructions for terraform-eks-golden-path

## Project Overview

Platform Engineering ポートフォリオ：EKS + kind の二段構えで「Golden Path（標準化）+ Guardrails（強制力）+ Reproducibility（再現性）」を実証する。

## Architecture

```
app/                          # Go HTTP API（net/http + slog）
  cmd/api/main.go             # エントリーポイント、グレースフルシャットダウン実装
  internal/handler/           # HTTPハンドラー + Prometheusメトリクス
  internal/middleware/        # ロギングミドルウェア
deploy/helm/golden-path-api/  # Helm chart（kind/EKS共通）
  values-kind.yaml            # kind用（nginx IngressClass）
  values-eks.yaml             # EKS用（alb IngressClass + HPA有効）
deploy/kind/                  # kind設定、Prometheus values
infra/terraform/              # EKSインフラ
  envs/dev/                   # 開発環境定義
  modules/vpc/                # VPC, サブネット, EKS/ALBタグ
  modules/eks/                # EKSクラスター, ノードグループ, OIDC Provider
  modules/iam/                # AWS Load Balancer Controller用IRSA
```

- **kind（ローカル）**: ingress-nginx + kube-prometheus-stack で即座に試せる
- **EKS（クラウド）**: AWS Load Balancer Controller（IRSA）で ALB Ingress 公開

## Developer Workflow

### Git 運用ルール

- **main ブランチへ直接コミット禁止**: 必ず feature ブランチを作成し、PR 経由でマージする
- **コミットメッセージは日本語で記述する**
- **ブランチ命名規則**: `feature/機能名`, `fix/修正内容`, `docs/ドキュメント`

```bash
# 新機能開発の流れ
git checkout -b feature/新機能名
# ... 作業 ...
git add -A
git commit -m "feat: 新機能の説明"
git push -u origin feature/新機能名
# GitHub で PR を作成 → レビュー → マージ
```

### GitHub CLI 使用時の注意

- `gh` コマンド使用時は必ず `GH_PAGER=''` を付ける（ページングによるブロックを防止）

```bash
# 例
GH_PAGER='' gh pr create --title "タイトル" --body "説明"
GH_PAGER='' gh pr merge <番号> --squash --delete-branch --admin
GH_PAGER='' gh pr checks <番号> --watch
```

### AWS CLI 使用時の注意

- `aws` コマンド使用時は必ず `AWS_PAGER=""` を付ける（ページングによるブロックを防止）

```bash
# 例
AWS_PAGER="" aws sts get-caller-identity
AWS_PAGER="" aws eks describe-cluster --name terraform-eks-golden-path-dev
AWS_PAGER="" aws budgets describe-budgets --account-id <account-id>
```

### すべての操作は Makefile 経由

```bash
# ローカル開発サイクル
make run              # Goアプリをローカル実行（port 8080）
make test             # go test -v -race -cover
make lint             # golangci-lint
make ci               # lint + test + image-build を一括実行（PR前に必ず実行）

# kind環境
make kind-up          # クラスター作成 + ingress-nginx導入
make obs-up           # kube-prometheus-stack導入（kind-deploy前に必要）
make kind-deploy      # イメージビルド→ロード→Helmデプロイ
make kind-status      # pods/svc/ingress確認
curl http://localhost/healthz

# 観測性
make kind-grafana     # port-forward → http://localhost:3000 (admin/prom-operator)

# EKS環境
make tf-init          # Terraform初期化
make eks-apply        # EKS構築（約15分、コスト発生注意）
make eks-kubeconfig   # kubeconfig設定
make eks-install-lbc  # AWS Load Balancer Controller導入
make eks-deploy       # アプリデプロイ
make eks-url          # ALB DNS表示
make eks-destroy      # 後片付け（必須！）
```

### Makefile 変数

```makefile
PROJECT_NAME := terraform-eks-golden-path
CLUSTER_NAME := $(PROJECT_NAME)-$(ENV)  # terraform-eks-golden-path-dev
IMAGE_REPO := ghcr.io/<user>/$(PROJECT_NAME)
```

## Go Application Patterns

### main.go の構造（`cmd/api/main.go`）

```go
// 必須実装
- log/slog でJSON構造化ログ（slog.SetDefault）
- http.Server のタイムアウト設定（Read: 10s, Write: 10s, Idle: 120s）
- goroutineでサーバー起動
- グレースフルシャットダウン（SIGINT/SIGTERM → 30s timeout）
- PORT環境変数（デフォルト: 8080）
```

### ハンドラー構造（`internal/handler/handler.go`）

```go
type Handler struct {
    ready atomic.Bool  // Readiness状態管理
}

// 必須エンドポイント
GET /healthz  // Liveness（常に200、依存なし）
GET /readyz   // Readiness（SetReady(true)後に200）
GET /metrics  // Prometheus形式（外部公開禁止）
```

### エラーハンドリング規約

- サーバー起動エラー: `slog.Error` + `os.Exit(1)`
- リクエストエラー: HTTP ステータスコード + `slog.Error`（構造化フィールド付き）
- シャットダウンエラー: `slog.Error`（プロセスは終了させる）

### ロギング規約（`internal/middleware/logging.go`）

- `log/slog`で JSON 構造化ログ
- 必須フィールド: `method`, `path`, `status`, `latency_ms`
- `/healthz`, `/readyz`, `/metrics`はログ出力しない（ノイズ回避）

### メトリクス

- `http_requests_total{method,path,status}` - リクエストカウンター
- `http_request_duration_seconds{method,path}` - レイテンシヒストグラム

### テストパターン（`handler_test.go`）

```go
h := New()
req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
rec := httptest.NewRecorder()
h.Healthz(rec, req)
// rec.Code, rec.Body で検証
```

### Dockerfile 規約（`app/Dockerfile`）

- **マルチステージビルド**: `golang:1.25-alpine` → `scratch`
- **レイヤーキャッシング最適化**: `go.mod`/`go.sum` を先に COPY
- **静的バイナリ**: `CGO_ENABLED=0`, `-ldflags="-w -s"`
- **最小イメージ**: `scratch` base（CA 証明書のみコピー）
- **非 root ユーザー**: `USER 65534:65534`
- **ポート**: 8080 固定

## Helm Chart Conventions

### 環境差分は values ファイルで吸収

| 設定           | kind (`values-kind.yaml`) | EKS (`values-eks.yaml`) |
| -------------- | ------------------------- | ----------------------- |
| IngressClass   | `nginx`                   | `alb`                   |
| autoscaling    | disabled                  | enabled (2-10)          |
| resources      | 最小 (10m CPU)            | 本番想定 (100m CPU)     |
| ServiceMonitor | enabled                   | enabled                 |

### EKS ALB 必須アノテーション

```yaml
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/healthcheck-path: /healthz
```

## Terraform（EKS 構築時）

### 基本方針

- **リージョン**: `ap-northeast-1` 固定
- **VPC**: public subnet のみ（NAT Gateway 不要でコスト削減）
- **EKS**: v1.31、マネージドノードグループ
- **IRSA**: AWS Load Balancer Controller 用の IAM ロール
- **命名**: `${project_name}-${env}`（例：`terraform-eks-golden-path-dev`）
- **サブネットタグ必須**:
  - `kubernetes.io/cluster/<cluster_name> = shared`
  - `kubernetes.io/role/elb = 1`

### Module 構造と責務

#### `modules/vpc/`

- VPC 作成（CIDR: 変数で指定）
- Internet Gateway
- Public subnets（2 つの AZ、ALB 配置用）
- Route tables
- **重要**: EKS/ALB 用のタグを自動付与

#### `modules/eks/`

- EKS クラスター作成（version 1.31）
- マネージドノードグループ（instance type: t3.medium 等）
- OIDC Provider（IRSA 前提）
- Security Group（ノード間通信）

#### `modules/iam/`

- AWS Load Balancer Controller 用の IAM ロール（IRSA）
- IAM ポリシー（ELB/EC2/Route53 の最小権限）
- ServiceAccount 用の Trust Policy（OIDC 連携）

### envs/dev/

- 環境固有の変数定義（`terraform.tfvars`）
- module 呼び出し（`main.tf`）
- outputs 定義（cluster_name, endpoint 等）

## イメージ配布

- **GHCR（GitHub Container Registry）で Public イメージ**として配布
- kind: `make image-load` でローカルイメージを直接ロード
- EKS: `make image-push` で GHCR にプッシュ → ノードが pull

## SLO/SLI

- **成功率**: 99.9%（5 分窓） - `2xx / total`
- **p95 レイテンシ**: 200ms 以下（5 分窓）
- アラート条件例: `docs/runbook-*.md` 参照

## CI/Guardrails（`.github/workflows/`）

### ci.yaml（PR/main push で実行）

- **Go Build & Test**: `go test -v -race -coverprofile=coverage.out`
- **Go Lint**: `golangci-lint`（最新版）
- **Docker Build**: `docker/build-push-action`（GHA cache あり）
- **Helm Lint**: `helm lint` + `helm template`（kind/EKS 両方）

### terraform.yaml（Terraform ファイル変更時のみ）

- **Terraform Format Check**: `terraform fmt -check -recursive`
- **Terraform Init**: `-backend=false`（CI 用）
- **Terraform Validate**: 構文チェック

### CI で必ず落とすもの

- `go test -race` 失敗
- `golangci-lint` 違反
- `terraform fmt -check` 失敗
- `terraform validate` 失敗
- Docker build 失敗
- Helm lint/template 失敗

## Security Principles

- `/metrics` は外部公開しない（cluster 内 or 認証付きのみ）
- AWS Load Balancer Controller は **IRSA** で最小権限
- 機密は Git に置かない（Secret 管理方針を README に明記）

## Non-goals（やらないこと）

- マイクロサービス複数本
- Service Mesh / GitOps（ArgoCD/Flux）の必須化
- HTTPS（Route53 + ACM）は Plus 扱い
- マルチリージョン DR
- 複雑な認証基盤

## Common Pitfalls

- **ALB 未作成**: サブネットに `kubernetes.io/role/elb = 1` タグが無い
- **IRSA 無効**: OIDC Provider 設定漏れ、ServiceAccount annotation 不一致
- **kind で Ingress 到達不可**: `kind-config.yaml`の`extraPortMappings`設定漏れ
- **Readyz 即失敗**: `Handler.SetReady(true)`が呼ばれる前に probe が来る
- **EKS コスト放置**: 検証後は必ず `make eks-destroy` を実行

## Reference

- 技術解説: [docs/IMPLEMENTATION.md](../docs/IMPLEMENTATION.md)
- 設計仕様: [docs/00-spec.md](../docs/00-spec.md)
- Runbook: [docs/runbook-high-error-rate.md](../docs/runbook-high-error-rate.md), [docs/runbook-latency-regression.md](../docs/runbook-latency-regression.md)
