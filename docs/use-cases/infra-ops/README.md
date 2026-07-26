# ② IT infra operator

Agentic workflows that keep operators informed without manual reporting: recurring
status summaries, fault triage, and dependency-update follow-up.

## Scenarios

| Scenario | Trigger | Safe-output | Workflow |
| --- | --- | --- | --- |
| [Periodic status report](status-report.md) | `schedule` (daily) | `create-issue` | [daily-repo-status.md](../../../.github/workflows/daily-repo-status.md) |

More scenarios (fault-triage summaries, dependency-update follow-up) will be added
in later iterations.

← Back to [use cases](../README.md)
