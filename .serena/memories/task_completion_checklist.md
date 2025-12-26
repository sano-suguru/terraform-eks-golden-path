# タスク完了時のチェックリスト

## コード変更時

1. **lint 実行**
   ```bash
   make lint
   ```

2. **テスト実行**
   ```bash
   make test
   ```

3. **Docker ビルド確認**
   ```bash
   make image-build
   ```

4. **CI 一括チェック（推奨）**
   ```bash
   make ci   # lint + test + image-build を一括実行
   ```

## Terraform 変更時

1. **フォーマット**
   ```bash
   make tf-fmt
   ```

2. **検証**
   ```bash
   make tf-validate
   ```

3. **Plan 確認**
   ```bash
   make eks-plan
   ```

## コミット・PR 作成

1. **feature ブランチ作成**
   ```bash
   git checkout -b feature/変更内容
   ```

2. **変更をコミット**（日本語メッセージ）
   ```bash
   git add -A
   git commit -m "feat: 変更内容の説明"
   ```

3. **プッシュ & PR 作成**
   ```bash
   git push -u origin feature/変更内容
   GH_PAGER='' gh pr create --title "タイトル" --body "説明"
   ```

4. **CI 結果確認**
   ```bash
   GH_PAGER='' gh pr checks <PR番号> --watch
   ```

5. **マージ**
   ```bash
   GH_PAGER='' gh pr merge <PR番号> --squash --delete-branch --admin
   ```

## EKS 環境での作業後

⚠️ **コスト発生注意**: 検証後は必ず削除

```bash
make eks-destroy
```
