# 実行アーキテクチャ: managed 実行環境・コスト・セキュリティ

このページでは、エージェントワークフローが *どこで* *どのように* 実行されるのか、そしてなぜそのモデルが運用コストを下げ、セキュリティの下限を引き上げるのかを説明します。公式の [gh-aw セキュリティアーキテクチャ](https://github.github.com/gh-aw/introduction/architecture/) と [概要](https://github.github.com/gh-aw/introduction/overview/) を要約し、本リポジトリのワークフローと `make` ターゲットに結びつけます。

## ひと段落での全体像

ワークフローは YAML フロントマター付きの Markdown として記述します。`gh aw compile` がそれを堅牢化された GitHub Actions ワークフロー（`*.lock.yml`）に変換し、トリガー発火時に managed ランナー上のコンテナ内で AI コーディングエージェントを実行します。ワークフローは **既定で読み取り専用** であり、すべての書き込みはサニタイズされた [safe-outputs](https://github.github.com/gh-aw/reference/safe-outputs/) を経由します。

## managed 実行が運用コストを下げる

- **運用するインフラが不要**。ワークフローは GitHub Actions の managed ランナーで実行されます。プロビジョニング・パッチ適用・スケーリングを行うサーバー、キュー、エージェントホストはありません。
- **再現可能なビルド**。コミットされた `*.lock.yml` は Markdown から生成されるため、実行されるものはレビューされたものと完全に一致します。`make compile` で再生成します。
- **シークレットはプラットフォーム内に留まる**。認証情報は GitHub Actions のシークレット（例: `COPILOT_GITHUB_TOKEN`）として提供され、ログやアーティファクトからは秘匿（redact）されます。
- **組み込みの可観測性**。`gh aw logs` と `gh aw audit` が、プロンプト・出力・パッチ・トークン使用量・ネットワーク活動を公開し、デバッグ・セキュリティレビュー・コスト監視に使えます。別途のテレメトリ基盤は不要です。

## イベント駆動実行がコストを最適化する

エージェントワークフローは常時稼働ではなく、**イベント発生時のみ** 実行されます:

- **トリガーが費用を規定する**。`issues`、`pull_request`、`schedule`、コマンドの各トリガーは、そのイベント時にのみエージェントを実行します。日次スケジュールはリポジトリのトラフィックに関係なく 1 日 1 実行です（[定期ステータスレポート](../use-cases/infra-ops/status-report.ja.md)を参照）。
- **コスト制御はトリガーを絞る**。push ごとの `pull_request` のような高頻度トリガーは、`paths:` フィルターで絞るか、オンデマンドのコマンド（`/review`）に置き換えられます（[PR レビュー補助](../use-cases/dev-productivity/pr-review-helper.ja.md)を参照）。
- **使用量は計測可能**。実行ごとのトークン使用量は `gh aw logs` で追跡でき、コストは推測ではなく観測可能な量になります。

## セキュリティアーキテクチャ（多層防御）

gh-aw は独立した制御を積み重ね、1 つの層の失敗を他の層が封じ込めます。以下の層は公式のセキュリティアーキテクチャからの要約です。

### 読み取り専用エージェント + Safe Outputs による分離

エージェントのジョブは **読み取り専用** の権限で実行され、外部状態に直接書き込むことはありません。書き込み操作（Issue 作成、コメント追加、PR 作成）は **アーティファクトとしてバッファリング** され、エージェント完了後に実行される、権限を最小限に絞った別ジョブが適用します。完全に侵害されたエージェントであっても、単独でリポジトリの状態を変更することはできません。

### コンパイル時の堅牢化

`gh aw compile` はフロントマターをスキーマ検証し、アクションを SHA でピン留めし、式の安全性をチェックし、セキュリティスキャナー（**actionlint、zizmor、poutine**）を実行します。本リポジトリでは、この堅牢化を `make ci-test` が実行し、`gh aw validate`（コンパイル + スキャナー）と `gh aw lint` を走らせます。

### コンテンツのサニタイズ & integrity filtering

信頼できないイベントテキスト（Issue/PR のタイトル・本文・コメント）は、エージェントが見る前にサニタイズされます。`@メンション` やボットトリガーは無害化され、HTML/XML タグは解除され、URL は信頼された HTTPS ドメインに制限され、コンテンツはサイズ制限されます。パブリックリポジトリでは、integrity filtering（`min-integrity: approved`）が信頼できる作成者にコンテキストを自動的に制限します。

### ネットワーク下り制御（Agent Workflow Firewall）

エージェントはファイアウォールの背後で実行され、すべてのトラフィックはドメイン **許可リスト**（`network:` 設定）を強制するプロキシを経由します。これによりデータの持ち出しを制限し、侵害されたエージェントを許可ドメインに限定します。

### 脅威検知 & シークレットの秘匿

いかなる書き込みも外部化される前に、別の検知ジョブがバッファリングされた出力とパッチをシークレット漏洩や悪意あるパターンについて検査し、実行をブロックできます。独立して、すべてのアーティファクトはスキャンされ、シークレット値はアップロード前に秘匿（マスク）されます。`if: always()` 付きのため、失敗時でもシークレットは保護されます。

## 本リポジトリでの適用

両ワークフローは同じ安全なパターンに従います:

| ワークフロー | 権限 | safe-output | Human-in-the-Loop |
| --- | --- | --- | --- |
| [`pr-review-helper.md`](../../.github/workflows/pr-review-helper.md) | 読み取り専用 | `add-comment` | レビュアーがコメントに対応 |
| [`daily-repo-status.md`](../../.github/workflows/daily-repo-status.md) | 読み取り専用 | `create-issue` | チームがレポート Issue をトリアージ |

いつでも一式を検証できます:

```bash
make compile
make ci-test
```

## 参考リンク

- [Security Architecture](https://github.github.com/gh-aw/introduction/architecture/)
- [About Workflows（概要）](https://github.github.com/gh-aw/introduction/overview/)
- [Safe Outputs リファレンス](https://github.github.com/gh-aw/reference/safe-outputs/)
- [Network permissions](https://github.github.com/gh-aw/reference/network/)
- [ambient agent と Human-in-the-Loop: 簡易サーベイ](ambient-agents-survey.ja.md)
- [ワークフローのフォーマットとコンパイルパイプライン](compilation-and-format.ja.md)
- [外部連携: Azure・外部 API](external-integrations.ja.md)
