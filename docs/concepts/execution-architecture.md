# Execution architecture: managed runtime, cost, and security

This page explains *where* and *how* agentic workflows run, and why that model lowers
operational cost and raises the security floor. It summarizes the official
[gh-aw Security Architecture](https://github.github.com/gh-aw/introduction/architecture/)
and [Overview](https://github.github.com/gh-aw/introduction/overview/) and connects them
to this repository's workflows and `make` targets.

## The model in one paragraph

You write a workflow as Markdown with YAML frontmatter. `gh aw compile` turns it into a
hardened GitHub Actions workflow (`*.lock.yml`) that runs an AI coding agent inside a
containerized, managed runner whenever a trigger fires. Workflows are **read-only by
default**; every write goes through sanitized [safe-outputs](https://github.github.com/gh-aw/reference/safe-outputs/).

## Managed execution lowers operational cost

- **No infrastructure to run.** Workflows execute on GitHub Actions managed runners.
  There is no server, queue, or agent host to provision, patch, or scale.
- **Reproducible builds.** The committed `*.lock.yml` is generated from the Markdown, so
  what runs is exactly what was reviewed. Regenerate with `make compile`.
- **Secrets stay in the platform.** Credentials are provided as GitHub Actions secrets
  (for example `COPILOT_GITHUB_TOKEN`) and are redacted from logs and artifacts.
- **Built-in observability.** `gh aw logs` and `gh aw audit` expose prompts, outputs,
  patches, token usage, and network activity for debugging, security review, and cost
  monitoring — no separate telemetry stack required.

## Event-driven execution optimizes cost

Agentic workflows run **only when an event occurs**, not continuously:

- **Triggers bound the spend.** An `issues`, `pull_request`, `schedule`, or command
  trigger runs the agent only on that event. A daily schedule costs one run per day
  regardless of repository traffic (see the
  [periodic status report](../use-cases/infra-ops/status-report.md)).
- **Narrow the trigger to control cost.** High-frequency triggers such as
  `pull_request` on every push can be scoped with `paths:` filters or replaced with an
  on-demand command (`/review`) — see the
  [PR review helper](../use-cases/dev-productivity/pr-review-helper.md).
- **Usage is measurable.** Token usage per run is tracked via `gh aw logs`, so cost is an
  observable quantity rather than a guess.

## Security architecture (defense in depth)

gh-aw layers independent controls so that a failure in one layer is contained by the
others. The layers below are summarized from the official Security Architecture.

### Read-only agent + Safe Outputs isolation

The agent job runs with **read-only** permissions and never writes to external state
directly. Write operations (create issue, add comment, create PR) are **buffered as
artifacts** and applied by separate, minimally-scoped jobs that run only after the agent
finishes. Even a fully compromised agent cannot modify repository state on its own.

### Compilation-time hardening

`gh aw compile` validates frontmatter against a schema, pins actions to SHAs, checks
expression safety, and runs security scanners (**actionlint, zizmor, poutine**). In this
repository that hardening is exercised by `make ci-test`, which runs `gh aw validate`
(compile + scanners) and `gh aw lint`.

### Content sanitization & integrity filtering

Untrusted event text (issue/PR titles, bodies, comments) is sanitized before the agent
sees it: `@mentions` and bot triggers are neutralized, HTML/XML tags are defanged, URLs
are restricted to trusted HTTPS domains, and content is size-limited. For public
repositories, integrity filtering (`min-integrity: approved`) restricts context to
trusted authors automatically.

### Network egress control (Agent Workflow Firewall)

The agent runs behind a firewall that routes all traffic through a proxy enforcing a
domain **allowlist** (`network:` configuration). This limits data exfiltration and
restricts a compromised agent to permitted domains.

### Threat detection & secret redaction

Before any write is externalized, a separate detection job inspects the buffered outputs
and patches for secret leaks and malicious patterns, and can block the run. Independently,
all artifacts are scanned and secret values are redacted (masked) before upload — with
`if: always()`, so secrets are protected even on failure.

## How this repository applies it

Both workflows follow the same safe pattern:

| Workflow | Permissions | Safe-output | Human-in-the-Loop |
| --- | --- | --- | --- |
| [`pr-review-helper.md`](../../.github/workflows/pr-review-helper.md) | read-only | `add-comment` | reviewer acts on the comment |
| [`daily-repo-status.md`](../../.github/workflows/daily-repo-status.md) | read-only | `create-issue` | team triages the report issue |

Validate the whole set at any time:

```bash
make compile
make ci-test
```

## References

- [Security Architecture](https://github.github.com/gh-aw/introduction/architecture/)
- [About Workflows (Overview)](https://github.github.com/gh-aw/introduction/overview/)
- [Safe Outputs reference](https://github.github.com/gh-aw/reference/safe-outputs/)
- [Network permissions](https://github.github.com/gh-aw/reference/network/)
- [Ambient agents and Human-in-the-Loop: a short survey](ambient-agents-survey.md)
- [Workflow format and the compile pipeline](compilation-and-format.md)
- [External integrations: Azure and external APIs](external-integrations.md)
