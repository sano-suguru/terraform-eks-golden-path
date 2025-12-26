# Runbook: 高エラー率への対応

## 症状

- 成功率 SLO 割れ（< 99.9%）
- 5xx エラーの増加
- Grafana ダッシュボードの Error Rate パネルが赤くなっている

## アラート条件

```promql
100 * sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 1
```

## 初動確認（5分以内）

### 1. 現在の状態確認

```bash
# Pod の状態確認
kubectl get pods -l app.kubernetes.io/name=golden-path-api

# 最近の再起動確認
kubectl get pods -l app.kubernetes.io/name=golden-path-api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# イベント確認
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

### 2. 直近のデプロイ確認

```bash
# Helm リリース履歴
helm history golden-path-api

# 最新のデプロイ時刻
kubectl get deployment golden-path-api-golden-path-api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'
```

### 3. ログ確認

```bash
# エラーログの抽出
kubectl logs -l app.kubernetes.io/name=golden-path-api --tail=100 | jq 'select(.level == "ERROR")'

# 直近のリクエストログ（status 5xx）
kubectl logs -l app.kubernetes.io/name=golden-path-api --tail=1000 | jq 'select(.status >= 500)'
```

## 切り分け

### エラーの種類を特定

1. **特定エンドポイントのみ？**

   ```promql
   sum(rate(http_requests_total{status=~"5.."}[5m])) by (path)
   ```

2. **特定 Pod のみ？**

   ```promql
   sum(rate(http_requests_total{status=~"5.."}[5m])) by (pod)
   ```

3. **外部依存の問題？**
   - DB 接続エラー
   - 外部 API タイムアウト

## 対応

### 即時緩和

#### 直近デプロイが原因の場合 → ロールバック

```bash
helm rollback golden-path-api
```

#### 負荷が原因の場合 → スケールアウト

```bash
kubectl scale deployment golden-path-api-golden-path-api --replicas=4
```

#### 特定 Pod が原因の場合 → Pod 削除

```bash
kubectl delete pod <問題のpod名>
```

### 恒久対応

1. 根本原因の特定とチケット起票
2. 再発防止策の検討
   - テストの追加
   - ガードレールの強化
   - モニタリングの改善

## エスカレーション

- 15 分以上解決しない場合 → チームリードに連絡
- 顧客影響がある場合 → インシデント対応フローへ

## チェックリスト

- [ ] アラートを確認した
- [ ] 直近のデプロイを確認した
- [ ] ログを確認した
- [ ] 緩和策を実施した
- [ ] 根本原因を特定した（または調査チケットを起票した）
