# Troubleshooting Copilot engine startup failures

This guide covers GitHub Agentic Workflows that reach the Copilot harness but
stop before the first agent turn. It explains model availability, model-alias
resolution, PAT authentication, and authentication with the built-in GitHub
Actions token. The examples assume the default GitHub Copilot route, not a
Bring Your Own Key (BYOK) provider.

> [!IMPORTANT]
> Start with the earliest specific provider or harness error. A final message
> such as `all retries exhausted` reports the outcome, not the root cause.
> Zero agent turns and zero effective tokens confirm a pre-inference failure,
> but do not identify its cause.

## Quick diagnosis

| Log signal | Diagnosis | First action |
| --- | --- | --- |
| `requested model is not available` with HTTP 400 | The concrete model is unavailable for the current integrator, entitlement, or policy. | Select a concrete ID from the accompanying `Available models` list. |
| `catalog unavailable` followed by `refusing to start Copilot with an unresolved alias` | An alias such as `auto` could not be resolved because the model catalog was unavailable. | Use the preceding catalog status to distinguish authentication (`401`) from a temporary service failure (`429` or `503`). |
| `Authentication failed` with HTTP 401 on the PAT path | The provider rejected `COPILOT_GITHUB_TOKEN` or its owner's entitlement. | Verify the token type, permission, validity, Copilot license, and model access. |
| `S2STOKENS: true` and HTTP 403 | The built-in Actions token lacks organization-billed Copilot access. | Enable centralized organization billing or switch explicitly to PAT authentication. |
| `awf-reflect.json` with `EACCES` | A diagnostic artifact could not be saved. | Treat it separately when a later model or authentication error identifies the actual failure. |

## Collect evidence

Download the audit and logs for the failed run:

```bash
gh aw audit <run-id> --json
gh aw logs <workflow-name> --json
```

Inspect these signals in order:

1. The first explicit HTTP 400, 401, 403, 429, or 503 message.
2. The `inference routing` line and its `configuredModel` value.
3. `engine`, `model`, and `permissions` in the source Markdown workflow.
4. `COPILOT_MODEL`, `COPILOT_GITHUB_TOKEN`, and `S2STOKENS` in the generated `.lock.yml`.
5. Agent turns and effective token usage in the audit.

Do not edit `.lock.yml` directly. It is generated from the source workflow.

## HTTP 400: concrete model unavailable

### HTTP 400 log

```text
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
400 The requested model is not available for integrator "agentic-workflows". Available models: [... claude-sonnet-5 ...]
[copilot-harness] all 3 retries exhausted — giving up (exitCode=1)
```

### HTTP 400 diagnosis

The workflow reached Copilot CLI with a concrete model ID, but the provider
rejected that ID before inference. This is not an alias-resolution error. It is
also distinct from authentication and network failures.

Model availability depends on the integrator, account entitlement, and policy,
and can change over time. The `Available models` list in the current response is
more authoritative than an older compiler catalog or a previous successful run.

### HTTP 400 recovery

Select an ID from the response and set it in the source workflow. For the example
above, that change would be:

```yaml
engine:
  id: copilot
  model: claude-sonnet-5
```

Recompile the workflow and confirm that the generated `COPILOT_MODEL` contains
the replacement ID. Repeated retries cannot make an unavailable model valid.

## Alias resolution: model catalog unavailable

### Alias-resolution log

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] copilot model alias resolution: catalog unavailable from awf-reflect for known alias 'auto'
[copilot-harness] copilot model alias resolution: retrying awf-reflect model-catalog fetch once before failing for 'auto'
[copilot-harness] copilot model alias resolution failed: model-catalog retrieval prevented alias resolution for 'auto' after a bounded refresh — refusing to start Copilot with an unresolved alias
```

### Alias-resolution diagnosis

`auto` is a model alias rather than a concrete Copilot model ID. Resolving it
requires the runtime model catalog. The harness fails closed instead of sending
an unresolved alias to inference.

The catalog status identifies the next step:

- HTTP 401: fix the selected authentication path.
- HTTP 429 or 503: retry after the catalog service recovers.

### Alias-resolution recovery

Resolve the catalog error first. To remove the catalog dependency from alias
expansion, configure a concrete model that the current runtime exposes, then
recompile. A concrete model bypasses alias expansion, but it does not bypass
authentication for model discovery or inference.

## HTTP 401: PAT authentication rejected

### HTTP 401 log

```text
[copilot-harness] awf-reflect: models fetch returned 401 for http://api-proxy:10002/models
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-4.6" endpoint=managed-by-copilot-cli
Authentication failed with provider at http://172.30.0.30:10002 (HTTP 401).
[copilot-harness] attempt 2 failed: exitCode=1 failureClass=authentication_failed ... tokenCount=0
```

### HTTP 401 diagnosis

The provider rejected the credential before producing tokens. A successful
activation check proves only that a secret was supplied. Likewise, the
`updatedAt` value from `gh secret list` records when the secret was registered;
it does not prove that the PAT is valid.

HTTP 401 alone does not prove that a token expired. Possible causes include an
expired or revoked PAT, an unsupported token type, a missing `Copilot Requests`
permission, no active Copilot license for the token owner, or a policy that
blocks the selected model.

### HTTP 401 recovery

First confirm that the PAT path is selected. The source workflow should disable
organization billing explicitly when that is the intent:

```yaml
permissions:
  contents: read
  copilot-requests: none
```

The generated workflow should read `COPILOT_GITHUB_TOKEN` from repository
secrets and should not set `S2STOKENS: true`.

Create a fine-grained PAT with all of these properties:

1. The resource owner is the user account with the Copilot license, not an organization.
2. **Account permissions > Copilot Requests** is set to **Read**.
3. The owner has an active Copilot subscription and access to the selected model.
4. The token is a PAT, not an OAuth user token such as `gho_...`.

Update the repository secret without placing the PAT in a command-line argument:

```bash
gh secret set COPILOT_GITHUB_TOKEN
```

In a temporary shell where the replacement PAT has been exported securely, test
the same entitlement outside Actions:

```bash
copilot -p "Reply only with OK"
```

If the local request fails, correct the token, license, entitlement, or policy
before rerunning the workflow. On the default GitHub Copilot route, do not add
`COPILOT_PROVIDER_*` repository secrets in response to a generic CLI message;
those variables are for explicitly configured BYOK providers.

## HTTP 403: built-in Actions token not authorized

### HTTP 403 log

```text
S2STOKENS: true
[copilot-harness] awf-reflect: models fetch returned 403 for http://api-proxy:10002/models
[copilot-harness] inference routing: mode=cli configuredModel="claude-sonnet-5" endpoint=managed-by-copilot-cli
Authentication failed with provider at http://172.30.0.30:10002 (HTTP 403).
[copilot-harness] attempt 2: Copilot requests authentication failed through the gh-aw API proxy (HTTP 403, model=claude-sonnet-5, stage=starting the Copilot CLI request).
```

### HTTP 403 diagnosis

`S2STOKENS: true` indicates the organization-billing path selected by
`copilot-requests: write`. In this mode gh-aw uses `${{ github.token }}` for
inference and ignores a repository secret named `COPILOT_GITHUB_TOKEN`.
Rotating that secret cannot change this authentication path.

The 403 localizes the failure to Copilot authorization, but does not identify
which administrative prerequisite is missing.

### HTTP 403 recovery

For organization billing, keep this configuration:

```yaml
permissions:
  contents: read
  copilot-requests: write
```

Ask an organization administrator to confirm an active Copilot subscription and
that centralized billing for Copilot CLI requests is allowed by organization
policy. Recompile after changing workflow permissions.

If centralized billing is unavailable, switch explicitly to the PAT path:

```yaml
permissions:
  contents: read
  copilot-requests: none
```

Then configure `COPILOT_GITHUB_TOKEN` as described in the HTTP 401 section and
recompile. Do not configure both paths expecting the PAT to take precedence.

## `awf-reflect.json` `EACCES` warnings

A warning containing `/home/runner/work/_temp/awf-reflect.json` and `EACCES`
means the harness could not persist a diagnostic reflection artifact. If the
run continues and later reports an explicit model or authentication error, that
later error is the cause of the failed startup.

Investigate the artifact path and runner permissions when the reflection file is
required, or when no later error explains the exit. Do not use this warning to
explain an explicit HTTP 400, 401, or 403 response.

## Recompile and verify

After changing the source workflow, regenerate the lock file, validate, run, and
audit a fresh execution:

```bash
gh aw compile <workflow-name> --strict
gh aw validate
gh aw run <workflow-name>
gh aw audit <new-run-id> --json
```

Changing only a repository secret does not require compilation or a commit.
Changing `engine`, `model`, or `permissions` does.

Recovery is confirmed when:

1. The generated lock file contains the intended model and authentication path.
2. The original provider or alias-resolution error is absent.
3. At least one inference turn starts and token usage is greater than zero.

## Recovery checklist

1. Classify the first specific provider error, not the final retry message.
2. Identify the authentication path from `permissions` and `S2STOKENS`.
3. For HTTP 400, choose a model from the current `Available models` response.
4. For HTTP 401, repair the PAT, its permission, and the owner's Copilot access.
5. For HTTP 403 with `S2STOKENS: true`, enable organization billing or switch explicitly to the PAT path.
6. Recompile after source changes; never edit `.lock.yml` directly.
7. Rerun and verify an inference turn and nonzero token usage.

## Primary references

All references below are maintained by GitHub:

- [GitHub Agentic Workflows: AI engines](https://github.github.com/gh-aw/reference/engines/)
- [GitHub Agentic Workflows: Authentication](https://github.github.com/gh-aw/reference/auth/)
- [GitHub Agentic Workflows: Billing](https://github.github.com/gh-aw/reference/billing/)
- [GitHub Agentic Workflows: Common issues](https://github.github.com/gh-aw/troubleshooting/common-issues/)
- [GitHub Agentic Workflows: Debugging workflows](https://github.github.com/gh-aw/troubleshooting/debugging/)
- [GitHub Docs: Using secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [GitHub Docs: Token expiration and revocation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/token-expiration-and-revocation)
- [GitHub CLI manual: `gh secret set`](https://cli.github.com/manual/gh_secret_set)
