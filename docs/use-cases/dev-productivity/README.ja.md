# ① ソフトウェア開発者

日々の開発ループの手間を減らすエージェントワークフローです。プルリクエストのレビュー、Issue のトリアージと整形、リリースノートの下書きなどを扱います。

## シナリオ

| シナリオ | トリガー | safe-output | ワークフロー |
| --- | --- | --- | --- |
| [PR レビュー補助](pr-review-helper.ja.md) | `pull_request` | `add-comment` | [pr-review-helper.md](../../../.github/workflows/pr-review-helper.md) |

さらなるシナリオ（Issue トリアージ・整形、リリースノート生成）は今後の反復で追加予定です。

← [ユースケース](../README.ja.md)に戻る
