# Periodic status report

> Persona: ② IT infra operator · Follows the [scenario template](../TEMPLATE.md).

## 1. Background & problem

Operators and team leads need a regular pulse on a repository — what merged, what is
stuck, what needs attention — but assembling that summary by hand every day is tedious
and easy to skip. When the summary lapses, problems surface late.

## 2. Automation goal

Once a day, an agent reviews recent repository activity and files a concise status
report as a GitHub issue, replacing the previous day's report so the tracker stays clean.

## 3. Design: trigger / permissions / safe-outputs

| Aspect | Choice | Why |
| --- | --- | --- |
| Trigger (`on:`) | `schedule: daily` | Recurring, unattended cadence |
| Permissions | `contents: read`, `issues: read`, `pull-requests: read` | Read-only — enough to assess activity |
| Safe-outputs | `create-issue` (`close-older-issues: true`) | One rolling report; scoped write path |
| Engine | `copilot` | Repository default |

`close-older-issues` keeps a single current report instead of accumulating a new issue
every day — a small but important noise/cost control.

## 4. Working workflow

This scenario reuses the repository's existing sample:

- Workflow: [`.github/workflows/daily-repo-status.md`](../../../.github/workflows/daily-repo-status.md)
- Compiled: [`.github/workflows/daily-repo-status.lock.yml`](../../../.github/workflows/daily-repo-status.lock.yml)

Run it on demand:

```bash
make run WORKFLOW=daily-repo-status
```

## 5. Human-in-the-Loop

The report lands as a GitHub issue, where the team reviews it and decides what to act
on. The agent summarizes and proposes; it does not change code, close work items, or
take operational action. Humans triage from the issue.

## 6. Cost & security notes

- **Cost**: a daily schedule is predictable and cheap — one run per day regardless of
  repository traffic. This scheduled, event-driven model keeps agent spend bounded. See
  [execution architecture → event-driven cost](../../concepts/execution-architecture.md#event-driven-execution-optimizes-cost).
- **Least privilege**: read-only permissions; the only write is the report issue.
- **Noise control**: `close-older-issues` prevents issue pile-up.

## 7. Extensions

- Add `workflow_dispatch` inputs to vary the reporting window.
- Post to a discussion or a pull request comment instead of an issue.
- Extend toward fault triage: summarize failed CI runs (`workflow_run`) and open an
  issue only when something breaks.

← Back to [② IT infra operator](README.md) · [Use cases](../README.md)
