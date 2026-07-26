# ② IT インフラ運用者

手作業のレポート作成なしに運用担当者へ情報を届けるエージェントワークフローです。定期的なステータス要約、障害トリアージ、依存更新の追従を扱います。

## シナリオ

| シナリオ | トリガー | safe-output | ワークフロー |
| --- | --- | --- | --- |
| [定期ステータスレポート](status-report.ja.md) | `schedule`（日次） | `create-issue` | [daily-repo-status.md](../../../.github/workflows/daily-repo-status.md) |

さらなるシナリオ（障害トリアージ要約、依存更新の追従）は今後の反復で追加予定です。

← [ユースケース](../README.ja.md)に戻る
