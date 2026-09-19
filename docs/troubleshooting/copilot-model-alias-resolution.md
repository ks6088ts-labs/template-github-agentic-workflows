# FAQ: Copilot model selection fails before startup

This FAQ records three related `daily-repo-status` failures observed on September
19-20, 2026. The first stopped during model-alias resolution. The follow-up used
a concrete model but stopped before the first agent turn when the Copilot provider
rejected its credential with HTTP 401. The latest run returned HTTP 400 because
that concrete model was no longer available to the `agentic-workflows` integrator.

## What does `requested model is not available` mean?

The decisive sequence in the [latest failed run](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471741529) is:

```text
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
400 The requested model is not available for integrator "agentic-workflows". Available models: [... claude-sonnet-5 ...]
[copilot-harness] all 3 retries exhausted — giving up (exitCode=1)
```

The workflow passed container startup and handed the concrete ID
`claude-sonnet-4.6` to Copilot CLI, but the provider rejected it before the first
inference turn. The same response listed `claude-sonnet-5` as available and did
not list `claude-sonnet-4.6`, so the configured model had become stale for this
integrator. This is not an alias-resolution, token-authentication, or network
failure.

## How do I fix an unavailable concrete model?

Choose a concrete ID from the `Available models` list in the failed run. To keep
the same model family, this repository now uses:

```yaml
engine: copilot
model: claude-sonnet-5
```

Then regenerate the lock file from the source workflow:

```bash
gh aw compile daily-repo-status --strict
```

Do not edit `.lock.yml` directly. Confirm that the generated metadata and every
literal `COPILOT_MODEL` value use the replacement ID, then rerun the workflow.
Model availability is scoped to the integrator, account entitlement, and policy,
and it can change over time; the list returned by the failing request is more
authoritative than a previously successful run or an older compiler catalog.

## What did the earlier alias-resolution failure look like?

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

## What caused the earlier alias-resolution failure?

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

The earlier incident therefore pinned a concrete model in the source workflow.
That model was subsequently removed from the runtime availability list, so the
current source uses an available model from the same family:

```yaml
engine: copilot
model: claude-sonnet-5
```

`claude-sonnet-4.6` was present in the v0.88.7 model metadata and had succeeded
in the audit baselines for this workflow, but that history did not guarantee
continued availability. Use a concrete model listed by the current runtime for
the repository's Copilot subscription and policies.

After changing frontmatter, regenerate the lock file rather than editing it:

```bash
gh aw compile daily-repo-status --strict
```

The generated `.lock.yml` should then contain a literal `COPILOT_MODEL` instead
of an expression whose fallback is `auto`.

## What does a 401 after pinning a concrete model mean?

Pinning a concrete model removes the catalog dependency from alias resolution;
it does not bypass authentication for model discovery or inference. The
[follow-up run](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052)
contained this decisive sequence:

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
Authentication failed with provider at http://172.30.0.30:10002 (HTTP 401).
[copilot-harness] attempt 2 failed: exitCode=1 failureClass=authentication_failed ... tokenCount=0
```

This confirms that `claude-sonnet-4.6` reached the Copilot CLI as a concrete
model and that the provider rejected authentication before producing any
tokens. The activation step named `Validate COPILOT_GITHUB_TOKEN secret`
succeeded, but that check only established that a secret was supplied; the
provider's 401 showed that the credential was not usable for this request.

The actionable repository secret remains `COPILOT_GITHUB_TOKEN`. The
`COPILOT_PROVIDER_*` names in the Copilot CLI error describe the internal AWF
proxy handoff and do not require additional repository secrets.

## Does this prove that the stored token is old?

No. HTTP 401 proves that the provider rejected the credential, but it does not
identify the credential lifecycle or policy reason. An expired or revoked token
is a strong candidate. Other candidates are an unsupported token type, missing
`Copilot Requests` permission, no active Copilot license for the token owner, or
an organization/model policy that denies the selected model.

GitHub documents that a PAT can stop working at its expiration date, after one
year without use, after public exposure, or after revocation. An expired or
revoked token cannot be restored; create a replacement. The timestamp reported
by `gh secret list` shows when the Actions secret was last registered, not the
PAT's expiration or validity, and GitHub does not expose secret values for
comparison.

For this incident, the repository metadata inspected on September 20, 2026
reported:

```json
{"name":"COPILOT_GITHUB_TOKEN","updatedAt":"2026-07-25T23:15:22Z"}
```

That date supports rotating the credential as the fastest discriminating test,
but it does not prove when the stored PAT was created or whether it expired.

## How do I create a compatible replacement token?

Use the gh-aw [pre-filled fine-grained PAT form](https://github.com/settings/personal-access-tokens/new?name=COPILOT_GITHUB_TOKEN&description=GitHub+Agentic+Workflows+-+Copilot+engine+authentication&user_copilot_requests=read),
then verify all of these settings before generating the token:

1. **Resource owner** is the user account that has the Copilot license, not the organization.
2. **Account permissions → Copilot Requests** is set to **Read**.
3. The token owner has an active Copilot subscription and access to the selected model.

Do not use an OAuth user token such as a `gho_...` token. gh-aw requires a PAT
for `COPILOT_GITHUB_TOKEN` and rejects OAuth user tokens during activation.

## How do I update the repository secret quickly?

Use GitHub CLI without putting the PAT in the command line. This command prompts
for the value and updates the repository secret used by the next workflow run:

```bash
gh secret set COPILOT_GITHUB_TOKEN \
  --repo ks6088ts-labs/template-github-agentic-workflows
```

Rotating only the secret does not require `gh aw compile` or a repository
commit. GitHub Actions resolves the current secret value when the next run
starts.

GitHub CLI encrypts the value locally before sending it. Avoid a literal
`--body "github_pat_..."` because command-line arguments and shell history can
expose credentials. If `COPILOT_GITHUB_TOKEN` is already supplied securely in
the environment or this repository's gitignored `.env`, the existing shortcut
updates the same repository secret:

```bash
make set-secret-github-copilot-token
```

Confirm the secret name and update timestamp without reading its value:

```bash
gh secret list \
  --repo ks6088ts-labs/template-github-agentic-workflows \
  --app actions \
  --json name,updatedAt \
  --jq '.[] | select(.name == "COPILOT_GITHUB_TOKEN")'
```

## How do I verify the replacement?

In a temporary local shell where the new PAT has been exported securely, first
exercise the same Copilot entitlement outside Actions:

```bash
copilot -p "Reply only with OK"
```

If this fails, rotating the Actions secret alone will not help; correct the PAT
permission, Copilot license, or organization/model policy. If it succeeds,
dispatch and audit a fresh workflow run:

```bash
gh aw run daily-repo-status
gh aw audit <new-run-id> --json
```

The repair is confirmed when the run starts at least one inference turn and
reports nonzero token usage. A successful activation secret check or a recent
`updatedAt` timestamp alone is not sufficient.

## Can I avoid a long-lived PAT?

Yes. Organizations with centralized Copilot billing can use the built-in
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
artifact persistence, but execution continued. The original run exited after
the unresolved-alias message; the follow-up run reached the Copilot CLI and was
explicitly classified as `authentication_failed`; the latest run reached the
Copilot CLI and returned the explicit unavailable-model HTTP 400.

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
| `requested model is not available for integrator "agentic-workflows"` | The configured concrete ID is unavailable under the current runtime entitlement or policy; select an ID from the accompanying `Available models` list. |
| The requested model is absent from `Available models` | Treat the configured ID as stale even if an earlier run or compiler catalog accepted it. |
| The same model-related HTTP 400 repeats across harness retries | This is a deterministic configuration failure; retries do not make an unavailable model valid. |
| `COPILOT_MODEL: auto` or another alias | Runtime catalog data is required before Copilot can start. |
| `models fetch returned 401` or `403` | The catalog endpoint rejected authentication or authorization; these permanent 4xx responses are fail-fast. |
| `models fetch returned 429` or `503` | The catalog endpoint is temporarily unavailable; current gh-aw versions use bounded retries. |
| `refusing to start Copilot with an unresolved alias` | Expected fail-closed behavior; the unresolved alias is not sent to inference. |
| Zero turns and zero effective tokens | Failure occurred during the harness handoff, before model inference. |
| A concrete model also returns 401 during inference | Fix the token, entitlement, or organization policy; model pinning is not sufficient. |
| Activation secret validation succeeds, then inference returns 401 | A secret is present, but provider acceptance has not been proven; rotate or diagnose the PAT. |

The upstream issue originally covered HTTP 429. This incident returned HTTP
401, but it reached the same generalized fail-closed path introduced by the
upstream fix.

## What is the recovery checklist?

1. Classify the failure from the exact provider message rather than the final retry error.
2. For `requested model is not available`, select a concrete ID from that response's `Available models` list.
3. For an unresolved alias, select a concrete Copilot model supported by the repository's subscription.
4. Set `engine: copilot` and top-level `model:` in the source `*.md` workflow.
5. Recompile and commit both the source workflow and generated `.lock.yml`.
6. Run repository validation, dispatch the workflow again, and confirm that at least one inference turn starts.
7. If inference returns 401, create a compatible PAT, update `COPILOT_GITHUB_TOKEN`, and test the PAT with Copilot CLI.
8. If a fresh PAT still fails, repair the Copilot license, model entitlement, or organization policy.

For this repository, the local validation sequence is:

```bash
gh aw compile daily-repo-status --strict
make ci-test
gh aw run daily-repo-status
```

## Primary sources

| Evidence | Primary source |
| --- | --- |
| Concrete model rejected as unavailable and current model list | [Workflow run 35471741529](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471741529) and its [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471741529/job/105973861793#step:26:211) |
| Incident log and exact 401/alias failure | [Workflow run 35470003900](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900) and its [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35470003900/job/105969169242#step:26:210) |
| Concrete-model provider 401 and `authentication_failed` classification | [Workflow run 35471231052](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052) and its [agent execution step](https://github.com/ks6088ts-labs/template-github-agentic-workflows/actions/runs/35471231052/job/105972518194#step:26:210) |
| Alias keys require a catalog; concrete IDs bypass alias resolution | [`resolve_model_alias.cjs` at gh-aw v0.88.7](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.cjs) |
| One bounded refresh followed by fail-closed exit | [`copilot_harness.cjs` at gh-aw v0.88.7](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/copilot_harness.cjs) |
| Regression coverage for an empty catalog and a concrete model | [`resolve_model_alias.test.cjs` at gh-aw v0.88.7](https://github.com/github/gh-aw/blob/v0.88.7/actions/setup/js/resolve_model_alias.test.cjs) |
| Original catalog outage report and design rationale | [github/gh-aw issue #52782](https://github.com/github/gh-aw/issues/52782) |
| Implementation of bounded retry and unresolved-alias refusal | [github/gh-aw pull request #53456](https://github.com/github/gh-aw/pull/53456) |
| Compiler/runtime version used in the incident | [gh-aw v0.88.7 release](https://github.com/github/gh-aw/releases/tag/v0.88.7) |
| Supported engine/model configuration | [AI Engines reference](https://github.github.com/gh-aw/reference/engines/) |
| Fine-grained PAT requirements, secret setup, and `copilot-requests: write` alternative | [Authentication reference](https://github.github.com/gh-aw/reference/auth/) and [Billing reference](https://github.github.com/gh-aw/reference/billing/) |
| Local Copilot license/inference diagnostic | [gh-aw Common Issues](https://github.github.com/gh-aw/troubleshooting/common-issues/#copilot-license-or-inference-access-issues) |
| Secure repository secret update and metadata listing | [`gh secret set` manual](https://cli.github.com/manual/gh_secret_set), [`gh secret list` manual](https://cli.github.com/manual/gh_secret_list), and [Using secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) |
| PAT expiration and revocation conditions | [Token expiration and revocation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/token-expiration-and-revocation) and [Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) |
