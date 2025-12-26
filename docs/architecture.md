# アーキテクチャ

## システム構成

このリポジトリは「kind（ローカル）」と「EKS（クラウド）」の二段構えで、同じアプリ・同じ Helm チャートで動作します。

### 全体像

```mermaid
flowchart TB
    subgraph "Developer Environment"
        DEV[開発者]
        GIT[GitHub Repository]
    end

    subgraph "CI/CD Pipeline"
        GHA[GitHub Actions]
        TRIVY[Trivy Scanner]
        HELM_LINT[Helm Lint]
        GO_TEST[Go Test/Lint]
        CONFTEST[Conftest/OPA]
    end

    subgraph "Local (kind)"
        KIND[kind Cluster]
        NGINX[ingress-nginx]
        PROM_LOCAL[Prometheus]
        GRAFANA_LOCAL[Grafana]
        APP_LOCAL[golden-path-api]
    end

    subgraph "AWS (EKS)"
        VPC[VPC]
        EKS[EKS Cluster]
        ALB[Application Load Balancer]
        LBC[AWS LB Controller]
        APP_EKS[golden-path-api]
        IRSA[IRSA]
    end

    DEV -->|git push| GIT
    GIT -->|trigger| GHA
    GHA --> TRIVY
    GHA --> HELM_LINT
    GHA --> GO_TEST
    GHA --> CONFTEST

    DEV -->|make kind-deploy| KIND
    KIND --> NGINX
    KIND --> PROM_LOCAL
    KIND --> GRAFANA_LOCAL
    NGINX --> APP_LOCAL

    DEV -->|make eks-deploy| EKS
    EKS --> LBC
    LBC -->|creates| ALB
    ALB --> APP_EKS
    IRSA -.->|auth| LBC
```

### kind（ローカル）構成

```mermaid
flowchart LR
    subgraph "Host Machine"
        CURL[curl/browser]
        PORT80[localhost:80]
        PORT3000[localhost:3000]
    end

    subgraph "kind Cluster"
        subgraph "ingress-nginx"
            ING[Ingress Controller]
        end

        subgraph "default namespace"
            SVC[Service]
            POD[golden-path-api Pod]
        end

        subgraph "monitoring namespace"
            PROM[Prometheus]
            GRAF[Grafana]
            SM[ServiceMonitor]
        end
    end

    CURL --> PORT80
    PORT80 --> ING
    ING -->|/healthz, /readyz| SVC
    SVC --> POD
    PORT3000 -.->|port-forward| GRAF
    PROM -->|scrape| SM
    SM -->|/metrics| POD
```

### EKS（クラウド）構成

```mermaid
flowchart TB
    subgraph "Internet"
        USER[ユーザー]
    end

    subgraph "AWS"
        subgraph "VPC (10.0.0.0/16)"
            subgraph "Public Subnets"
                ALB[Application Load Balancer]
            end

            subgraph "EKS Cluster"
                subgraph "kube-system"
                    LBC[AWS LB Controller]
                    SA[ServiceAccount]
                end

                subgraph "default namespace"
                    ING[Ingress]
                    SVC[Service]
                    POD[golden-path-api Pod]
                end
            end
        end

        subgraph "IAM"
            ROLE[IAM Role for LBC]
            OIDC[OIDC Provider]
        end
    end

    USER -->|HTTP| ALB
    ALB --> POD
    ING -.->|defines| ALB
    LBC -->|manages| ALB
    SA -->|IRSA| ROLE
    ROLE --> OIDC
```

## リポジトリ構造

```
terraform-eks-golden-path/
├── app/                          # Go アプリケーション
│   ├── cmd/api/main.go           # エントリーポイント
│   ├── internal/
│   │   ├── handler/              # HTTP ハンドラー
│   │   └── middleware/           # ミドルウェア
│   └── Dockerfile                # マルチステージビルド
│
├── deploy/
│   ├── helm/golden-path-api/     # Helm チャート
│   │   ├── templates/            # K8s マニフェストテンプレート
│   │   ├── values.yaml           # デフォルト値
│   │   ├── values-kind.yaml      # kind 用オーバーライド
│   │   └── values-eks.yaml       # EKS 用オーバーライド
│   └── kind/                     # kind 関連設定
│       ├── kind-config.yaml      # kind クラスター設定
│       ├── prometheus-values.yaml
│       └── grafana-*.json        # Grafana ダッシュボード
│
├── infra/terraform/
│   ├── envs/dev/                 # 環境定義
│   │   ├── main.tf               # モジュール呼び出し
│   │   ├── variables.tf          # 変数定義
│   │   └── outputs.tf            # 出力定義
│   ├── modules/
│   │   ├── vpc/                  # VPC, サブネット
│   │   ├── eks/                  # EKS クラスター
│   │   └── iam/                  # IRSA
│   └── policies/                 # OPA/Rego ポリシー
│
├── docs/                         # ドキュメント
│   ├── 00-spec.md                # 設計仕様
│   ├── architecture.md           # 本ドキュメント
│   ├── runbook-*.md              # 運用手順書
│
└── .github/workflows/            # CI/CD
    ├── ci.yaml                   # メイン CI
    └── terraform.yaml            # Terraform CI
```

## データフロー

### リクエスト処理

```mermaid
sequenceDiagram
    participant C as Client
    participant I as Ingress/ALB
    participant S as Service
    participant P as Pod
    participant M as Prometheus

    C->>I: HTTP Request
    I->>S: Route by path
    S->>P: Forward to container
    P->>P: Handler処理
    P-->>S: HTTP Response
    S-->>I: Response
    I-->>C: Response

    Note over P: メトリクス更新
    M->>P: Scrape /metrics
    P-->>M: Prometheus形式
```

### デプロイフロー

```mermaid
sequenceDiagram
    participant D as Developer
    participant GH as GitHub
    participant CI as GitHub Actions
    participant K as Kubernetes

    D->>GH: git push (feature branch)
    GH->>CI: Trigger workflow
    CI->>CI: go test, lint
    CI->>CI: docker build
    CI->>CI: Trivy scan
    CI->>CI: helm lint
    CI-->>GH: Status check

    D->>GH: Create PR
    GH->>CI: Trigger checks
    CI-->>GH: All checks passed
    D->>GH: Merge to main

    D->>K: make kind-deploy / eks-deploy
    K->>K: Helm upgrade --install
```

## SLO/SLI アーキテクチャ

```mermaid
flowchart TB
    subgraph "Application"
        APP[golden-path-api]
        METRICS[/metrics endpoint]
    end

    subgraph "Monitoring Stack"
        PROM[Prometheus]
        GRAF[Grafana]
        SM[ServiceMonitor]
    end

    subgraph "SLI Metrics"
        REQ[http_requests_total]
        LAT[http_request_duration_seconds]
    end

    subgraph "SLO Targets"
        SUCCESS[成功率 99.9%]
        P95[p95 < 200ms]
        BUDGET[Error Budget]
    end

    APP --> METRICS
    SM -->|scrape| METRICS
    PROM -->|collect| SM
    PROM --> REQ
    PROM --> LAT

    REQ --> SUCCESS
    LAT --> P95
    SUCCESS --> BUDGET

    GRAF -->|query| PROM
    GRAF -->|visualize| SUCCESS
    GRAF -->|visualize| P95
    GRAF -->|visualize| BUDGET
```

## セキュリティ境界

```mermaid
flowchart TB
    subgraph "External (Internet)"
        USER[ユーザー]
    end

    subgraph "DMZ Layer"
        ALB[ALB / ingress-nginx]
    end

    subgraph "Application Layer"
        PUBLIC[公開エンドポイント<br/>/, /healthz, /readyz]
        INTERNAL[内部エンドポイント<br/>/metrics]
    end

    subgraph "Monitoring Layer"
        PROM[Prometheus]
    end

    USER -->|HTTP 80/443| ALB
    ALB -->|allowed| PUBLIC
    ALB -.->|blocked| INTERNAL
    PROM -->|cluster internal| INTERNAL

    style INTERNAL fill:#ffcccc
    style PUBLIC fill:#ccffcc
```
