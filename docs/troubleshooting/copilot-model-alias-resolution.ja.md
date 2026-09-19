# FAQ: Copilot のモデルエイリアス解決が起動前に失敗する

この FAQ は、2026 年 9 月 19 日に発生した `daily-repo-status` の関連する 2 件の失敗について、
調査結果を記録したものです。最初の実行はモデルエイリアスの解決中に停止しました。後続の実行では
具体的なモデルを使用しましたが、Copilot provider が credential を HTTP 401 で拒否し、最初の
エージェントターンより前に停止しました。

## どのような失敗か

判定に使用したログは次のとおりです。

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] copilot model alias resolution: catalog unavailable from awf-reflect for known alias 'auto'
[copilot-harness] copilot model alias resolution: retrying awf-reflect model-catalog fetch once before failing for 'auto'
[copilot-harness] copilot model alias resolution failed: model-catalog retrieval prevented alias resolution for 'auto' after a bounded refresh — refusing to start Copilot with an unresolved alias
```

[失敗した実行](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900)では、
コンテナと API proxy のヘルスチェックは成功しました。一方、Copilot が起動しなかったため、
audit ではエージェントターンと effective token がともに 0 と記録されました。

## 原因は何か

次の 4 条件が連鎖して失敗しました。

1. ワークフローでモデルを選択していなかったため、コンパイル後のワークフローは `COPILOT_MODEL` に既定のエイリアス `auto` を設定しました。
2. `auto` は具体的な Copilot model ID ではなく、gh-aw の既知のモデルエイリアスです。
3. エイリアスの解決には AWF `/reflect` が公開するモデルカタログが必要でしたが、Copilot `/models` リクエストが 2 回とも HTTP 401 を返しました。
4. gh-aw v0.88.7 は、未解決のエイリアスを Copilot に渡さず、Copilot の起動前に意図的に停止しました。

直接の原因は、モデル一覧 endpoint の認証エラー後に、モデルカタログを必要とするエイリアス解決が
失敗したことです。Squid によるネットワーク遮断やコンテナ起動失敗ではありません。firewall に
遮断されたリクエストはなく、harness の実行前に 3 個のコンテナはすべて healthy でした。

## 具体的なモデルを選択すると直るのはなぜか

v0.88.7 の resolver が live catalog を必要とするのは、設定値が既知のエイリアスキーである場合だけです。
具体的な model ID はエイリアス展開を迂回します。上流の回帰テストでも、catalog が空でも具体的な
モデルを使用できることを明示的に検証しています。

このリポジトリでは、ソースワークフローでモデルを次のように固定します。

```yaml
engine: copilot
model: claude-sonnet-4.6
```

`claude-sonnet-4.6` は v0.88.7 のモデルメタデータに含まれ、このワークフローの audit baseline で
成功実績がありました。この値は今回の事例に固有です。リポジトリの Copilot subscription と policy で
許可された具体的なモデルを使用してください。

frontmatter を変更した後は、lock ファイルを直接編集せず再生成します。

```bash
gh aw compile daily-repo-status --strict
```

生成された `.lock.yml` の `COPILOT_MODEL` は、fallback が `auto` の式ではなく、具体的な文字列に
なっている必要があります。

## 具体的なモデルを固定した後の 401 は何を意味するか

具体的なモデルの固定によってエイリアス解決時の catalog 依存はなくなりますが、モデル検出や推論時の
認証は迂回しません。[後続の実行](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052)には、
次の判定に使用できるログが含まれています。

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
Authentication failed with provider at http://172.30.0.30:10002 (HTTP 401).
[copilot-harness] attempt 2 failed: exitCode=1 failureClass=authentication_failed ... tokenCount=0
```

このログから、`claude-sonnet-4.6` が具体的なモデルとして Copilot CLI に渡され、token が生成される前に
provider が認証を拒否したことを確認できます。`Validate COPILOT_GITHUB_TOKEN secret` という activation
step は成功しましたが、この check から分かるのは secret が渡されたことだけです。この request で
credential を使用できなかったことは、provider の 401 によって示されています。

対処する repository secret は `COPILOT_GITHUB_TOKEN` です。Copilot CLI のエラーに含まれる
`COPILOT_PROVIDER_*` は内部の AWF proxy への引き渡しを表す名前であり、同名の repository secret を
追加する必要はありません。

## 保存された token が古いと断定できるか

いいえ。HTTP 401 から分かるのは provider が credential を拒否したことまでであり、credential の
lifecycle や policy 上の理由までは特定できません。期限切れまたは失効した token は有力な候補です。
ほかにも、未対応の token type、`Copilot Requests` permission の不足、token owner の有効な Copilot
license の欠如、選択したモデルを拒否する organization／model policy が候補になります。

GitHub の文書では、PAT は有効期限への到達、1 年間の未使用、公開場所への漏えい、明示的な revoke
などによって使用できなくなると説明されています。期限切れまたは revoke 済みの token は復元できないため、
新しい token を作成します。`gh secret list` が返す timestamp は Actions secret を最後に登録した時刻であり、
PAT の有効期限や有効性ではありません。また、GitHub から secret の値を取得して比較することはできません。

今回の調査では、2026 年 9 月 20 日に確認した repository metadata は次の値でした。

```json
{"name":"COPILOT_GITHUB_TOKEN","updatedAt":"2026-07-25T23:15:22Z"}
```

この日付は credential の更新を最初の切り分けとして行う根拠になりますが、保存された PAT の作成日や
期限切れを証明するものではありません。

## 互換性のある replacement token をどう作成するか

gh-aw の [fine-grained PAT 作成フォーム](https://github.com/settings/personal-access-tokens/new?name=COPILOT_GITHUB_TOKEN&description=GitHub+Agentic+Workflows+-+Copilot+engine+authentication&user_copilot_requests=read)を
使用し、token を生成する前に次の設定をすべて確認します。

1. **Resource owner** は organization ではなく、Copilot license を持つ user account です。
2. **Account permissions → Copilot Requests** は **Read** です。
3. token owner が有効な Copilot subscription と、選択したモデルへの access を持っています。

`gho_...` で始まる OAuth user token は使用しないでください。gh-aw は `COPILOT_GITHUB_TOKEN` に
PAT を要求し、OAuth user token を activation 中に拒否します。

## repository secret を手早く更新するにはどうするか

PAT を command line に含めず GitHub CLI を使用します。次のコマンドは値の入力を prompt で求め、
次回の workflow run が使用する repository secret を更新します。

```bash
gh secret set COPILOT_GITHUB_TOKEN \
  --repo ks6088ts-labs/template-github-agentic-workflows
```

secret の値だけを更新する場合は、`gh aw compile` や repository への commit は不要です。次回の run が
開始するときに、GitHub Actions が現在の secret 値を解決します。

GitHub CLI は値をローカルで暗号化してから送信します。command-line argument や shell history から
credential が漏れる可能性があるため、`--body "github_pat_..."` に PAT を直接記載しないでください。
`COPILOT_GITHUB_TOKEN` が環境変数またはこのリポジトリの gitignored `.env` に安全に設定済みの場合は、
既存の shortcut でも同じ repository secret を更新できます。

```bash
make set-secret-github-copilot-token
```

値を読み出さず、secret 名と更新 timestamp を確認します。

```bash
gh secret list \
  --repo ks6088ts-labs/template-github-agentic-workflows \
  --app actions \
  --json name,updatedAt \
  --jq '.[] | select(.name == "COPILOT_GITHUB_TOKEN")'
```

## replacement をどう検証するか

新しい PAT を安全に export した一時的なローカル shell で、まず Actions の外から同じ Copilot entitlement を
使用します。

```bash
copilot -p "Reply only with OK"
```

この確認が失敗する場合、Actions secret の入れ替えだけでは解決しません。PAT permission、Copilot license、
または organization／model policy を修正します。成功する場合は、新しい workflow run を dispatch して
audit します。

```bash
gh aw run daily-repo-status
gh aw audit <new-run-id> --json
```

1 回以上の推論ターンが開始し、0 より大きい token usage が記録されれば復旧を確認できます。activation の
secret check が成功することや、`updatedAt` が新しいことだけでは十分ではありません。

## 長期間有効な PAT を使わずに済むか

はい。Copilot の centralized billing を使用できる organization では、文書化された権限を宣言して再コンパイルし、
組み込みの GitHub Actions token を使用できます。

```yaml
permissions:
  contents: read
  copilot-requests: write
```

この方法は、organization の Copilot policy で Copilot CLI request が有効な場合に限り使用できます。

## `awf-reflect.json` の `EACCES` warning が原因か

いいえ。harness は reflection payload を `/home/runner/work/_temp/awf-reflect.json` に保存できないことも
記録しました。この warning は診断 artifact の保存に影響しますが、実行は継続しました。最初の実行は
未解決エイリアスのメッセージ後に終了し、後続の実行は Copilot CLI まで到達して
`authentication_failed` と明示的に分類されました。

reflection artifact が必要な場合は permission warning を別の runtime issue として扱います。ただし、
モデルカタログとエイリアス解決のメッセージが存在する場合、この終了の説明として permission warning を
使用しないでください。

## 同じ症状をどう診断するか

run ID を起点として、ダウンロードした audit artifact を確認します。

```bash
gh aw audit <run-id> --json
gh aw logs <workflow-name> --json
```

次の順序で signal を確認します。

| Signal | 解釈 |
| --- | --- |
| `COPILOT_MODEL: auto` または別のエイリアス | Copilot を起動する前に runtime catalog data が必要です。 |
| `models fetch returned 401` または `403` | catalog endpoint が認証または認可を拒否しています。この永続的な 4xx response は fail-fast になります。 |
| `models fetch returned 429` または `503` | catalog endpoint が一時的に利用できません。現在の gh-aw は bounded retry を行います。 |
| `refusing to start Copilot with an unresolved alias` | 想定された fail-closed 動作です。未解決のエイリアスは推論に送信されません。 |
| turn と effective token がともに 0 | モデル推論より前の harness handoff で失敗しています。 |
| 具体的なモデルでも推論時に 401 | token、entitlement、または organization policy を修正する必要があり、モデルの固定だけでは解決しません。 |
| activation の secret validation が成功した後、推論が 401 | secret は存在しますが、provider が受け付けることは確認できていません。PAT の更新または診断が必要です。 |

上流 Issue の当初の対象は HTTP 429 でした。今回の事例では HTTP 401 が返りましたが、上流の修正で
導入された同じ汎用的な fail-closed 経路に到達しています。

## 復旧手順は何か

1. リポジトリの subscription で使用できる具体的な Copilot model を選択します。
2. ソースの `*.md` ワークフローに `engine: copilot` とトップレベルの `model:` を設定します。
3. 再コンパイルし、ソースワークフローと生成された `.lock.yml` の両方をコミットします。
4. リポジトリの検証を実行してから、ワークフローを再実行します。
5. 再実行を audit し、1 回以上の推論ターンが開始されたことを確認します。
6. 推論自体が 401 を返す場合は、互換性のある PAT を作成し、`COPILOT_GITHUB_TOKEN` を更新して Copilot CLI で PAT を検証します。
7. 新しい PAT でも失敗する場合は、Copilot license、model entitlement、または organization policy を修正します。

このリポジトリでは、次の順序でローカル検証します。

```bash
gh aw compile daily-repo-status --strict
make ci-test
gh aw run daily-repo-status
```

## 一次情報と出典

| 根拠 | 一次情報 |
| --- | --- |
| 今回のログと 401／エイリアス解決失敗 | [Workflow run 35470003900](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900)と、その [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900/job/105969169242#step:26:210) |
| 具体的なモデルに対する provider の 401 と `authentication_failed` の分類 | [Workflow run 35471231052](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052)と、その [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052/job/105972518194#step:26:210) |
| エイリアスキーは catalog が必要で、具体的な ID はエイリアス解決を迂回する | [gh-aw v0.88.7 の `resolve_model_alias.cjs`](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.cjs) |
| 1 回の bounded refresh 後に fail-closed で終了する | [gh-aw v0.88.7 の `copilot_harness.cjs`](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/copilot_harness.cjs) |
| 空の catalog と具体的なモデルに対する回帰テスト | [gh-aw v0.88.7 の `resolve_model_alias.test.cjs`](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.test.cjs) |
| 当初の catalog 障害報告と設計根拠 | [github/gh-aw Issue #52782](https://github.com/github/gh-aw/issues/52782) |
| bounded retry と未解決エイリアス拒否の実装 | [github/gh-aw Pull Request #53456](https://github.com/github/gh-aw/pull/53456) |
| 今回使用した compiler／runtime version | [gh-aw v0.88.7 release](https://github.com/github/gh-aw/releases/tag/v0.88.7) |
| 対応する engine／model の設定 | [AI Engines reference](https://github.github.com/gh-aw/reference/engines/) |
| fine-grained PAT の要件、secret 設定、`copilot-requests: write` の代替経路 | [Authentication reference](https://github.github.com/gh-aw/reference/auth/)と[Billing reference](https://github.github.com/gh-aw/reference/billing/) |
| ローカルでの Copilot license／inference 診断 | [gh-aw Common Issues](https://github.github.com/gh-aw/troubleshooting/common-issues/#copilot-license-or-inference-access-issues) |
| repository secret の安全な更新と metadata の一覧表示 | [`gh secret set` manual](https://cli.github.com/manual/gh_secret_set)、[`gh secret list` manual](https://cli.github.com/manual/gh_secret_list)、[Using secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) |
| PAT の有効期限と revoke の条件 | [Token expiration and revocation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/token-expiration-and-revocation)と[Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) |
