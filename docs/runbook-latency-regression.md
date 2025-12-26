# Runbook: レイテンシ劣化への対応

## 症状

- p95 レイテンシ SLO 割れ（> 200ms）
- リクエストタイムアウトの増加
- Grafana ダッシュボードの Latency (p95) パネルが赤くなっている

## アラート条件

```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 0.2
```

## 初動確認（5分以内）

### 1. 現在のレイテンシ確認

```bash
# Prometheus でクエリ（port-forward が必要）
# p50, p95, p99 を確認
```

Grafana ダッシュボードの「Latency Distribution」パネルで確認。

### 2. リソース使用状況確認

```bash
# CPU/メモリ使用率
kubectl top pods -l app.kubernetes.io/name=golden-path-api

# リソース制限の確認
kubectl get pods -l app.kubernetes.io/name=golden-path-api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources}{"\n"}{end}'
```

### 3. Pod の状態確認

```bash
# Pod 一覧と状態
kubectl get pods -l app.kubernetes.io/name=golden-path-api -o wide

# レプリカ数確認
kubectl get deployment golden-path-api-golden-path-api
```

## 切り分け

### 遅いエンドポイントを特定

```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, path))
```

### CPU/メモリが原因か

- CPU 使用率 > 80% → CPU バウンド
- メモリ使用率 > 80% → メモリバウンド or GC 頻発

### 外部依存が原因か

- DB クエリの遅延
- 外部 API のレスポンス遅延

### トラフィック増加が原因か

```promql
sum(rate(http_requests_total[5m]))
```

過去の平均と比較して急増していないか確認。

## 対応

### 即時緩和

#### CPU/メモリ不足の場合 → リソース増加

```bash
# HPA が有効な場合は自動スケール
# 手動でスケールする場合
kubectl scale deployment golden-path-api-golden-path-api --replicas=4
```

#### 特定 Pod が遅い場合 → Pod 再起動

```bash
kubectl delete pod <遅いpod名>
```

#### 直近デプロイが原因の場合 → ロールバック

```bash
helm rollback golden-path-api
```

### リソース調整（values.yaml の変更）

```yaml
resources:
  limits:
    cpu: 200m # 増加
    memory: 256Mi # 増加
  requests:
    cpu: 100m
    memory: 128Mi
```

### 恒久対応

1. **ボトルネックの特定**

   - プロファイリング（pprof）の導入
   - 遅いクエリの最適化
   - キャッシュの導入

2. **容量計画の見直し**
   - 適切なリソースリクエスト/リミットの設定
   - HPA の閾値調整

## エスカレーション

- 15 分以上解決しない場合 → チームリードに連絡
- p99 > 1s が継続する場合 → インシデント対応フローへ

## チェックリスト

- [ ] 現在のレイテンシ値を確認した
- [ ] CPU/メモリ使用率を確認した
- [ ] 遅いエンドポイントを特定した
- [ ] 緩和策を実施した
- [ ] 根本原因を特定した（または調査チケットを起票した）
