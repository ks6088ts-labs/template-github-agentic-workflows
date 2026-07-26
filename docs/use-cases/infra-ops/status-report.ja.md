# 定期ステータスレポート

> ペルソナ: ② IT インフラ運用者 · [シナリオテンプレート](../TEMPLATE.ja.md)に従います。

## 1. 背景・課題

運用担当者やチームリードは、リポジトリの動き（何がマージされ、何が滞り、何に注意が必要か）を定期的に把握する必要があります。しかし、その要約を毎日手作業で組み立てるのは退屈で、つい省略しがちです。要約が途絶えると、問題の表面化が遅れます。

## 2. 自動化ゴール

1 日 1 回、エージェントが最近のリポジトリ活動をレビューし、簡潔なステータスレポートを GitHub Issue として起票します。前日のレポートは置き換えられ、トラッカーは整理された状態に保たれます。

## 3. 設計: トリガー・permissions・safe-outputs

| 項目 | 選択 | 理由 |
| --- | --- | --- |
| トリガー (`on:`) | `schedule: daily` | 定期的・無人のリズム |
| 権限 (permissions) | `contents: read`、`issues: read`、`pull-requests: read` | 読み取り専用 — 活動を評価するのに十分 |
| safe-outputs | `create-issue`（`close-older-issues: true`） | ローリングする 1 件のレポート。スコープを絞った書き込み経路 |
| エンジン | `copilot` | リポジトリの既定 |

`close-older-issues` は、毎日新しい Issue を積み上げるのではなく、常に 1 件の最新レポートを保ちます。小さいながらも重要なノイズ・コスト対策です。

## 4. 動作ワークフロー

このシナリオはリポジトリ既存のサンプルを再利用します:

- ワークフロー: [`.github/workflows/daily-repo-status.md`](../../../.github/workflows/daily-repo-status.md)
- コンパイル済み: [`.github/workflows/daily-repo-status.lock.yml`](../../../.github/workflows/daily-repo-status.lock.yml)

オンデマンドで実行します:

```bash
make run WORKFLOW=daily-repo-status
```

## 5. Human-in-the-Loop（承認点）

レポートは GitHub Issue として起票され、チームがそれをレビューして対応を判断します。エージェントは要約と提案を行うだけで、コードの変更・作業項目のクローズ・運用アクションは行いません。人間が Issue からトリアージします。

## 6. コスト・セキュリティ注意

- **コスト**: 日次スケジュールは予測可能で低コストです。リポジトリのトラフィックに関係なく 1 日 1 実行です。このスケジュール型・イベント駆動のモデルがエージェントの費用を抑えます。[実行アーキテクチャ → イベント駆動のコスト](../../concepts/execution-architecture.ja.md)を参照してください。
- **最小権限**: 読み取り専用の権限で、書き込みはレポート Issue のみです。
- **ノイズ対策**: `close-older-issues` が Issue の積み上がりを防ぎます。

## 7. 発展

- `workflow_dispatch` の入力を追加し、レポート対象期間を変える。
- Issue の代わりにディスカッションやプルリクエストのコメントに投稿する。
- 障害トリアージへ発展させる: 失敗した CI 実行（`workflow_run`）を要約し、問題が起きたときだけ Issue を起票する。

← [② IT インフラ運用者](README.ja.md)に戻る · [ユースケース](../README.ja.md)
