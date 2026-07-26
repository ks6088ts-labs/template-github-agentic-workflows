[![test](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/workflows/test.yaml/badge.svg)](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/workflows/test.yaml)

# template-github-agentic-workflows

GitHub Agentic Workflows のための厳選されたテンプレート集です。

## 前提条件

このリポジトリは **Windows、macOS、Linux** を対象とし、すべての操作のタスクランナーとして **GNU Make** を使用します。

- **オペレーティングシステム**: Windows (WSL2) / macOS / Linux。Windows では **WSL2 (Ubuntu)** 内で作業してください。`Makefile` は Unix ツール（`grep`、`awk`、`sed` など）に依存しており、ネイティブの PowerShell やコマンドプロンプトでは動作しません。
- **GNU Make**: このリポジトリのタスクランナーです。利用可能なすべてのターゲットを一覧するには `make help` を実行します。
- **GitHub CLI (`gh`) v2.0.0 以降**: 認証、`gh-aw` 拡張機能のインストール、ワークフローの実行に必要です。
- **AI アカウント**: デフォルトでは GitHub Copilot（または Anthropic Claude / OpenAI Codex / Google Gemini）。
- 書き込み権限があり、**GitHub Actions が有効** になっている **GitHub リポジトリ**。

### `gh` と `make` のインストール

**Windows (WSL2)** — 管理者権限の PowerShell から WSL をインストールし、その後 Ubuntu 内で Linux の手順を実行します:

```powershell
wsl --install
```

**macOS** — [Homebrew](https://brew.sh/) を使用:

```bash
brew install gh make
```

**Linux (Debian / Ubuntu)**:

```bash
sudo apt update && sudo apt install -y make gh
```

両方のツールが利用可能であることを確認します:

```bash
gh --version
make --version
```

## チュートリアル

前提条件が整ったら、ステップバイステップのチュートリアルに従って、最初のワークフローの作成・検証・実行を行いましょう:

1. **[はじめに](docs/tutorials/01_getting-started.ja.md)**

## 参考リンク

- [はじめてのエージェントワークフロー（クイックスタート）](https://docs.github.com/en/copilot/how-tos/github-agentic-workflows/quickstart)
- [GitHub Agentic Workflows ドキュメントサイト](https://github.github.com/gh-aw/)
- [GitHub CLI のインストール](https://github.com/cli/cli#installation)
