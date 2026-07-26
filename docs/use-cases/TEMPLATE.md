# Scenario template

Copy this page when adding a new use-case scenario. Every scenario uses the same
seven sections so readers can compare scenarios at a glance.

Keep each section short and concrete, and link to a **working** workflow under
[`.github/workflows/`](../../.github/workflows) — a scenario is not complete until a
real, compiling workflow is attached.

---

## 1. Background & problem (背景・課題)

Describe the team situation and the pain point: who feels it, how often, and why
handling it manually is costly or error-prone.

## 2. Automation goal (自動化ゴール)

One or two sentences: what the workflow should achieve, and how you will know it
worked (the observable outcome).

## 3. Design: trigger / permissions / safe-outputs (トリガー・permissions・safe-outputs 設計)

| Aspect | Choice | Why |
| --- | --- | --- |
| Trigger (`on:`) | … | when the workflow should run |
| Permissions | … | least privilege |
| Safe-outputs | … | the only write path |
| Engine | `copilot` | repository default |

## 4. Working workflow (動作 workflow へのリンク)

Link to the workflow Markdown and its compiled `*.lock.yml`, and note how to run it.

## 5. Human-in-the-Loop (承認点)

Where does a human stay in control? Identify the approval/decision point and what
the agent is explicitly **not** allowed to do.

## 6. Cost & security notes (コスト・セキュリティ注意)

Trigger frequency and cost implications, permission scope, handling of
fork/untrusted input, and any secrets involved. See
[execution architecture](../concepts/execution-architecture.md).

## 7. Extensions (発展)

Ideas to grow the scenario: richer prompts, additional safe-outputs, command
triggers, or combining with other workflows.
