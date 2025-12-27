# ポートフォリオ設計（Platform向け）：EKS + kind（二段構え） + Terraform

狙い：Platform Engineering 採用で「複数チームに効く標準化（Golden Path）＋強制力（Guardrails）＋再現性（IaC）」を短時間で伝える。

あなたの状況（求人がB：Kubernetes前提がバラバラ）では、

- **誰でも手元で試せる**（= 評価されやすい）: kind（ローカルKubernetes）
- **クラウドで“本番想定”を示せる**（= Platformらしさ）: EKS
を同じアプリ/同じデプロイ方式で両立するのが最も強い。

---

## 1. 追加で作る「特化ポートフォリオ」コンセプト

### コンセプト名（例）

- **Golden Path Starter（Go + Helm + Terraform）**

### 何を証明するか（採用評価軸に直結）

1. **Golden Path**：新規サービスが迷わず立ち上がる標準ルート
2. **Guardrails**：人の善意に依存せず品質・セキュリティを強制できる
3. **Reproducibility**：ローカルでもクラウドでも同じやり方で動く
4. **Operations**：観測性・アラート・runbookがセットで提供される

---

## 2. 対象スコープ（やりすぎ防止の境界）

### やる（最小で勝つ）

- 1つの小さなHTTP API（機能は薄くてOK）
- **Helm** でデプロイ（kindでもEKSでも同じチャート）
- **Terraform** でEKS環境を構築（クラウド側の証明）
- **外部公開（EKS）**：Ingress + ALB でHTTP到達できる（HTTPSは任意）
- GitHub Actions で **CIガードレール** を実装
- 観測性（最低2つ）：メトリクス + 構造化ログ（余力があればトレース）
- SLO/SLI（最低1つ）：例）成功率・レイテンシ（p95）
- runbook（最低2本）：例）高エラー率、レイテンシ劣化

### やらない（沼ポイント）

- マイクロサービス複数本
- service mesh / 複雑な認証基盤 / 便利アドオン盛り盛り
- ArgoCD/Fluxを必須化（入れても「オプション」扱い）
- マルチAZ/マルチリージョンの本格DR（説明はしても実装必須にしない）

---

## 3. 推奨アーキテクチャ（最小構成）

### ローカル（評価者が一番試す）

- kind
- Helm install
- Prometheus + Grafana（または軽量な代替）
- Ingress（ローカル用）：ingress-nginx等でHTTP到達（EKSのIngressと“概念”を揃える）

### クラウド（Platformらしさの証明）

- AWS EKS（Managed Node Group）
- **外部公開**：AWS Load Balancer Controller（ALB Ingress）でHTTP到達
  - 最小：ALBのDNS名でアクセス（独自ドメイン無し）
  - 余力：Route53で独自ドメイン割当（任意）
  - 余力：ACMでTLS終端（HTTPS）（任意だが見栄えは良い）

#### 外部公開方式の決定（このポートフォリオの前提）

- **EKSはALB Ingress（AWS Load Balancer Controller）で統一**
  - `Service=LoadBalancer` 方式は採用しない（Platformらしい標準化を見せるため）

#### 外部公開の「必須/任意」境界

- 必須：HTTPで到達（ALB + Ingress）
- 任意：独自ドメイン（Route53）
- 任意：HTTPS（ACM）

#### 独自ドメインが無い場合の扱い（前提）

- このポートフォリオでは **ALBのDNS名でHTTP到達** をMVPの完成条件とする
  - 例：`http://xxxxx.elb.amazonaws.com`
- HTTPS（ACM + Route53）は **独自ドメインが前提** になりやすいため、実装の必須要件にはしない
  - ただし「どう拡張するか」は設計として明記し、Terraform変数で拡張可能な方針にする

#### 外部公開でTerraformが作るもの（例）

- VPC（public/private subnets、EKS用タグ）
- EKS cluster / node group
- IAM（IRSA：AWS Load Balancer Controller用）
- Security Group（最小開放：ALBは80/443、Pod間は必要最小限）
- （任意）Route53 record
- （任意）ACM certificate

---

## 4. リポジトリ構成

```txt
repo/
  README.md                    # 主要ドキュメント（What/Why, Golden Path, Quickstart, Guardrails, Observability, Terraform）
  Makefile                     # コマンド契約（kind-*, eks-*, ci 等）
  docs/
    00-spec.md                 # 設計仕様書（本ドキュメント）
    architecture.md            # アーキテクチャ図（Mermaid）
    runbook-high-error-rate.md # Runbook: 高エラー率
    runbook-latency-regression.md # Runbook: レイテンシ劣化
  app/
    cmd/api/                   # エントリーポイント
    internal/                  # ハンドラー、ミドルウェア
    Dockerfile                 # マルチステージビルド
  deploy/
    helm/
      golden-path-api/         # Helm チャート（kind/EKS 共通）
        values.yaml            # 共通設定
        values-kind.yaml       # kind 用オーバーライド
        values-eks.yaml        # EKS 用オーバーライド
    kind/
      kind-config.yaml         # kind クラスター設定
      prometheus-values.yaml   # kube-prometheus-stack 設定
      grafana-dashboard.json   # カスタムダッシュボード
  infra/
    terraform/
      envs/dev/                # 環境定義（dev のみ実装）
      modules/
        vpc/                   # VPC、サブネット、IGW
        eks/                   # EKS クラスター、ノードグループ
        iam/                   # IRSA（AWS LBC 用）
      policies/                # OPA/Conftest ポリシー
  .github/
    workflows/
      ci.yaml                  # Go lint/test, Docker build, Helm lint
      terraform.yaml           # Terraform fmt/validate
    copilot-instructions.md    # Copilot 用コンテキスト
```

> **設計方針**: 主要なコンテンツは README.md に統合し、評価者が最短で全体像を把握できるようにしている。
> docs/ には設計仕様書（本ドキュメント）、アーキテクチャ図、運用 Runbook のみを配置する。

---

## 5. READMEの必須セクション（採用で効く順）

1. **What / Why（何を解く標準か）**
   - “新規サービスが運用可能な形で立ち上がる”
   - “判断コスト・属人性を減らす”

2. **Quickstart（5〜10分）**
   - kindで立ち上げ → 1リクエスト → メトリクス確認

3. **Golden Path（標準ルートの定義）**
   - logging / metrics / config / health / deploy の標準

4. **Guardrails（強制力）**
   - CIで落ちる例（わざと失敗させる）を1つ用意すると強い

5. **Observability / SLO**
   - どの指標を、どう計測し、どの閾値でアラートするか

6. **Runbook（運用手順）**
   - 例）High error rate / Latency regression

7. **Terraform（EKS構築）**
   - 何を作るか、権限分離/状態管理の方針

---

## 6. Guardrails（CI）で入れると強いチェック

最低限

- go test / lint
- Docker build
- Terraform fmt / validate
- SBOM or 依存脆弱性スキャン（どちらか）

できれば（余力）

- policy as code（例：OPA/Conftest）でTerraformの禁止ルール
  - 例）Public S3禁止、0.0.0.0/0のSG禁止、など

---

## 7. 具体的な「運用シナリオ」例（1〜2個で十分）

- **シナリオA：レイテンシ劣化**
  - SLI：p95 latency
  - 兆候：メトリクス上昇 → アラート
  - 切り分け：CPU/メモリ、依存先、ログ相関
  - 対応：リソース調整、ロールバック、恒久対応の記載

- **シナリオB：エラー率増加**
  - SLI：success rate
  - 切り分け：エラー種別、直近デプロイ、設定差分
  - 対応：フェイルオープン/クローズ、リトライ方針

---

## 8. マイルストーン（完成定義）

### MVP（採用に出せる最小）

- kindで `make up` 相当のコマンドで起動
- `/healthz` と `/metrics` がある
- Grafanaダッシュボード1枚
- CIが動く
- runbook 2本

### EKS外部公開（今回の必須）

- TerraformでEKSが作れる
- AWS Load Balancer Controller（IRSA含む）を導入できる
- Ingress経由で **インターネットからHTTPアクセス** できる（ALB DNSでも可）

### Plus（差別化）

- TerraformでEKSを構築（plan/applyは手順と前提が明記）
- OIDCでCIからTerraform plan
- guardrails（OPA等）1つ
- Route53 + ACMでHTTPS（独自ドメイン）

---

## 9. ここまでの方針に沿った判断

- **言語**：Go（Platform文脈と相性が良い／既存ポートフォリオとも整合）
- **IaC**：Terraform（狙う領域へのシグナルが強い）
- **基盤**：B（バラつく）なので **EKS + kind** が最適

---

## 10. 次に決めるとブレない2点

1. デプロイ方式：Helmで統一（kind/EKS共通）
2. 観測性の最小セット：メトリクス + 構造化ログ（トレースは余力）

---

## 11. 外部公開の実装でハマりやすい点（先回りメモ）

- EKSのサブネット/タグが正しくないとALBが作られない（Terraform側でタグを標準化する）
- AWS Load Balancer ControllerはIRSA前提にする（アクセスキー直設定は避ける）
- 公開範囲を最小化する（ALBは80/443のみ、アプリの管理系エンドポイントは閉じる）
- まずはHTTP公開で完了扱いにして、HTTPSはPlusに回す（スコープ肥大防止）

---

## 12. HTTP外部公開でも「弱く見えない」ためのセキュリティ/運用の見せ方

独自ドメイン無しでHTTPSを必須にしない場合でも、Platform採用で重要なのは
「セキュリティ・信頼性が設計のデフォルトになっているか」なので、以下をREADME/設計で必ず言語化する。

### 公開面（Exposure）

- 外部公開するのは **必要なパスのみ**（例：`/` または `/api/*`）
- `/metrics` は外部公開しない（cluster内または認証付きのみ）
- `/debug` や管理系エンドポイントは無効化/非公開

### 権限（Least Privilege）

- AWS Load Balancer Controllerは **IRSA** で最小権限
- Terraform用の実行権限は環境分離（dev/stg/prod想定の権限境界を説明）

### 機密（Secrets）

- 機密はGitに置かない（Kubernetes Secretや外部Secret管理の方針を明記）
- 例としてダミー値で動くようにし、実運用時の差分（Secret投入手順）をREADMEに書く

### 監査/変更（Change Management）

- 「何が変わったか」を追跡できる（CIのチェック、Terraform planの提示、差分のレビュー前提）

### HTTPSへの拡張方針（Plus）

- Route53（独自ドメイン） + ACM（証明書） + Ingress annotations の追加でHTTPS終端可能
- 追加に必要な入力（ドメイン名、Hosted Zone、証明書ARN等）をTerraform変数として定義する方針

---

## 実装仕様（このドキュメント1枚で再開できるレベル）

## 13. Non-goals（やらないこと：沼回避の“契約”）

このポートフォリオは「Platform向けの標準化＋ガードレール」を示すのが目的であり、以下は**意図的にやらない**。

- サービスを複数本に増やさない（1サービスで十分）
- マルチテナント設計、課金、ユーザー管理などプロダクト機能を作り込まない
- Service Mesh / eBPF / 高度なネットワーク制御は入れない
- GitOps（ArgoCD/Flux）を必須化しない（入れるなら“任意の拡張”として別章）
- 本格的なDR（複数リージョン）や厳密なコンプライアンス要件は対象外

---

## 14. 完成条件（Acceptance Criteria）

### 14.1 MVP（kind：評価者が最短で試せる）

#### セットアップと到達性

- [ ] `make kind-up` でkindクラスターが作成される
- [ ] `make kind-deploy` でアプリがデプロイされる
- [ ] `make kind-url` でHTTPの到達先が表示される（localhostでもOK）
- [ ] ブラウザ/`curl`でHTTP 200が返る

#### 運用前提の機能（アプリ）

- [ ] `/healthz` があり、依存無しで200を返す
- [ ] `/readyz` があり、起動直後はReadyにならない設計になっている（例：初期化完了後にReady）
- [ ] `/metrics` があり、Prometheus形式でメトリクスが出る
- [ ] 構造化ログ（JSON）でリクエスト単位のログが出る（最低：method/path/status/latency）

#### 観測性

- [ ] Prometheusがスクレイプできる（ServiceMonitorでも手動でも可）
- [ ] Grafanaダッシュボード1枚が用意され、最低限の指標が見える（RPS、エラー率、p95）

#### ドキュメント

- [ ] READMEにQuickstart（5〜10分）がある
- [ ] runbookが最低2本ある（高エラー率、レイテンシ劣化）

### 14.2 EKS外部公開（本番想定：Platformらしさ）

#### Terraform

- [ ] `make eks-plan` でplanできる
- [ ] `make eks-apply` でEKSが作成できる
- [ ] `make eks-destroy` で後片付けできる

#### ALB Ingress

- [ ] AWS Load Balancer ControllerをIRSAで導入できる
- [ ] Ingress作成でALBが払い出される
- [ ] ALB DNSでHTTP到達できる

#### 公開面の最小化

- [ ] 外部公開するパスが最小化されている（例：`/` or `/api/*`）
- [ ] `/metrics`は外部公開しない

### 14.3 Plus（差別化・余力）

- [ ] GitHub Actionsでterraform planを自動実行（OIDC or 最小の安全な方法）
- [ ] policy as code（OPA/Conftest等）でTerraformの禁止ルールを1つ以上
- [ ] HTTPS（Route53 + ACM + Ingress annotations）は拡張として設計/実装可能

---

## 15. コマンド契約（Makefileターゲット案）

“入口のコマンド”が固定されていること自体がPlatformらしいので、Makefileで契約化する。

### 15.1 kind（ローカル）

- `make kind-up`：kind作成 + 必要アドオン（ingress-nginx, prometheus/grafana等）の導入
- `make kind-down`：kind削除
- `make kind-deploy`：Helmでアプリをデプロイ
- `make kind-undeploy`：アプリ削除
- `make kind-url`：到達URLを表示（例：ingressのhost/portを出す）
- `make kind-logs`：アプリのログを見る
- `make kind-grafana`：Grafanaに到達する（例：port-forward）
- `make kind-prometheus`：Prometheusに到達する（例：port-forward）
- `make kind-status`：主要リソースの状態を表示（pods/ingress/svc）

### 15.2 EKS（クラウド）

- `make eks-plan`：Terraform plan
- `make eks-apply`：Terraform apply
- `make eks-destroy`：Terraform destroy
- `make eks-kubeconfig`：kubectl接続設定
- `make eks-install-lbc`：AWS Load Balancer Controller導入（IRSA前提）
- `make eks-deploy`：Helmでアプリをデプロイ
- `make eks-url`：ALB DNSを表示
- `make eks-undeploy`：アプリ削除
- `make eks-status`：主要リソースの状態を表示（nodes/pods/ingress/targetgroup）

### 15.3 ツール前提（バージョン目安）

実装時に詰まりやすいので、READMEに以下を前提として明記する。

- Go：最新安定系（例：1.22+ など）
- Terraform：1.x系
- kubectl：EKSのKubernetesバージョンと概ね同世代
- Helm：3.x
- kind：0.2x系
- AWS CLI：2.x

※厳密な固定が不要なら「目安」だけでOK。固定する場合は`tool-versions`（asdf）等で明文化する。

---

## 16. Terraform仕様（構成・責務・変数）

### 16.1 方針

- **モジュール分割**：責務境界が明確で、読みやすいこと（Platformらしさ）
- **state**：ローカルでも動く前提で開始し、READMEに「本来はS3+DynamoDB等で共有する」方針を書く
  - ポートフォリオとしては「まずローカルstateで動く」ことを優先
  - PlusとしてS3 backend + DynamoDB lockまで実装できると、Platformらしさが上がる
- **環境**：`dev`だけ実装してよい。ただし「stg/prodへ広げる設計」は示す

### 16.2 ディレクトリ設計（例）

- `infra/terraform/envs/dev`：環境定義（module呼び出し、tfvars）
- `infra/terraform/modules/vpc`：VPC、サブネット、IGW/NAT、EKS用タグ
- `infra/terraform/modules/eks`：EKS cluster / managed node group
- `infra/terraform/modules/iam`：IRSA前提のIAM（ポリシー、ロール）
- `infra/terraform/modules/alb`：AWS Load Balancer Controller用のIAM/設定（実体はiamに寄せてもOK）

### 16.3 最低限の変数（envs/dev）

- `aws_region`
- `project_name`
- `env`（例：`dev`）
- `cluster_name`
- `kubernetes_version`
- `node_instance_types`（またはnode_group設定）
- `vpc_cidr`
- `public_subnet_cidrs` / `private_subnet_cidrs`（MVPはpublicのみでもOK。privateはPlusで追加）

#### 推奨デフォルト（迷子防止）

- `aws_region`：`ap-northeast-1`（固定）
- `kubernetes_version`：EKSでサポートされる「最新の安定系」を採用（例：`1.31` など）

#### 命名規約（Terraform/Helm/タグを揃える）

- `project_name`：`terraform-eks-golden-path`（固定）
- `env`：`dev`（MVPはこれだけでOK）
- `cluster_name`：`${project_name}-${env}`（例：`terraform-eks-golden-path-dev`）

※AWSリソースの `Name` タグやKubernetesのnamespace/prefixにも、原則このprefix（`${project_name}-${env}`）を使う。

#### VPC方針（MVPはコスト最小を優先）

- MVP：**public subnetのみ**で成立させる（NAT Gatewayを作らない）
  - 目的：検証コストと後片付けの難易度を下げる
- Plus：private subnet + NAT Gateway を追加し、本番寄り構成に寄せる
  - 目的：より“Platformらしい”標準構成として説明できる

### 16.4 出力（outputs）

- `cluster_name`
- `cluster_endpoint`
- `cluster_ca`
- `public_subnet_ids` / `private_subnet_ids`
- `aws_load_balancer_controller_iam_role_arn`（IRSA確認用）

### 16.5 外部公開の要点（Terraform側）

- SubnetにEKS/ALB用のタグを付与する（ここが一番詰まりやすい）
- IRSA用のOIDC ProviderをEKSに紐付ける（moduleで隠蔽して良い）

### 16.6 サブネットタグ（EKS/ALBで詰まりやすいので具体を固定）

Terraform側で最低限、以下のようなタグを付与して「ALBが作れない」を回避する。

- サブネット共通（例）
  - `kubernetes.io/cluster/<cluster_name> = shared`（またはowned）
- Public subnet（ALB: internet-facing を置く想定）
  - `kubernetes.io/role/elb = 1`
- Private subnet（ALB: internal を置く想定。MVPでinternalを使わないなら後回しでもOK）
  - `kubernetes.io/role/internal-elb = 1`

※最終的に「MVPはinternet-facingのみ」なら、まずはPublic側のタグを確実に入れて動く状態を優先する。

---

## 17. Kubernetes/Helm仕様（valuesの“契約”）

### 17.1 Helmチャートが提供すべきもの

- Deployment / Service
- Ingress（kind/EKSで共通のvaluesインタフェース）
- ServiceAccount（IRSA/将来拡張を見据えて作成）
- ConfigMap（アプリ設定の受け口：env）

### 17.2 values.yaml（例：インタフェースだけ固定）

- `image.repository` / `image.tag`
- `service.port`
- `ingress.enabled`
- `ingress.className`
- `ingress.hosts`（kind用はlocalhost、EKS用は空でも可）
- `ingress.path`（公開パス最小化のため明示）
- `metrics.enabled`（ただし外部公開はしない）
- `resources.requests/limits`

### 17.3 Ingressの実装指針

- kind：ingress-nginxのIngressClass（例：`nginx`）
- EKS：ALB Ingress（IngressClassは`alb`、annotationsでALB設定）
- ただし「valuesの使い方」は共通にして、環境差分は`values-kind.yaml` / `values-eks.yaml`で吸収する

#### IngressClassの扱い（迷子防止）

- 基本は `spec.ingressClassName` を使う（例：`alb` / `nginx`）
- `kubernetes.io/ingress.class` のannotationはレガシー寄りなので、使う場合はREADMEに理由を書く

#### EKS（ALB）向け：最小アノテーション例（MVP）

MVPでは「HTTPでALB DNS到達」が完成条件なので、まずは以下を基本セットとして固定する。

- `alb.ingress.kubernetes.io/scheme: internet-facing`
- `alb.ingress.kubernetes.io/target-type: ip`

※HTTPS（ACM/証明書、リダイレクト）はPlus側で追加する。

---

## 18. kind環境（ローカル再現性）

### 18.1 目的

- AWSアカウント不要で、面接官/評価者が動かせる
- Kubernetesの概念（Ingress/Service/Deploy/観測性）を体験できる

### 18.2 採用するもの（例）

- kind
- ingress-nginx
- kube-prometheus-stack（重ければ軽量構成でも良い）

#### 重要：Grafana/Prometheusへの到達方法

- 余計な公開を避けるため、ローカルは基本 `kubectl port-forward` で到達する
  - 例：`make kind-grafana` / `make kind-prometheus` でport-forwardを張る

### 18.3 Quickstartの最小手順（READMEに載せる想定）

1. 前提ツールをインストール（kind, kubectl, helm）
2. `make kind-up`
3. `make kind-deploy`
4. `make kind-url` でアクセス
5. Grafanaでダッシュボード確認（ログイン情報はREADMEへ）

---

## 19. EKS外部公開（ALB Ingress）実装手順の骨子

### 19.1 前提（READMEに明記）

- AWSアカウントと請求が発生すること（検証後にdestroyする）
- `awscli` / `kubectl` / `helm` / `terraform` が必要

#### AWS前提（よく詰まるので明記）

- Terraformを実行できる認証情報が必要（例：`AWS_PROFILE`）
- EKS/EC2/VPC/IAM/ELB周りを作成できる権限が必要
- コストが発生するため、検証後は `make eks-destroy` を必ず実行する

### 19.2 手順（概略）

1. `make eks-apply`
2. `make eks-kubeconfig`
3. `make eks-install-lbc`
4. `make eks-deploy`
5. `make eks-url`（ALB DNSを出す）
6. `curl http://<ALB-DNS>/...` で確認

### 19.3 AWS Load Balancer Controller導入（要点）

- IRSAでServiceAccountにIAM Roleを紐付け
- Ingressを作るとALBが作成される
- セキュリティグループの開放は80（必要なら443も）だけ

#### 導入方式（迷わないための決め）

- LBCの導入は **Helm** で統一する（TerraformでIRSAを用意し、HelmでControllerを入れる）
  - Terraform：IRSA（IAM Role/Policy/OIDC）
  - Helm：`aws-load-balancer-controller` のリリース
- チャート/イメージのバージョンは原則ピン留めする（READMEに“固定している理由”を一言添える）

#### Helmインストール（IRSA前提の最小コマンド例）

Context7で確認した推奨形：IRSAを使う場合、ServiceAccountはTerraform側で作り、Helm側では `serviceAccount.create=false` にする。

```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

※`make eks-install-lbc` はこの形を内包し、`clusterName` と（必要なら）チャートversionを引数/変数で固定する。

---

## 19.4 イメージ配布（EKSで動かすための前提）

kindはローカルイメージをロードできるが、EKSはノードがpullできる場所が必要。

- 推奨：**GHCR（GitHub Container Registry）でPublicイメージ**を配布
  - 認証無しでpullできるため、評価者の再現性が上がる
  - `make image-build` / `make image-push` を用意して運用を標準化する
- 代替：ECR（よりAWSらしいが、評価者がAWSに依存しやすい）

---

## 20. CI/Guardrails 仕様（最低限の合格ライン）

### 20.1 CIで必ず落とす（例）

- lint違反
- unit test失敗
- `terraform fmt` 未適用
- `terraform validate` 失敗
- 依存関係スキャンでHigh以上（運用はチーム方針により調整、ポートフォリオでは基準を明記）

### 20.2 ワークフロー例

- `ci.yaml`
  - Go：lint/test
  - Docker build
  - Helm lint（可能なら）
- `terraform.yaml`
  - fmt/validate
  - （Plus）plan

#### CIの追加前提（READMEに書くと親切）

- `terraform plan` をCIで回す場合、AWS認証方法を明記する（OIDC推奨）
- OIDCをやらない場合は「ポートフォリオではplanのみローカル実行」と割り切っても良い

---

## 21. SLO/SLI（最小定義）とダッシュボード要件

### 21.1 SLI（例）

- **成功率**：`2xx / total`（直近5分など）
- **レイテンシ**：p95（直近5分など）

### 21.2 SLO（例：ポートフォリオ用の仮値）

- 成功率：99.9%（5分窓）
- p95レイテンシ：200ms以下（5分窓）

### 21.3 ダッシュボード（最低パネル）

- RPS
- エラー率（4xx/5xxの内訳）
- p95レイテンシ
- PodのCPU/メモリ（基本の切り分け用）

---

## 22. Runbook（2本）テンプレ

### 22.1 Runbook：High error rate

- 症状：成功率SLO割れ、5xx増加
- まず見る：直近デプロイ、Pod再起動、依存先
- 切り分け：ログのエラー種別、エンドポイント別、直近の設定変更
- 対応：ロールバック/スケール/一時的な緩和（例：タイムアウト/リトライ）
- 恒久対応：原因の分類と再発防止（テスト、ガードレール強化）

### 22.2 Runbook：Latency regression

- 症状：p95上昇、タイムアウト
- まず見る：CPU/メモリ、HPAが無いならレプリカ数、ALB/Ingressの状況
- 切り分け：遅いエンドポイント、外部呼び出し、GC等（Goなら）
- 対応：スケール、リソース調整、ロールバック
- 恒久対応：メトリクス追加、ボトルネックの設計見直し

---

## 23. 決定事項サマリ（リセット耐性）

- 狙い：Platform採用向け（Golden Path/Guardrails/Reproducibility/Operations）
- リポジトリ名：`terraform-eks-golden-path`
- 言語：Go
- IaC：Terraform
- K8s：kind（ローカル） + EKS（クラウド）の二段構え
- 外部公開：EKSはALB Ingress（AWS Load Balancer Controller）で統一
- 独自ドメイン無し：MVPはALB DNSでHTTP到達、HTTPSはPlus扱い

---

## 24. コスト/クリーンアップ（EKS検証で必須）

### 24.1 何にコストが乗りやすいか

- EKSクラスタ（コントロールプレーン）
- ノード（EC2）
- ALB
- NAT Gateway（VPC設計次第でコスト増）

### 24.2 最低限の運用ルール

- 検証が終わったら `make eks-destroy` を必ず実行
- READMEに「作成物一覧（高レベル）」と「削除の手順」を明記
