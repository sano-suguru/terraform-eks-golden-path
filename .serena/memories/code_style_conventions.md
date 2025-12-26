# コードスタイルと規約

## Git 運用ルール

- **main ブランチへ直接コミット禁止**: 必ず feature ブランチを作成し、PR 経由でマージ
- **コミットメッセージは日本語で記述**
- **ブランチ命名規則**:
  - `feature/機能名`
  - `fix/修正内容`
  - `docs/ドキュメント`

## Go コード規約

### ロギング

- `log/slog` で JSON 構造化ログ
- 必須フィールド: `method`, `path`, `status`, `latency_ms`
- `/healthz`, `/readyz`, `/metrics` はログ出力しない（ノイズ回避）

### エラーハンドリング

- サーバー起動エラー: `slog.Error` + `os.Exit(1)`
- リクエストエラー: HTTP ステータスコード + `slog.Error`（構造化フィールド付き）
- シャットダウンエラー: `slog.Error`（プロセスは終了させる）

### HTTP サーバー

- タイムアウト設定: Read: 10s, Write: 10s, Idle: 120s
- グレースフルシャットダウン: SIGINT/SIGTERM → 30s timeout
- PORT 環境変数（デフォルト: 8080）

### エンドポイント設計

| Path       | 用途              | 仕様                          |
|------------|-------------------|-------------------------------|
| `/healthz` | Liveness probe    | 常に 200、依存なし            |
| `/readyz`  | Readiness probe   | SetReady(true) 後に 200       |
| `/metrics` | Prometheus        | 外部公開禁止                  |

## Terraform 規約

- リージョン: `ap-northeast-1` 固定
- 命名: `${project_name}-${env}`（例: `terraform-eks-golden-path-dev`）
- サブネットタグ必須:
  - `kubernetes.io/cluster/<cluster_name> = shared`
  - `kubernetes.io/role/elb = 1`

## Helm 規約

- 環境差分は values ファイルで吸収
  - `values-kind.yaml`: nginx IngressClass
  - `values-eks.yaml`: alb IngressClass, HPA 有効

## ドキュメント

- README.md: 英語/日本語混在可
- Runbook: docs/ 配下に配置
