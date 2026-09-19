# FAQ: Copilot のモデル選択が起動前に失敗する

この FAQ は、2026 年 9 月 19 日から 20 日に発生した `daily-repo-status` の関連する 3 件の失敗について、
調査結果を記録したものです。最初の実行はモデルエイリアスの解決中に停止しました。後続の実行では
具体的なモデルを使用しましたが、Copilot provider が credential を HTTP 401 で拒否し、最初の
エージェントターンより前に停止しました。直近の実行では、その具体的なモデルが
`agentic-workflows` integrator で利用できなくなり、HTTP 400 が返されました。

## `requested model is not available` は何を意味するか

[直近の失敗した実行](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471741529)で
判定に使用したログは次のとおりです。

```text
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
400 The requested model is not available for integrator "agentic-workflows". Available models: [... claude-sonnet-5 ...]
[copilot-harness] all 3 retries exhausted — giving up (exitCode=1)
```

workflow はコンテナ起動を通過し、具体的な ID `claude-sonnet-4.6` を Copilot CLI に渡しましたが、
最初の推論ターンより前に provider が拒否しました。同じ response の利用可能一覧には
`claude-sonnet-5` が含まれ、`claude-sonnet-4.6` は含まれていないため、この integrator に対する
設定モデルが古くなっていたと判断できます。これはエイリアス解決、token 認証、network の失敗ではありません。

## 利用できない具体的なモデルをどう修正するか

失敗した実行の `Available models` 一覧から具体的な ID を選択します。同じモデル系統を維持するため、
このリポジトリでは次の値へ更新しました。

```yaml
engine: copilot
model: claude-sonnet-5
```

次に、ソースワークフローから lock file を再生成します。

```bash
gh aw compile daily-repo-status --strict
```

`.lock.yml` は直接編集しません。生成された metadata とすべての `COPILOT_MODEL` の固定値が
新しい ID になったことを確認してから、workflow を再実行します。モデルの利用可否は integrator、
account entitlement、policy に依存し、時間とともに変わることがあります。以前の成功実績や古い compiler
catalog より、失敗した request 自体が返した一覧を優先してください。

## 以前のモデルエイリアス解決失敗はどのようなものか

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

## 以前のエイリアス解決失敗の原因は何か

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

以前の事例では、ソースワークフローで具体的なモデルを固定しました。そのモデルが後に runtime の
利用可能一覧から外れたため、現在のソースでは利用可能な同系統のモデルを使用します。

```yaml
engine: copilot
model: claude-sonnet-5
```

`claude-sonnet-4.6` は v0.88.7 のモデルメタデータに含まれ、このワークフローの audit baseline で
成功実績がありましたが、その履歴は将来の利用可否を保証しません。現在の runtime が返す一覧に含まれ、
リポジトリの Copilot subscription と policy で許可された具体的なモデルを使用してください。

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

## `copilot-requests: write` 使用時の HTTP 403 は何を意味するか

別の `Advanced Guideline Impact Report` の[失敗した実行](https://github.com/ks6088ts-labs/handson-github-actions/actions/runs/35472789759)と
その [agent job](https://github.com/ks6088ts-labs/handson-github-actions/actions/runs/35472789759/job/105976804951)には、
次のログが含まれています。

```text
S2STOKENS: true
[copilot-harness] awf-reflect: models fetch returned 403 for http://api-proxy:10002/models
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-5" endpoint=managed-by-copilot-cli
Authentication failed with provider at http://172.30.0.30:10002 (HTTP 403).
[copilot-harness] attempt 2: Copilot requests authentication failed through the gh-aw API proxy (HTTP 403, model=claude-sonnet-5, stage=starting the Copilot CLI request).
```

失敗時の commit では、[ソースワークフロー](https://github.com/ks6088ts-labs/handson-github-actions/blob/4b6ecd279f64de7d7f038ba17e813c319ec79766/.github/workflows/guideline-impact-report.md#L5-L9)が
`copilot-requests: write` を宣言していました。そのため、[生成された agent job](https://github.com/ks6088ts-labs/handson-github-actions/blob/4b6ecd279f64de7d7f038ba17e813c319ec79766/.github/workflows/guideline-impact-report.lock.yml#L365)は
`COPILOT_GITHUB_TOKEN` に `${{ github.token }}` を設定し、
[`S2STOKENS: true`](https://github.com/ks6088ts-labs/handson-github-actions/blob/4b6ecd279f64de7d7f038ba17e813c319ec79766/.github/workflows/guideline-impact-report.lock.yml#L888-L911)を有効にしていました。
gh-aw の認証リファレンスでは、`copilot-requests: write` はこの組み込み token の経路を選択し、
`COPILOT_GITHUB_TOKEN` という repository secret が存在しても推論には使用しないと規定されています。
したがって、secret の追加や更新だけでは、この実行の認証経路は変わりません。

内部の Copilot CLI は `COPILOT_PROVIDER_*` の値を確認する一般的な案内も出力しました。
この S2S 経路では、後から出力される gh-aw の診断の方が具体的です。この一般的なメッセージを理由に
provider key の repository secret を追加しないでください。

これらの signal から、最初の推論ターンより前に organization 課金の認可で失敗したと判断できます。
ただし、403 だけでは不足している管理設定を特定できません。organization に有効な Copilot subscription が
あること、Copilot CLI request の centralized billing が有効であること、生成された job にこの権限が
あることを確認します。harness は具体的なモデルを選択した後、推論前に `tokenCount=0` を記録しているため、
これはエイリアス解決や利用できないモデルの response ではありません。

## 利用できない organization 課金から PAT 認証へ切り替えるにはどうするか

organization の centralized billing を利用できず、個人または seat 課金へ切り替える場合は、
ソースワークフローでその経路を明示的に無効化します。

```yaml
permissions:
  contents: read
  copilot-requests: none
engine: copilot
model: claude-sonnet-5
```

前述の手順に従って、互換性のある fine-grained PAT を repository secret
`COPILOT_GITHUB_TOKEN` に設定し、lock ファイルを再生成します。

```bash
gh aw compile guideline-impact-report --strict
```

生成された lock ファイルで、Copilot 実行が `${{ secrets.COPILOT_GITHUB_TOKEN }}` を使用し、
`S2STOKENS: true` が設定されていないことを確認します。PAT が優先されることを期待して両方の経路を
設定しないでください。organization 管理者が centralized billing を有効にする場合は、
`copilot-requests: write` を維持し、PAT を使わず組み込み token の経路を使用します。どちらの場合も、
新しい実行で 1 回以上の推論ターンと 0 より大きい token usage が記録されて初めて復旧を確認できます。

## `awf-reflect.json` の `EACCES` warning が原因か

いいえ。harness は reflection payload を `/home/runner/work/_temp/awf-reflect.json` に保存できないことも
記録しました。この warning は診断 artifact の保存に影響しますが、実行は継続しました。最初の実行は
未解決エイリアスのメッセージ後に終了し、後続の実行は Copilot CLI まで到達して
`authentication_failed` と明示的に分類されました。直近の実行も Copilot CLI まで到達し、利用できない
モデルを示す HTTP 400 を明示的に返しました。

別の organization 課金の 403 実行でも同じ EACCES warning が出ましたが、API proxy が 403 を返した後に
reflection payload を保存する段階の warning です。provider の認可失敗を説明する原因ではありません。

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
| `requested model is not available for integrator "agentic-workflows"` | 現在の runtime entitlement または policy では設定した具体的な ID を利用できません。同時に出力された `Available models` 一覧から ID を選択します。 |
| 指定したモデルが `Available models` にない | 以前の実行や compiler catalog で受理されていても、設定した ID は古いものとして扱います。 |
| モデル関連の同じ HTTP 400 が harness の retry ごとに繰り返される | 決定的な設定エラーです。retry しても利用できないモデルは有効になりません。 |
| `COPILOT_MODEL: auto` または別のエイリアス | Copilot を起動する前に runtime catalog data が必要です。 |
| `models fetch returned 401` | 設定した credential または endpoint の認証が拒否されています。PAT 経路では `COPILOT_GITHUB_TOKEN`、permission、token owner の entitlement を確認します。 |
| `models fetch returned 403` と `S2STOKENS: true` または organization 課金の診断メッセージ | Actions token に centralized organization billing 経由の Copilot 推論権限がありません。この課金経路を有効にするか、PAT 認証へ明示的に切り替えます。 |
| `models fetch returned 429` または `503` | catalog endpoint が一時的に利用できません。現在の gh-aw は bounded retry を行います。 |
| `refusing to start Copilot with an unresolved alias` | 想定された fail-closed 動作です。未解決のエイリアスは推論に送信されません。 |
| turn と effective token がともに 0 | モデル推論より前の harness handoff で失敗しています。 |
| 具体的なモデルでも推論時に 401 | token、entitlement、または organization policy を修正する必要があり、モデルの固定だけでは解決しません。 |
| activation の secret validation が成功した後、推論が 401 | secret は存在しますが、provider が受け付けることは確認できていません。PAT の更新または診断が必要です。 |
| `COPILOT_GITHUB_TOKEN` が存在するが、workflow が `copilot-requests: write` を宣言している | repository secret は推論で無視されます。centralized billing を診断するか、workflow を `copilot-requests: none` に変更して再コンパイルします。 |

上流 Issue の当初の対象は HTTP 429 でした。今回の事例では HTTP 401 が返りましたが、上流の修正で
導入された同じ汎用的な fail-closed 経路に到達しています。

## 復旧手順は何か

1. 最終的な retry error ではなく、provider の正確なメッセージから失敗を分類します。
2. ソース、生成された lock、ログから認証経路を判定します。`copilot-requests: write` と `S2STOKENS: true` の組み合わせは organization 課金、`COPILOT_GITHUB_TOKEN: ${{ secrets.COPILOT_GITHUB_TOKEN }}` は PAT 経路です。
3. `requested model is not available` の場合は、その response の `Available models` 一覧から具体的な ID を選択します。
4. 未解決エイリアスの場合は、リポジトリの subscription で使用できる具体的な Copilot model を選択します。
5. ソースの `*.md` ワークフローに `engine: copilot` とトップレベルの `model:` を設定します。
6. 再コンパイルし、ソースワークフローと生成された `.lock.yml` の両方をコミットします。
7. リポジトリの検証後に workflow を再実行し、1 回以上の推論ターンが開始されたことを確認します。
8. PAT 経路が 401 を返す場合は、互換性のある PAT を作成し、`COPILOT_GITHUB_TOKEN` を更新して Copilot CLI で PAT を検証します。
9. organization 課金の経路が 403 を返す場合は、Copilot subscription、centralized billing、policy の前提を有効にするか、`copilot-requests: none` と PAT 経路へ明示的に切り替えます。
10. 新しい PAT でも失敗する場合は、Copilot license、model entitlement、または organization policy を修正します。

このリポジトリでは、次の順序でローカル検証します。

```bash
gh aw compile daily-repo-status --strict
make ci-test
gh aw run daily-repo-status
```

## 一次情報と出典

| 根拠 | 一次情報 |
| --- | --- |
| 具体的なモデルの利用不可エラーと現在のモデル一覧 | [Workflow run 35471741529](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471741529)と、その [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471741529/job/105973861793#step:26:211) |
| 今回のログと 401／エイリアス解決失敗 | [Workflow run 35470003900](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900)と、その [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900/job/105969169242#step:26:210) |
| 具体的なモデルに対する provider の 401 と `authentication_failed` の分類 | [Workflow run 35471231052](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052)と、その [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052/job/105972518194#step:26:210) |
| organization 課金の HTTP 403、`S2STOKENS: true`、token 0 | [Workflow run 35472789759](https://github.com/ks6088ts-labs/handson-github-actions/actions/runs/35472789759)と、その [agent job](https://github.com/ks6088ts-labs/handson-github-actions/actions/runs/35472789759/job/105976804951) |
| 失敗時の commit で選択された認証経路 | [ソースワークフロー](https://github.com/ks6088ts-labs/handson-github-actions/blob/4b6ecd279f64de7d7f038ba17e813c319ec79766/.github/workflows/guideline-impact-report.md#L5-L9)と[生成された lock ファイル](https://github.com/ks6088ts-labs/handson-github-actions/blob/4b6ecd279f64de7d7f038ba17e813c319ec79766/.github/workflows/guideline-impact-report.lock.yml#L888-L911) |
| organization 課金経路の HTTP 403 分類 | [gh-aw v0.88.7 の harness 回帰テスト](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/copilot_harness.test.cjs)と[診断テンプレート](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/md/copilot_requests_proxy_auth_403.md) |
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
