# terraform-eks-golden-path

[![CI](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/ci.yaml/badge.svg)](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/ci.yaml)
[![Terraform](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/terraform.yaml/badge.svg)](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/terraform.yaml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Platform Engineering ポートフォリオ：EKS + kind の二段構えで「Golden Path（標準化）+ Guardrails（強制力）+ Reproducibility（再現性）」を実証する。

## 解決する課題

新しいサービスを作るたびに、ログ形式、メトリクス、ヘルスチェック、デプロイ方法を一から決めていませんか？

![課題](https://mermaid.ink/img/pako:eNptkMEKwjAMhl8l5KSgb9CDIHgQvHjx5KXbsi5uTWnTgYi-u9OJiHoI_PlDvhDm0MuAwME4f5fBqXZdGaZpKMgHSxPGMPJaFq_UxmBjlDSk-uDxxz7G9hqNkEoPLJx4bJLoXA-BmNd5j5b0wML8cN4A?type=png)

チームごとに異なる方式が乱立し、運用負荷が増大します。

## 解決策：3つの柱

| 柱 | 説明 | 実装 |
|---|------|------|
| **Golden Path** | ログ・メトリクス・ヘルスチェック・デプロイを標準化 | JSON ログ、Prometheus メトリクス、Helm チャート |
| **Guardrails** | 品質・セキュリティを CI で強制 | golangci-lint, Trivy, OPA/Conftest |
| **Reproducibility** | ローカルでもクラウドでも同じ方法で動く | kind + EKS で共通 Helm チャート |

## 技術スタック

| カテゴリ | 技術 |
|---------|------|
| 言語 | Go 1.24 |
| インフラ | AWS EKS (Terraform) / kind (ローカル) |
| デプロイ | Helm 3.x |
| 監視 | Prometheus + Grafana (kube-prometheus-stack) |
| ログ | 構造化ログ (log/slog) |
| CI/CD | GitHub Actions |
| セキュリティ | Trivy (脆弱性スキャン) + OPA/Conftest (Policy as Code) |
| SBOM | Syft (SPDX JSON) |

## アーキテクチャ

![アーキテクチャ](https://mermaid.ink/img/pako:eNp1kE1qwzAQha9izCpQ5wJeFEJ-IN0UstJGO5VlxQiNhCTHhJC717FdaNPuZnjvG94M8ILKe4QC1DjfdnBqvYy-7_toKXhP0xz9gLdp_Ul1iK4xSppaVXD9sY-RMUQnVL1xH2VuklSxQ8-8LjJaGbDxNJwfyMgqR7Z6jkaNrLJ_W-6P8J5qH7x8_AVKX0-_-S5Ue2O14-O2bV8?type=png)

詳細は [docs/architecture.md](docs/architecture.md) を参照。

## クイックスタート（5分）

### 前提ツール

- [kind](https://kind.sigs.k8s.io/) 0.20+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) 1.28+
- [Helm](https://helm.sh/) 3.x
- [Docker](https://www.docker.com/)

### 手順

```bash
# 1. kind クラスター作成（ingress-nginx 込み）
make kind-up

# 2. 観測性スタック導入（Prometheus + Grafana）
make obs-up

# 3. アプリをデプロイ
make kind-deploy

# 4. 動作確認
curl http://localhost/healthz
# => {"status":"ok"}

# 5. Grafana ダッシュボード確認
make kind-grafana
# => http://localhost:3000 (admin/prom-operator)

# 6. 片付け
make kind-down
```

## API エンドポイント

| Path | 説明 | 外部公開 |
|------|------|---------|
| `/` | Hello レスポンス | ✅ |
| `/healthz` | Liveness probe（依存なし） | ✅ |
| `/readyz` | Readiness probe（初期化完了後 OK） | ✅ |
| `/metrics` | Prometheus メトリクス | ❌（内部のみ） |

## SLO/SLI

| 指標 | 目標 | 計測窓 |
|------|------|--------|
| 成功率 | 99.9% | 5分 |
| p95 レイテンシ | < 200ms | 5分 |

## EKS デプロイ

> ⚠️ **注意**: AWS 料金が発生します。**1日放置で約$5〜10**。検証後は必ず `make eks-destroy` を実行してください。

```bash
# 1. Terraform 初期化
make tf-init

# 2. EKS 構築（約15分）
make eks-apply

# 3. kubeconfig 設定
make eks-kubeconfig

# 4. AWS Load Balancer Controller 導入
make eks-install-lbc

# 5. アプリデプロイ
make eks-deploy

# 6. ALB DNS 確認
make eks-url
# => http://xxxxx.elb.amazonaws.com

# 7. 片付け（必須！）
make eks-destroy
```

## プロジェクト構成

```
├── app/                    # Go HTTP API
│   ├── cmd/api/            # エントリーポイント
│   └── internal/           # ハンドラー、ミドルウェア
├── deploy/
│   ├── helm/               # Helm チャート（kind/EKS 共通）
│   └── kind/               # kind 設定、Prometheus values
├── infra/terraform/        # EKS インフラ
│   ├── envs/dev/           # 環境定義
│   ├── modules/            # vpc, eks, iam モジュール
│   └── policies/           # OPA/Conftest ポリシー
└── docs/                   # ドキュメント
```

## CI/Guardrails

| チェック | 説明 |
|---------|------|
| Go Lint/Test | golangci-lint + go test -race |
| Docker Build | イメージビルド + Trivy スキャン |
| SBOM | Syft で SPDX JSON 生成 |
| Helm Lint | helm lint + helm template |
| Terraform | fmt + validate + OPA ポリシーチェック |

## 詳細ドキュメント

📖 **[技術解説 (IMPLEMENTATION.md)](docs/IMPLEMENTATION.md)**

README では触れていない以下の内容を詳しく解説しています：

- **Golden Path の詳細** - ログ・メトリクス・ヘルスチェックの実装
- **Observability** - SLO/SLI 設計、Grafana ダッシュボード、アラート条件
- **Guardrails の実装** - OPA/Rego ポリシー、Trivy、SBOM
- **Terraform モジュール** - VPC、EKS、IRSA の設計
- **Security** - Pod Security Standards、脆弱性スキャン
- **CI/CD パイプライン** - GitHub Actions、OIDC 認証

### その他のドキュメント

- [アーキテクチャ図](docs/architecture.md)
- [設計仕様書](docs/00-spec.md)

### Runbooks

- [高エラー率への対応](docs/runbook-high-error-rate.md)
- [レイテンシ劣化への対応](docs/runbook-latency-regression.md)

## 設計上のトレードオフ

このリポジトリは**ローカルで即座に動作確認できる**ことを優先した設計です。

| 選択 | 理由 | 本番向け代替 |
|-----|------|-------------|
| HTTP のみ | 独自ドメイン不要で即座に検証可能 | Route53 + ACM で HTTPS 化 |
| Public Subnet | NAT Gateway 不要でコスト最小 | Private Subnet + NAT 構成 |
| ローカル state | 追加の AWS 設定不要 | S3 + DynamoDB でチーム共有 |

## License

MIT
