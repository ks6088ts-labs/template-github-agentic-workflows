# FAQ: Copilot model alias resolution fails before startup

This FAQ records the diagnosis of the `daily-repo-status` failure observed on
September 19, 2026. It applies when a GitHub Agentic Workflow stops before the
first agent turn with both a model-catalog error and an unresolved-model-alias
error.

## What does the failure look like?

The decisive log sequence is:

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] copilot model alias resolution: catalog unavailable from awf-reflect for known alias 'auto'
[copilot-harness] copilot model alias resolution: retrying awf-reflect model-catalog fetch once before failing for 'auto'
[copilot-harness] copilot model alias resolution failed: model-catalog retrieval prevented alias resolution for 'auto' after a bounded refresh — refusing to start Copilot with an unresolved alias
```

In the [failed run](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900),
the containers and API proxy health checks succeeded. The audit nevertheless
reported zero agent turns and zero effective tokens because Copilot was never
started.

## What caused it?

Four conditions formed the failure chain:

1. The workflow did not select a model, so the compiled workflow set `COPILOT_MODEL` to the default alias `auto`.
2. `auto` is a known gh-aw model alias, not a concrete Copilot model ID.
3. Resolving that alias required the model catalog exposed through AWF `/reflect`, but the Copilot `/models` request returned HTTP 401 twice.
4. gh-aw v0.88.7 intentionally stopped before launching Copilot rather than forwarding an unresolved alias.

The immediate cause was therefore catalog-dependent alias resolution failing
after an authentication error from the model-list endpoint. It was not a Squid
network block or a container startup failure: the firewall recorded no blocked
request, and all three containers were healthy before the harness ran.

## Why did selecting a concrete model fix it?

The v0.88.7 resolver only needs the live catalog when the configured value is a
known alias key. A concrete model ID bypasses alias expansion; the upstream
regression test explicitly verifies that a concrete model remains usable when
the catalog is empty.

This repository therefore pins the model in the source workflow:

```yaml
engine: copilot
model: claude-sonnet-4.6
```

`claude-sonnet-4.6` was present in the v0.88.7 model metadata and had succeeded
in the audit baselines for this workflow. This value is incident-specific: use a
concrete model that the repository's Copilot subscription and policies allow.

After changing frontmatter, regenerate the lock file rather than editing it:

```bash
gh aw compile daily-repo-status --strict
```

The generated `.lock.yml` should then contain a literal `COPILOT_MODEL` instead
of an expression whose fallback is `auto`.

## Does pinning a model prove that the token is valid?

No. Pinning a concrete model removes the catalog lookup from alias resolution;
it does not bypass authentication for inference. The failed run's activation
secret check passed, yet the model-list endpoint still returned 401.

If a rerun reaches Copilot but inference also returns 401, verify that
`COPILOT_GITHUB_TOKEN` is present, unexpired, and entitled to use the selected
model. Re-register the secret when necessary:

```bash
make set-secret-github-copilot-token
```

Organizations with centralized Copilot billing can instead use the built-in
GitHub Actions token by declaring the documented permission and recompiling:

```yaml
permissions:
  contents: read
  copilot-requests: write
```

This alternative only works when the organization has enabled Copilot CLI
requests in its Copilot policies.

## Was the `awf-reflect.json` `EACCES` warning the root cause?

No. The harness also logged that it could not persist the reflection payload to
`/home/runner/work/_temp/awf-reflect.json`. That warning affects diagnostic
artifact persistence, but execution continued into the bounded catalog refresh.
The explicit exit followed the unresolved-alias message.

Treat the permission warning as a separate runtime issue if reflection artifacts
are needed, but do not use it to explain this exit unless the model-catalog and
alias-resolution messages are absent.

## How can I diagnose the same symptom?

Start from the run ID and inspect the downloaded audit artifacts:

```bash
gh aw audit <run-id> --json
gh aw logs <workflow-name> --json
```

Check the signals in this order:

| Signal | Interpretation |
| --- | --- |
| `COPILOT_MODEL: auto` or another alias | Runtime catalog data is required before Copilot can start. |
| `models fetch returned 401` or `403` | The catalog endpoint rejected authentication or authorization; these permanent 4xx responses are fail-fast. |
| `models fetch returned 429` or `503` | The catalog endpoint is temporarily unavailable; current gh-aw versions use bounded retries. |
| `refusing to start Copilot with an unresolved alias` | Expected fail-closed behavior; the unresolved alias is not sent to inference. |
| Zero turns and zero effective tokens | Failure occurred during the harness handoff, before model inference. |
| A concrete model also returns 401 during inference | Fix the token, entitlement, or organization policy; model pinning is not sufficient. |

The upstream issue originally covered HTTP 429. This incident returned HTTP
401, but it reached the same generalized fail-closed path introduced by the
upstream fix.

## What is the recovery checklist?

1. Select a concrete Copilot model supported by the repository's subscription.
2. Set `engine: copilot` and top-level `model:` in the source `*.md` workflow.
3. Recompile and commit both the source workflow and generated `.lock.yml`.
4. Run repository validation, then dispatch the workflow again.
5. Audit the rerun and confirm that at least one inference turn starts.
6. If inference itself returns 401, repair the Copilot credential or organization policy.

For this repository, the local validation sequence is:

```bash
gh aw compile daily-repo-status --strict
make ci-test
gh aw run daily-repo-status
```

## Primary sources

| Evidence | Primary source |
| --- | --- |
| Incident log and exact 401/alias failure | [Workflow run 35470003900](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900) and its [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900/job/105969169242#step:26:210) |
| Alias keys require a catalog; concrete IDs bypass alias resolution | [`resolve_model_alias.cjs` at gh-aw v0.88.7](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.cjs) |
| One bounded refresh followed by fail-closed exit | [`copilot_harness.cjs` at gh-aw v0.88.7](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/copilot_harness.cjs) |
| Regression coverage for an empty catalog and a concrete model | [`resolve_model_alias.test.cjs` at gh-aw v0.88.7](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.test.cjs) |
| Original catalog outage report and design rationale | [github/gh-aw issue #52782](https://github.com/github/gh-aw/issues/52782) |
| Implementation of bounded retry and unresolved-alias refusal | [github/gh-aw pull request #53456](https://github.com/github/gh-aw/pull/53456) |
| Compiler/runtime version used in the incident | [gh-aw v0.88.7 release](https://github.com/github/gh-aw/releases/tag/v0.88.7) |
| Supported engine/model configuration | [AI Engines reference](https://github.github.com/gh-aw/reference/engines/) |
| PAT versus `copilot-requests: write` authentication paths | [Billing reference](https://github.github.com/gh-aw/reference/billing/) and [Authentication reference](https://github.github.com/gh-aw/reference/auth/) |
