# Copilot engine の起動失敗のトラブルシューティング

このガイドでは、Copilot harness まで到達したものの、最初の agent turn より前に停止する
GitHub Agentic Workflows を扱います。モデルの利用可否、モデルエイリアスの解決、PAT 認証、
組み込みの GitHub Actions token による認証を対象とします。ここで示す例は、Bring Your Own Key
（BYOK）provider ではなく、デフォルトの GitHub Copilot 経路を前提としています。

> [!IMPORTANT]
> 最初に出現する具体的な provider または harness のエラーから調査を始めます。
> `all retries exhausted` のような最後のメッセージが示すのは結果であり、根本原因ではありません。
> agent turn と effective token がともに 0 であれば推論前の失敗だと確認できますが、
> それだけでは原因を特定できません。

## 迅速な切り分け

| ログの signal | 診断 | 最初の対処 |
| --- | --- | --- |
| HTTP 400 と `requested model is not available` | 具体的なモデルを現在の integrator、entitlement、または policy で利用できません。 | 同時に出力された `Available models` 一覧から具体的な ID を選択します。 |
| `catalog unavailable` に続く `refusing to start Copilot with an unresolved alias` | モデルカタログを利用できないため、`auto` などのエイリアスを解決できませんでした。 | 直前の catalog status から、認証エラー（`401`）か一時的なサービス障害（`429` または `503`）かを判定します。 |
| PAT 経路での HTTP 401 と `Authentication failed` | provider が `COPILOT_GITHUB_TOKEN` または token owner の entitlement を拒否しました。 | token type、permission、有効性、Copilot license、モデルへの access を確認します。 |
| `S2STOKENS: true` と HTTP 403 | 組み込みの Actions token に、organization 課金による Copilot access がありません。 | organization の centralized billing を有効にするか、PAT 認証へ明示的に切り替えます。 |
| `awf-reflect.json` と `EACCES` | 診断 artifact を保存できませんでした。 | 後続のモデルまたは認証エラーで実際の失敗を特定できる場合は、別の問題として扱います。 |

## 証拠を収集する

失敗した実行の audit と log を取得します。

```bash
gh aw audit <run-id> --json
gh aw logs <workflow-name> --json
```

次の signal を順番に確認します。

1. 最初に出現する明示的な HTTP 400、401、403、429、または 503 のメッセージ。
2. `inference routing` 行と、その `configuredModel` の値。
3. ソースの Markdown workflow にある `engine`、`model`、`permissions`。
4. 生成された `.lock.yml` にある `COPILOT_MODEL`、`COPILOT_GITHUB_TOKEN`、`S2STOKENS`。
5. audit に記録された agent turn と effective token usage。

`.lock.yml` は直接編集しません。ソースワークフローから生成されるファイルです。

## HTTP 400: 具体的なモデルを利用できない

### HTTP 400 のログ

```text
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
400 The requested model is not available for integrator "agentic-workflows". Available models: [... claude-sonnet-5 ...]
[copilot-harness] all 3 retries exhausted — giving up (exitCode=1)
```

### HTTP 400 の診断

workflow は具体的な model ID を指定して Copilot CLI まで到達しましたが、provider が推論前に
その ID を拒否しました。これはエイリアス解決エラーではなく、認証や network の失敗とも異なります。

モデルの利用可否は integrator、account entitlement、policy に依存し、時間とともに変わることがあります。
古い compiler catalog や以前の成功実績より、現在の response にある `Available models` 一覧を優先します。

### HTTP 400 の復旧

response の一覧から ID を選び、ソースワークフローに設定します。上記の例では、次のように変更します。

```yaml
engine:
  id: copilot
  model: claude-sonnet-5
```

ワークフローを再コンパイルし、生成された `COPILOT_MODEL` に置換後の ID が設定されたことを
確認します。利用できないモデルは、retry を繰り返しても有効になりません。

## エイリアス解決: モデルカタログを利用できない

### エイリアス解決のログ

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] copilot model alias resolution: catalog unavailable from awf-reflect for known alias 'auto'
[copilot-harness] copilot model alias resolution: retrying awf-reflect model-catalog fetch once before failing for 'auto'
[copilot-harness] copilot model alias resolution failed: model-catalog retrieval prevented alias resolution for 'auto' after a bounded refresh — refusing to start Copilot with an unresolved alias
```

### エイリアス解決の診断

`auto` は具体的な Copilot model ID ではなく、モデルエイリアスです。解決には runtime の
モデルカタログが必要です。harness は未解決のエイリアスを推論へ渡さず、fail-closed で停止します。

catalog status に応じて次のように対処します。

- HTTP 401: 選択されている認証経路を修正します。
- HTTP 429 または 503: catalog service の復旧後に再実行します。

### エイリアス解決の復旧

最初に catalog のエラーを解消します。エイリアス展開時の catalog 依存をなくすには、現在の
runtime が公開している具体的なモデルを設定し、再コンパイルします。具体的なモデルはエイリアス展開を
迂回しますが、モデル検出や推論時の認証は迂回しません。

## HTTP 401: PAT 認証が拒否される

### HTTP 401 のログ

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
Authentication failed with provider at http://172.30.0.30:10002 (HTTP 401).
[copilot-harness] attempt 2 failed: exitCode=1 failureClass=authentication_failed ... tokenCount=0
```

### HTTP 401 の診断

provider は token を生成する前に credential を拒否しました。activation check の成功から分かるのは、
secret が渡されたことだけです。同様に、`gh secret list` の `updatedAt` が示すのは secret の登録日時であり、
PAT が有効であることは証明できません。

HTTP 401 だけでは token の期限切れを断定できません。期限切れまたは revoke 済みの PAT、未対応の
token type、`Copilot Requests` permission の不足、token owner の有効な Copilot license の欠如、
選択したモデルを遮断する policy などが候補です。

### HTTP 401 の復旧

最初に PAT 経路が選択されていることを確認します。PAT を使う場合、ソースワークフローで
organization 課金を明示的に無効化します。

```yaml
permissions:
  contents: read
  copilot-requests: none
```

生成されたワークフローでは、repository secret から `COPILOT_GITHUB_TOKEN` を読み込み、
`S2STOKENS: true` を設定していない必要があります。

次の条件をすべて満たす fine-grained PAT を作成します。

1. Resource owner は organization ではなく、Copilot license を持つ user account です。
2. **Account permissions > Copilot Requests** は **Read** です。
3. token owner に有効な Copilot subscription と、選択したモデルへの access があります。
4. `gho_...` などの OAuth user token ではなく、PAT を使用します。

PAT を command-line argument に含めず、repository secret を更新します。

```bash
gh secret set COPILOT_GITHUB_TOKEN
```

置換後の PAT を安全に export した一時的な shell で、Actions の外から同じ entitlement を検証します。

```bash
copilot -p "Reply only with OK"
```

ローカルの request が失敗する場合は、workflow を再実行する前に token、license、entitlement、
または policy を修正します。デフォルトの GitHub Copilot 経路では、一般的な CLI メッセージを理由に
`COPILOT_PROVIDER_*` repository secret を追加しないでください。これらの変数は、明示的に設定した
BYOK provider で使用します。

## HTTP 403: 組み込みの Actions token が認可されない

### HTTP 403 のログ

```text
S2STOKENS: true
[copilot-harness] awf-reflect: models fetch returned 403 for http://api-proxy:10002/models
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-5" endpoint=managed-by-copilot-cli
Authentication failed with provider at http://172.30.0.30:10002 (HTTP 403).
[copilot-harness] attempt 2: Copilot requests authentication failed through the gh-aw API proxy (HTTP 403, model=claude-sonnet-5, stage=starting the Copilot CLI request).
```

### HTTP 403 の診断

`S2STOKENS: true` は、`copilot-requests: write` によって選択された organization 課金の経路を示します。
この mode では、gh-aw は推論に `${{ github.token }}` を使用し、`COPILOT_GITHUB_TOKEN` という名前の
repository secret を無視します。その secret を更新しても、認証経路は変わりません。

403 によって Copilot の認可失敗まで切り分けられますが、不足している管理上の前提条件までは特定できません。

### HTTP 403 の復旧

organization 課金を使用する場合は、次の設定を維持します。

```yaml
permissions:
  contents: read
  copilot-requests: write
```

organization 管理者に、有効な Copilot subscription があることと、organization policy で
Copilot CLI request の centralized billing が許可されていることを確認してもらいます。
workflow の permission を変更した後は再コンパイルします。

centralized billing を利用できない場合は、PAT 経路へ明示的に切り替えます。

```yaml
permissions:
  contents: read
  copilot-requests: none
```

次に、HTTP 401 の節に従って `COPILOT_GITHUB_TOKEN` を設定し、再コンパイルします。
PAT が優先されることを期待して、両方の経路を同時に設定しないでください。

## `awf-reflect.json` の `EACCES` warning

`/home/runner/work/_temp/awf-reflect.json` と `EACCES` を含む warning は、harness が診断用の
reflection artifact を保存できなかったことを示します。実行が継続し、その後に明示的なモデルまたは
認証エラーが出た場合は、後続のエラーが起動失敗の原因です。

reflection file が必要な場合や、終了理由を説明する後続エラーがない場合に、artifact path と runner の
permission を調査します。明示的な HTTP 400、401、403 response の説明には、この warning を使用しません。

## 再コンパイルして検証する

ソースワークフローの変更後は、lock file を再生成して検証し、新しい実行を開始して audit します。

```bash
gh aw compile <workflow-name> --strict
gh aw validate
gh aw run <workflow-name>
gh aw audit <new-run-id> --json
```

repository secret だけを変更した場合は、コンパイルや commit は不要です。`engine`、`model`、
`permissions` を変更した場合は必要です。

次の条件を満たしたときに復旧を確認できます。

1. 生成された lock file に、意図したモデルと認証経路が設定されています。
2. 元の provider またはエイリアス解決エラーが出ていません。
3. 1 回以上の推論ターンが開始し、token usage が 0 より大きくなっています。

## 復旧チェックリスト

1. 最後の retry message ではなく、最初の具体的な provider error を分類します。
2. `permissions` と `S2STOKENS` から認証経路を判定します。
3. HTTP 400 では、現在の `Available models` response からモデルを選択します。
4. HTTP 401 では、PAT、permission、token owner の Copilot access を修正します。
5. `S2STOKENS: true` を伴う HTTP 403 では、organization 課金を有効にするか、PAT 経路へ明示的に切り替えます。
6. ソースの変更後は再コンパイルし、`.lock.yml` は直接編集しません。
7. 再実行し、推論ターンと 0 より大きい token usage を確認します。

## 一次情報

次の資料はすべて GitHub が提供しています。

- [GitHub Agentic Workflows: AI engine](https://github.github.com/gh-aw/reference/engines/)
- [GitHub Agentic Workflows: 認証](https://github.github.com/gh-aw/reference/auth/)
- [GitHub Agentic Workflows: 課金](https://github.github.com/gh-aw/reference/billing/)
- [GitHub Agentic Workflows: よくある問題](https://github.github.com/gh-aw/troubleshooting/common-issues/)
- [GitHub Agentic Workflows: workflow のデバッグ](https://github.github.com/gh-aw/troubleshooting/debugging/)
- [GitHub Docs: GitHub Actions での secret の使用](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [GitHub Docs: token の有効期限と revoke](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/token-expiration-and-revocation)
- [GitHub CLI manual: `gh secret set`](https://cli.github.com/manual/gh_secret_set)
