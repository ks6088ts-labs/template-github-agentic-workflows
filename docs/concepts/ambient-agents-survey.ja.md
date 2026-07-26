# ambient agent と Human-in-the-Loop: 簡易サーベイ (v1)

「ambient agent + Human-in-the-Loop (HITL)」という考え方と、GitHub Agentic Workflows (gh-aw) がそれをどのように実現するかについての初版サーベイです。ペルソナシナリオの拡充に合わせて発展させることを想定した初版です。

## 「ambient agent」とは？

**ambient agent** は、人間とターンごとに対話するのを待つのではなく、バックグラウンドで実行されイベントに反応するエージェントです。対話型のチャットアシスタントと比較すると次のようになります:

| 対話型（チャット）エージェント | ambient agent |
| --- | --- |
| 人間が毎ターンを開始する | イベントが作業を開始する（Issue、PR、スケジュール、コマンド） |
| フォアグラウンドで 1 件ずつ | バックグラウンドで、場合により多数を並行 |
| 人間が各ステップを見張る | 人間はほとんどの時間見ていない |

各ステップを誰も見ていないため、ambient agent には制御を人間に戻す明示的なポイントが必要です。

## なぜ Human-in-the-Loop なのか？

**Human-in-the-Loop** は、重要な局面（通常は提案されたアクションの *承認 / 編集 / 却下*）で人間の判断を差し込みます。これにより、自律的なエージェントを継続的に稼働させつつ、影響の大きい効果には依然として人間の判断を必須にできます。HITL こそが、ambient な自動化を稼働させ続けても安全にする要素です。

このペアリングに関する公開された議論としては、日本語では日経 COMEMO の *「AI BPO - Ambient Agent + Human in the Loop」*（<https://comemo.nikkei.com/n/n76970e72afde>）があり、ambient agent と HITL の組み合わせを間接業務自動化のモデルとして位置づけています。（テーマとして参照するものであり、仕様ではなく入り口として扱ってください。）

## gh-aw と ambient + HITL の対応

gh-aw は実質的に、HITL がアーキテクチャに組み込まれた ambient agent 実行環境です:

| ambient + HITL の概念 | gh-aw のメカニズム |
| --- | --- |
| イベントによる起動 | トリガー: `issues`、`pull_request`、`schedule`、コマンド（`/…`） |
| バックグラウンド / managed 実行 | GitHub Actions の managed ランナーで実行 |
| 制限された自律性 | 既定で読み取り専用の権限。最小権限 |
| HITL の承認ゲート | [safe-outputs](https://github.github.com/gh-aw/reference/safe-outputs/): 書き込みはバッファリングされ、チェック後にのみ適用。人間が結果をレビュー |
| 信頼できない入力への信頼付与 | コンテンツのサニタイズ + integrity filtering |
| 侵害に対するガードレール | 脅威検知、シークレットの秘匿、ネットワーク許可リスト |
| 監査可能性 | `gh aw logs` / `gh aw audit` |

各メカニズムの詳細は[実行アーキテクチャ](execution-architecture.ja.md)を参照してください。

## 本リポジトリのシナリオの位置づけ

- [PR レビュー補助](../use-cases/dev-productivity/pr-review-helper.ja.md) — `pull_request` による **イベント起動**。エージェントはコメントするだけで人間が対応を判断するため **HITL**。
- [定期ステータスレポート](../use-cases/infra-ops/status-report.ja.md) — 日次 `schedule` による **イベント起動**。チームがレポート Issue をレビューしてトリアージするため **HITL**。

いずれもエージェントを読み取り専用に保ち、すべての効果を safe-output（HITL ゲート）経由にしています。

## 未解決の論点と次のステップ

- **より強力な承認フロー（IssueOps）**。特定の人物に限定した、コマンドトリガーの申請・承認フローは自然な次の一歩であり、③ 社内間接業務ペルソナで予定しています。gh-aw の [IssueOps パターン](https://github.github.com/gh-aw/patterns/issue-ops/)を参照してください。
- **ステージング / ドラフト出力**。明示的な「提案してから適用」のレビュー手順として [staged-mode safe-outputs](https://github.github.com/gh-aw/reference/staged-mode/) を検討します。
- **マルチエンジン比較**。このサーベイは Copilot エンジンを前提としています。Claude / Codex / Gemini の挙動比較は今後の課題です。

## 参考リンク

- 日経 COMEMO『AI BPO - Ambient Agent + Human in the Loop』: <https://comemo.nikkei.com/n/n76970e72afde>
- gh-aw [Security Architecture](https://github.github.com/gh-aw/introduction/architecture/)
- gh-aw [Safe Outputs](https://github.github.com/gh-aw/reference/safe-outputs/) · [IssueOps パターン](https://github.github.com/gh-aw/patterns/issue-ops/)
- [実行アーキテクチャ（本リポジトリ）](execution-architecture.ja.md)
