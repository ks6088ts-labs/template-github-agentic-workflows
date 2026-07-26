# Ambient agents and Human-in-the-Loop: a short survey

An initial survey of the "ambient agent + Human-in-the-Loop (HITL)" idea and how
GitHub Agentic Workflows (gh-aw) realizes it. This is a first version meant to be
expanded as the persona scenarios grow.

## What is an "ambient agent"?

An **ambient agent** runs in the background and reacts to events, rather than waiting
for a person to chat with it turn by turn. Compared with an interactive chat assistant:

| Interactive (chat) agent | Ambient agent |
| --- | --- |
| A human starts every turn | Events start the work (issue, PR, schedule, command) |
| Foreground, one at a time | Background, potentially many in parallel |
| Human watches each step | Human is not watching most of the time |

Because nobody is watching each step, ambient agents need explicit points where control
returns to a human.

## Why Human-in-the-Loop?

**Human-in-the-Loop** reinserts human judgment at the moments that matter — typically
*approve / edit / reject* of a proposed action — so an autonomous agent can operate
continuously while consequential effects still require a person's decision. HITL is what
makes ambient automation safe to leave running.

Public discussion of this pairing includes the Japanese-language perspective in Nikkei
COMEMO, *"AI BPO — Ambient Agent + Human in the Loop"*
(<https://comemo.nikkei.com/n/n76970e72afde>), which frames ambient agents plus HITL as a
model for back-office automation. (Referenced by theme; treat as an entry point rather
than a specification.)

## How gh-aw maps to ambient + HITL

gh-aw is, in effect, an ambient-agent runtime with HITL built into its architecture:

| Ambient + HITL concept | gh-aw mechanism |
| --- | --- |
| Event activation | Triggers: `issues`, `pull_request`, `schedule`, command (`/…`) |
| Background / managed execution | Runs on GitHub Actions managed runners |
| Bounded autonomy | Read-only permissions by default; least privilege |
| HITL approval gate | [Safe-outputs](https://github.github.com/gh-aw/reference/safe-outputs/): writes are buffered and applied only after checks; a human reviews the result |
| Trust on untrusted input | Content sanitization + integrity filtering |
| Guardrails against compromise | Threat detection, secret redaction, network allowlist |
| Auditability | `gh aw logs` / `gh aw audit` |

See [execution architecture](execution-architecture.md) for the mechanisms in detail.

## Where this repository's scenarios sit

- [PR review helper](../use-cases/dev-productivity/pr-review-helper.md) — **ambient
  activation** on `pull_request`; **HITL** because the agent only posts a comment and a
  human decides whether to act.
- [Periodic status report](../use-cases/infra-ops/status-report.md) — **ambient
  activation** on a daily `schedule`; **HITL** because the team reviews the report issue
  and triages from there.

Both keep the agent read-only and route every effect through a safe-output — the HITL gate.

## Open questions & next steps

- **Stronger approval flows (IssueOps).** Command-triggered request/approval flows gated
  to specific people are a natural next step, planned for the ③ back-office persona. See
  the gh-aw [IssueOps pattern](https://github.github.com/gh-aw/patterns/issue-ops/).
- **Staged / draft outputs.** Explore
  [staged-mode safe-outputs](https://github.github.com/gh-aw/reference/staged-mode/) for
  an explicit "propose then apply" review step.
- **Multi-engine comparison.** This survey assumes the Copilot engine; comparing
  Claude / Codex / Gemini behavior is future work.

## References

- Nikkei COMEMO, *AI BPO — Ambient Agent + Human in the Loop*: <https://comemo.nikkei.com/n/n76970e72afde>
- gh-aw [Security Architecture](https://github.github.com/gh-aw/introduction/architecture/)
- gh-aw [Safe Outputs](https://github.github.com/gh-aw/reference/safe-outputs/) · [IssueOps pattern](https://github.github.com/gh-aw/patterns/issue-ops/)
- [Execution architecture (this repo)](execution-architecture.md)
