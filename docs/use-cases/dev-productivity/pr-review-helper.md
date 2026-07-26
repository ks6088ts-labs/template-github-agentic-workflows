# PR review helper

> Persona: ① Software developer · Follows the [scenario template](../TEMPLATE.md).

## 1. Background & problem

Every pull request needs a first read: does it do what it claims, are there obvious
bugs or security issues, is it tested, does it follow the team's conventions? On a
busy repository that first pass is a bottleneck — reviewers are interrupted, and
small issues slip through while a PR waits for attention.

## 2. Automation goal

When a pull request is opened or updated, an agent posts a single, structured review
comment that summarizes the change and lists the most important findings. The comment
gives a human reviewer a running start; it never merges or approves on its own.

## 3. Design: trigger / permissions / safe-outputs

| Aspect | Choice | Why |
| --- | --- | --- |
| Trigger (`on:`) | `pull_request` (`opened`, `synchronize`, `reopened`) | React to new and updated PRs automatically |
| Permissions | `contents: read`, `pull-requests: read` | Least privilege — the agent only reads the diff |
| Safe-outputs | `add-comment` (`max: 1`) | The single sanitized write path — one comment per run |
| Engine | `copilot` | Repository default |

The agent job runs read-only. The comment is written by a separate, scoped
safe-outputs job **after** the agent finishes — the agent never holds write access.
See [execution architecture](../../concepts/execution-architecture.md).

## 4. Working workflow

- Workflow: [`.github/workflows/pr-review-helper.md`](../../../.github/workflows/pr-review-helper.md)
- Compiled: [`.github/workflows/pr-review-helper.lock.yml`](../../../.github/workflows/pr-review-helper.lock.yml)

Compile and validate after editing:

```bash
make compile
make ci-test
```

To try it, open a pull request in the repository. The `COPILOT_GITHUB_TOKEN` secret
must be set first — see [getting started](../../tutorials/01_getting-started.md).

## 5. Human-in-the-Loop

The approval point is the pull request review itself. The agent only **comments**; a
human reads the findings and decides what to do. By configuration the agent cannot
approve, request changes as a formal review, merge, or modify files. This keeps a
person firmly in the decision loop while removing the cold-start cost of the first read.

## 6. Cost & security notes

- **Cost**: `pull_request` runs on every push to an open PR. For busy repositories,
  narrow the trigger (for example with `paths:` filters) or switch to an on-demand
  command trigger (`/review`). See
  [execution architecture → event-driven cost](../../concepts/execution-architecture.md#event-driven-execution-optimizes-cost).
- **Least privilege**: read-only permissions; the only side effect is one comment.
- **Untrusted input**: PR titles, descriptions, and diffs are untrusted content.
  gh-aw sanitizes event text and, for public repositories, applies integrity
  filtering automatically. Keep permissions read-only and never echo secrets.

## 7. Extensions

- Add inline review comments with the `create-pull-request-review-comment` safe-output.
- Gate the workflow behind a `/review` command so it runs on demand instead of on every push.
- Tailor the prompt to your team's style guide or review checklist.
- Combine with issue-triage or release-notes workflows for a fuller developer loop.

← Back to [① Software developer](README.md) · [Use cases](../README.md)
