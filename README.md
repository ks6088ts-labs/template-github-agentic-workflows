[![test](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/workflows/test.yaml/badge.svg?branch=main)](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/workflows/test.yaml?query=branch%3Amain)

# template-github-agentic-workflows

A curated collection of templates for GitHub Agentic Workflows.

## Prerequisites

This repository targets **Windows, macOS, and Linux**, and uses **GNU Make** as the task runner for every operation.

- **Operating system**: Windows (WSL2) / macOS / Linux. On Windows, work inside **WSL2 (Ubuntu)** — the `Makefile` relies on Unix tools (`grep`, `awk`, `sed`, ...) and does not run in native PowerShell or Command Prompt.
- **GNU Make**: the task runner for this repository. Run `make help` to list every available target.
- **GitHub CLI (`gh`) v2.0.0 or later**: required for authentication, installing the `gh-aw` extension, and running workflows.
- **An AI account**: GitHub Copilot by default (or Anthropic Claude / OpenAI Codex / Google Gemini).
- **A GitHub repository** with write access and **GitHub Actions enabled**.

### Install `gh` and `make`

**Windows (WSL2)** — install WSL from an elevated PowerShell, then run the Linux steps inside Ubuntu:

```powershell
wsl --install
```

**macOS** — via [Homebrew](https://brew.sh/):

```bash
brew install gh make
```

**Linux (Debian / Ubuntu)**:

```bash
sudo apt update && sudo apt install -y make gh
```

Verify both tools are available:

```bash
gh --version
make --version
```

## Getting Started

Once the prerequisites are in place, follow the step-by-step guide to author, validate, and run your first workflow:

- **[Getting started guide](docs/getting-started.md)**

## References

- [Your first agentic workflow (Quickstart)](https://docs.github.com/en/copilot/how-tos/github-agentic-workflows/quickstart)
- [GitHub Agentic Workflows documentation site](https://github.github.com/gh-aw/)
- [GitHub CLI installation](https://github.com/cli/cli#installation)
