[![test](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/workflows/test.yaml/badge.svg)](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/workflows/test.yaml)

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

## Tutorials

Once the prerequisites are in place, follow the step-by-step tutorials to author, validate, and run your first workflow:

1. **[Getting started](docs/tutorials/01_getting-started.md)**

## Use cases

Persona-based scenarios, each linked to a working workflow — see the [use-case index](docs/use-cases/README.md):

- ① Software developer — [PR review helper](docs/use-cases/dev-productivity/pr-review-helper.md)
- ② IT infra operator — [Periodic status report](docs/use-cases/infra-ops/status-report.md)

## Concepts

- [Execution architecture: managed runtime, cost, and security](docs/concepts/execution-architecture.md)
- [Ambient agents and Human-in-the-Loop: a short survey](docs/concepts/ambient-agents-survey.md)
- [Workflow format and the compile pipeline](docs/concepts/compilation-and-format.md)
- [External integrations: Azure and external APIs](docs/concepts/external-integrations.md)

## References

- [Your first agentic workflow (Quickstart)](https://docs.github.com/en/copilot/how-tos/github-agentic-workflows/quickstart)
- [GitHub Agentic Workflows documentation site](https://github.github.com/gh-aw/)
- [GitHub CLI installation](https://github.com/cli/cli#installation)
