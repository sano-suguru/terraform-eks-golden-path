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
infra/terraform/              # EKSインフラ（※未実装 - 作成時はspec参照）
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
GH_PAGER='' gh api repos/owner/repo/branches/main/protection
GH_PAGER='' gh pr list
GH_PAGER='' gh issue list
```

### すべての操作は Makefile 経由

```bash
# ローカル開発サイクル
make run              # Goアプリをローカル実行（port 8080）
make test             # go test -v -race -cover
make lint             # golangci-lint
make ci               # lint + test + image-build を一括実行

# kind環境
make kind-up          # クラスター作成 + ingress-nginx導入
make kind-deploy      # イメージビルド→ロード→Helmデプロイ
make kind-status      # pods/svc/ingress確認
curl http://localhost/healthz

# 観測性
make obs-up           # kube-prometheus-stack導入
make kind-grafana     # port-forward → http://localhost:3000 (admin/prom-operator)
```

### Make ターゲット命名規則

- kind 系: `kind-*`（例：`kind-up`, `kind-deploy`）
- EKS 系: `eks-*`（例：`eks-apply`, `eks-deploy`）
- 観測性: `obs-*`（例：`obs-up`）
- Terraform: `tf-*`（例：`tf-init`, `tf-fmt`）

## Go Application Patterns

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

> ⚠️ `infra/terraform/` は未実装。作成時は `docs/00-spec.md` セクション 16 を参照。

- **リージョン**: `ap-northeast-1` 固定
- **VPC**: public subnet のみ（NAT Gateway 不要でコスト削減）
- **命名**: `${project_name}-${env}`（例：`terraform-eks-golden-path-dev`）
- **サブネットタグ必須**:
  - `kubernetes.io/cluster/<cluster_name> = shared`
  - `kubernetes.io/role/elb = 1`

## イメージ配布

- **GHCR（GitHub Container Registry）で Public イメージ**として配布
- kind: `make image-load` でローカルイメージを直接ロード
- EKS: `make image-push` で GHCR にプッシュ → ノードが pull

## SLO/SLI

- **成功率**: 99.9%（5 分窓） - `2xx / total`
- **p95 レイテンシ**: 200ms 以下（5 分窓）
- アラート条件例: `docs/runbook-*.md` 参照

## CI/Guardrails（`.github/workflows/`）

CI で必ず落とすもの：

- `go test -race` 失敗
- `golangci-lint` 違反
- `terraform fmt -check` / `terraform validate` 失敗
- Docker build / Helm lint 失敗

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

- 詳細仕様: [docs/00-spec.md](../docs/00-spec.md)
- Runbook: [docs/runbook-high-error-rate.md](../docs/runbook-high-error-rate.md), [docs/runbook-latency-regression.md](../docs/runbook-latency-regression.md)
