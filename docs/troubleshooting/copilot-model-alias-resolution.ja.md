# FAQ: Copilot のモデルエイリアス解決が起動前に失敗する

この FAQ は、2026 年 9 月 19 日に発生した `daily-repo-status` の失敗について、調査結果を
記録したものです。モデルカタログのエラーと未解決モデルエイリアスのエラーが同時に発生し、
最初のエージェントターンより前に GitHub Agentic Workflow が停止する場合に該当します。

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

## モデルの固定に成功すれば token は有効か

いいえ。具体的なモデルの固定によって、エイリアス解決時の catalog lookup は不要になりますが、
推論時の認証は迂回しません。失敗した実行では activation の secret check が成功していましたが、
モデル一覧 endpoint は 401 を返しました。

再実行で Copilot まで到達した後、推論も 401 を返す場合は、`COPILOT_GITHUB_TOKEN` が存在し、
期限内で、選択したモデルを使用する権限を持つことを確認します。必要に応じて secret を再登録します。

```bash
make set-secret-github-copilot-token
```

Copilot の centralized billing を使用できる organization では、文書化された権限を宣言して再コンパイルし、
組み込みの GitHub Actions token を使用する方法もあります。

```yaml
permissions:
  contents: read
  copilot-requests: write
```

この方法は、organization の Copilot policy で Copilot CLI request が有効な場合に限り使用できます。

## `awf-reflect.json` の `EACCES` warning が原因か

いいえ。harness は reflection payload を `/home/runner/work/_temp/awf-reflect.json` に保存できないことも
記録しました。この warning は診断 artifact の保存に影響しますが、実行は bounded catalog refresh まで
継続しました。明示的な終了は、未解決エイリアスのメッセージの後に発生しています。

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

上流 Issue の当初の対象は HTTP 429 でした。今回の事例では HTTP 401 が返りましたが、上流の修正で
導入された同じ汎用的な fail-closed 経路に到達しています。

## 復旧手順は何か

1. リポジトリの subscription で使用できる具体的な Copilot model を選択します。
2. ソースの `*.md` ワークフローに `engine: copilot` とトップレベルの `model:` を設定します。
3. 再コンパイルし、ソースワークフローと生成された `.lock.yml` の両方をコミットします。
4. リポジトリの検証を実行してから、ワークフローを再実行します。
5. 再実行を audit し、1 回以上の推論ターンが開始されたことを確認します。
6. 推論自体が 401 を返す場合は、Copilot credential または organization policy を修正します。

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
| エイリアスキーは catalog が必要で、具体的な ID はエイリアス解決を迂回する | [gh-aw v0.88.7 の `resolve_model_alias.cjs`](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.cjs) |
| 1 回の bounded refresh 後に fail-closed で終了する | [gh-aw v0.88.7 の `copilot_harness.cjs`](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/copilot_harness.cjs) |
| 空の catalog と具体的なモデルに対する回帰テスト | [gh-aw v0.88.7 の `resolve_model_alias.test.cjs`](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.test.cjs) |
| 当初の catalog 障害報告と設計根拠 | [github/gh-aw Issue #52782](https://github.com/github/gh-aw/issues/52782) |
| bounded retry と未解決エイリアス拒否の実装 | [github/gh-aw Pull Request #53456](https://github.com/github/gh-aw/pull/53456) |
| 今回使用した compiler／runtime version | [gh-aw v0.88.7 release](https://github.com/github/gh-aw/releases/tag/v0.88.7) |
| 対応する engine／model の設定 | [AI Engines reference](https://github.github.com/gh-aw/reference/engines/) |
| PAT と `copilot-requests: write` の認証経路 | [Billing reference](https://github.github.com/gh-aw/reference/billing/)と[Authentication reference](https://github.github.com/gh-aw/reference/auth/) |
