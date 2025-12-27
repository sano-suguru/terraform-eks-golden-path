# terraform-eks-golden-path

[![CI](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/ci.yaml/badge.svg)](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/ci.yaml)
[![Terraform](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/terraform.yaml/badge.svg)](https://github.com/sano-suguru/terraform-eks-golden-path/actions/workflows/terraform.yaml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

EKS + kind の二段構えで、サービス立ち上げ時の「Golden Path（標準化）+ Guardrails（自動チェック）」を形にしたリポジトリです。

## このリポジトリについて

新しいサービスを立ち上げるとき、ログ形式やメトリクス、ヘルスチェック、デプロイ方法をどうするか迷うことが多いと感じていました。チームごとに違う方式になると、後から運用が大変になります。

そこで、以下の3つを意識して作りました：

| 柱 | やったこと |
|---|------------|
| **Golden Path** | ログ・メトリクス・ヘルスチェック・デプロイを最初から決めておく |
| **Guardrails** | CI で lint、テスト、脆弱性スキャンを自動実行 |
| **Reproducibility** | kind（ローカル）でも EKS（AWS）でも同じ Helm チャートで動く |

## 使っている技術

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

設計・実装時に考えたことや、具体的なコード例をまとめています：

- **Golden Path の詳細** - ログ・メトリクス・ヘルスチェックの実装
- **Observability** - SLO/SLI 設計、Grafana ダッシュボード、アラート条件
- **Guardrails の実装** - OPA/Rego ポリシー、Trivy、SBOM
- **Terraform モジュール** - VPC、EKS、IRSA の設計
- **Security** - Pod Security Standards、脆弱性スキャン
- **CI/CD パイプライン** - GitHub Actions、OIDC 認証
- **トレードオフと今後の課題** - 現状の設計判断と拡張方針

### その他のドキュメント

- [アーキテクチャ図](docs/architecture.md)
- [設計仕様書](docs/00-spec.md)

### Runbooks

- [高エラー率への対応](docs/runbook-high-error-rate.md)
- [レイテンシ劣化への対応](docs/runbook-latency-regression.md)

## 設計で意識したこと

ローカルで即座に動作確認できることを優先しています。
本番向けの構成にする場合は、以下のように拡張できます。

| 現状 | 理由 | 拡張する場合 |
|-----|------|-------------|
| HTTP のみ | 独自ドメイン不要で即座に検証可能 | Route53 + ACM で HTTPS 化 |
| Public Subnet | NAT Gateway 不要でコスト最小 | Private Subnet + NAT 構成 |
| ローカル state | 追加の AWS 設定不要 | S3 + DynamoDB でチーム共有 |

## License

MIT
