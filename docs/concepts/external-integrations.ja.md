# 外部連携: Azure・外部 API

ワークフローを Azure やその他の外部 API に接続する方法と、LLM が生の秘密を見ないように
クレデンシャルがどう流れるか。公式の
[Custom Steps and Jobs](https://github.github.com/gh-aw/reference/steps-jobs/)、
[Using MCPs](https://github.github.com/gh-aw/guides/mcps/)、
[Network Configuration](https://github.github.com/gh-aw/guides/network-configuration/)
を要約したものです（[出典](#出典)参照）。

## 原則: 経路は「誰が使うか」で決まる

gh-aw は **LLM に生のクレデンシャルを見せない**設計です。経路は、その資格情報を*誰が*使うかで
2 系統に分かれます:

| 使う主体 | 経路 | サンドボックス | 秘密の扱い |
| --- | --- | --- | --- |
| **決定論ステップ/ジョブ**（通常の Actions ステップ） | `pre-steps:` / `steps:` / `post-steps:` / `jobs:` | ファイアウォール**外**・標準 Actions セキュリティ | `${{ secrets.* }}` を直接使用。LLM は見ない |
| **エージェント（LLM）がツール経由で使う** | **MCP サーバ**への注入（`env` / `headers` / `auth`） | サンドボックス内 | ゲートウェイが保持・転送。プロンプトに生値は載らない |

カスタムステップ／ジョブはファイアウォールサンドボックスの**外**で標準の Actions セキュリティで
動くため、**Azure リソースを実際に操作するなら決定論ステップで `azure/login`** するのが素直です。

> **落とし穴**: ワークフローレベルの `env:` に `${{ secrets.* }}` を書かないこと。エージェント
> コンテナに渡り、秘密がモデルから見えます（**strict モードでコンパイルエラー**）。
> [ワークフローのフォーマット](compilation-and-format.ja.md)参照。

## クレデンシャルの連携手段

1. **`secrets:` フロントマター** — 渡す秘密を宣言。必ず `${{ secrets.NAME }}`（平文禁止）。
2. **MCP サーバへの注入**（エージェントが使う場合）:
   - ローカル(Docker) MCP → `env:` に `${{ secrets.* }}`
   - HTTP MCP → `headers:` に `Authorization: Bearer ${{ secrets.* }}`、または `auth: { type: github-oidc }` で短命 JWT を自動取得
3. **決定論ステップ/ジョブ**（エージェント外で使う場合）→ step の `env:` / `with:` に `${{ secrets.* }}`、または `azure/login` の OIDC。
4. **ネットワーク許可** — 認証が通っても、エージェント通信はファイアウォールを通るため、宛先ドメインを `network.allowed` で許可。

## ネットワーク許可（firewall）

strict モード（既定）は**エコシステム識別子**（`defaults`、`python`、`node`、`go`、
`containers`、`terraform`、`playwright`、`github` など）のみ受け付けます。**任意ドメイン**
（Azure エンドポイント等）は `strict: false` にして明示します。必要ドメインは
`gh aw logs --run-id <id>` のファイアウォール拒否ログから拾うのが確実です。`network: {}` は
外部通信を全遮断します（エンジン通信は許可）。

## パターン集

### 1. 外部 API — API キーを HTTP MCP のヘッダに注入

```yaml
---
on: issues
permissions:
  contents: read
mcp-servers:
  authenticated-api:
    url: "https://api.example.com/mcp"
    headers:
      Authorization: "Bearer ${{ secrets.API_TOKEN }}"
    allowed: ["*"]
---
```

### 2. 外部 API — GitHub OIDC で短命トークン（静的キー不要）

```yaml
---
permissions:
  id-token: write   # OIDC トークン取得に必須
mcp-servers:
  my-secure-server:
    url: "https://my-server.example.com/mcp"
    auth:
      type: github-oidc
      audience: "https://my-server.example.com"  # 省略時は URL
    allowed: ["*"]
---
```

ゲートウェイが GitHub Actions OIDC エンドポイントから JWT を取得し、各リクエストに
`Authorization: Bearer` として注入します（検証はサーバ側の責務。`auth.type: github-oidc`
は HTTP サーバ限定）。

### 3. ローカル(Docker) MCP — 秘密を env 注入 ＋ 通信先を許可

```yaml
---
mcp-servers:
  custom-tool:
    container: "mcp/custom-tool:v1.0"
    env:
      API_KEY: "${{ secrets.API_KEY }}"
    allowed: ["tool1", "tool2"]
    network:
      allowed:
        - defaults
        - api.example.com
---
```

### 4. Azure リソースを操作（推奨: 決定論ステップ＋OIDC）

エージェントに秘密を渡さず、通常の Actions ステップで `azure/login`（フェデレーション資格
情報）してから、*結果*（ファイル／ジョブ出力）をエージェントに渡します。

```yaml
---
on: workflow_dispatch
permissions:
  id-token: write     # Azure OIDC フェデレーションに必須
  contents: read
steps:
  - name: Azure login (OIDC / federated credential)
    uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  - name: Pull Azure data for the agent
    run: az account show -o json > /tmp/gh-aw/azure-context.json
---
# 本文
/tmp/gh-aw/azure-context.json を読み、コスト最適化の提案をまとめて…
```

> クレデンシャル／トークンは**エージェントに直接渡さない**。データをファイルや
> `jobs.<id>.outputs` に落とし、本文から `${{ needs.<job>.outputs.* }}` で参照します。
> **書き込み系**は決定論側（`az` CLI・safe-outputs）に置き、MCP サーバは read-only にします。

### 5. カスタムジョブの出力をエージェントへ渡す

```yaml
---
jobs:
  release:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.get.outputs.version }}
    steps:
      - id: get
        run: echo "version=${{ github.event.release.tag_name }}" >> $GITHUB_OUTPUT
---
リリース ${{ needs.release.outputs.version }} のハイライトを生成して…
```

### 6. カスタムドメインの許可（Azure 等）

```yaml
---
strict: false        # カスタムドメイン許可に必要
network:
  allowed:
    - defaults
    - "management.azure.com"
    - "*.vault.azure.net"
    - "login.microsoftonline.com"
---
```

## 既製の Microsoft / Azure MCP

gh-aw には共有 MCP 設定（`.github/workflows/shared/mcp/*.md`）があり、Azure・Microsoft Docs・
Fabric RTI などが含まれます。Microsoft Docs MCP はそのまま記述できます:

```yaml
mcp-servers:
  microsoftdocs:
    url: "https://learn.microsoft.com/api/mcp"
    allowed: ["*"]
```

Azure MCP は `gh aw mcp add`（レジストリから）または `shared/mcp/azure.md` の import で追加します。

## 推奨アーキテクチャ

- **読み取り** → エージェントに MCP ツールで持たせる（`env` / `headers` / `auth: github-oidc`、`network.allowed` で宛先許可）。
- **書き込み・Azure リソース操作** → 決定論ステップ/ジョブで `azure/login`（OIDC フェデレーション）。秘密は LLM に渡さず結果だけを渡す。
- **秘密**は `secrets:` ＋ MCP/ステップ経由のみ。ワークフローレベル `env:` に `secrets.*` は書かない。
- Azure は**保存シークレットレスの OIDC フェデレーション資格情報**を第一候補に。

## 出典

- [Custom Steps and Jobs](https://github.github.com/gh-aw/reference/steps-jobs/)
- [Using MCPs](https://github.github.com/gh-aw/guides/mcps/)
- [Network Configuration](https://github.github.com/gh-aw/guides/network-configuration/)
- [Frontmatter](https://github.github.com/gh-aw/reference/frontmatter/)
