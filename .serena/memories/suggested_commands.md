# 開発コマンド一覧

## Go アプリケーション

```bash
make build      # Go バイナリをビルド
make test       # テスト実行（-race -cover 付き）
make lint       # golangci-lint 実行
make run        # ローカルでアプリ起動（port 8080）
```

## Docker

```bash
make image-build   # Docker イメージビルド
make image-push    # GHCR にプッシュ
make image-load    # kind クラスターにロード
```

## kind（ローカル Kubernetes）

```bash
make kind-up       # クラスター作成 + ingress-nginx
make kind-down     # クラスター削除
make kind-deploy   # アプリデプロイ
make kind-undeploy # アプリ削除
make kind-url      # URL表示（http://localhost:80）
make kind-status   # pods/svc/ingress 確認
make kind-logs     # アプリログ表示
```

## 観測性（kind）

```bash
make obs-up        # kube-prometheus-stack インストール
make obs-down      # kube-prometheus-stack 削除
make kind-grafana  # Grafana port-forward (admin/prom-operator)
make kind-prometheus # Prometheus port-forward
```

## EKS（AWS）

```bash
make eks-plan      # Terraform plan
make eks-apply     # Terraform apply（約15分、コスト発生）
make eks-destroy   # Terraform destroy（必須！）
make eks-kubeconfig   # kubeconfig 設定
make eks-install-lbc  # AWS Load Balancer Controller 導入
make eks-deploy    # アプリデプロイ
make eks-undeploy  # アプリ削除
make eks-url       # ALB DNS 表示
make eks-status    # nodes/pods/ingress 確認
```

## Terraform

```bash
make tf-init       # Terraform 初期化
make tf-fmt        # Terraform フォーマット
make tf-validate   # Terraform 検証
```

## CI

```bash
make ci            # ローカルで CI チェック一括実行（lint + test + image-build）
```

## CLI 使用時の注意

### GitHub CLI

```bash
# ページングブロック防止のため GH_PAGER='' を付ける
GH_PAGER='' gh pr create --title "タイトル" --body "説明"
GH_PAGER='' gh pr merge <番号> --squash --delete-branch --admin
GH_PAGER='' gh pr checks <番号> --watch
```

### AWS CLI

```bash
# ページングブロック防止のため AWS_PAGER="" を付ける
AWS_PAGER="" aws sts get-caller-identity
AWS_PAGER="" aws eks describe-cluster --name terraform-eks-golden-path-dev
```
