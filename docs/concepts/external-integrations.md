# External integrations: Azure and external APIs

How to connect a workflow to Azure and other external APIs, and how credentials flow so the
LLM never sees raw secrets. Distilled from the official
[Custom Steps and Jobs](https://github.github.com/gh-aw/reference/steps-jobs/),
[Using MCPs](https://github.github.com/gh-aw/guides/mcps/), and
[Network Configuration](https://github.github.com/gh-aw/guides/network-configuration/)
references; see [Sources](#sources).

## Principle: the path depends on who uses the credential

gh-aw is designed so the **LLM never sees raw credentials**. The route splits by *who* uses
the credential:

| User of the credential | Route | Sandbox | Secret handling |
| --- | --- | --- | --- |
| **Deterministic steps/jobs** (normal Actions steps) | `pre-steps:` / `steps:` / `post-steps:` / `jobs:` | **Outside** the firewall; standard Actions security | Use `${{ secrets.* }}` directly; the LLM never sees it |
| **The agent (LLM) via a tool** | Injected into an **MCP server** (`env` / `headers` / `auth`) | Inside the sandbox | Held/forwarded by the gateway; never placed in the prompt |

Custom steps and jobs run **outside** the firewall sandbox with standard GitHub Actions
security, so **to actually touch Azure resources, run `azure/login` in a deterministic step**.

> **Pitfall**: never put `${{ secrets.* }}` in workflow-level `env:` — it reaches the agent
> container and exposes the secret to the model (**compile error in strict mode**). See
> [workflow format](compilation-and-format.md).

## Credential mechanisms

1. **`secrets:` frontmatter** — declare what's passed; always `${{ secrets.NAME }}` (never plaintext).
2. **Inject into an MCP server** (agent uses it):
   - Local (Docker) MCP → `env:` with `${{ secrets.* }}`
   - HTTP MCP → `headers:` with `Authorization: Bearer ${{ secrets.* }}`, or `auth: { type: github-oidc }` to auto-mint a short-lived JWT
3. **Deterministic step/job** (used outside the agent) → step `env:` / `with:` with `${{ secrets.* }}`, or `azure/login` via OIDC.
4. **Network allowlist** — even with valid auth, agent traffic goes through the firewall, so allow the destination domain in `network.allowed`.

## Network allowlist (firewall)

Strict mode (default) accepts only **ecosystem identifiers** (`defaults`, `python`, `node`,
`go`, `containers`, `terraform`, `playwright`, `github`, …). To allow **arbitrary domains**
(Azure endpoints, …), set `strict: false` and list them. Discover required domains from the
firewall-deny entries in `gh aw logs --run-id <id>`. `network: {}` blocks all external traffic
(engine traffic is still allowed).

## Patterns

### 1. External API — inject an API key as an HTTP MCP header

```yaml
---
on: issues
permissions:
  contents: read
mcp-servers:
  authenticated-api:
    url: "https://api.example.com/mcp"
    headers:
      Authorization: "Bearer ${{ secrets.API_TOKEN }}"
    allowed: ["*"]
---
```

### 2. External API — short-lived token via GitHub OIDC (no static key)

```yaml
---
permissions:
  id-token: write   # required to mint the OIDC token
mcp-servers:
  my-secure-server:
    url: "https://my-server.example.com/mcp"
    auth:
      type: github-oidc
      audience: "https://my-server.example.com"  # defaults to the URL
    allowed: ["*"]
---
```

The gateway obtains a JWT from the GitHub Actions OIDC endpoint and injects it as
`Authorization: Bearer` per request (server-side verification is your responsibility;
`auth.type: github-oidc` is HTTP-only).

### 3. Local (Docker) MCP — inject a secret via env + allow its egress

```yaml
---
mcp-servers:
  custom-tool:
    container: "mcp/custom-tool:v1.0"
    env:
      API_KEY: "${{ secrets.API_KEY }}"
    allowed: ["tool1", "tool2"]
    network:
      allowed:
        - defaults
        - api.example.com
---
```

### 4. Touch Azure resources (recommended: deterministic step + OIDC)

Don't hand the agent any secret. Run `azure/login` (federated credential) in a normal Actions
step, then pass the *result* (a file / job output) to the agent.

```yaml
---
on: workflow_dispatch
permissions:
  id-token: write     # required for Azure OIDC federation
  contents: read
steps:
  - name: Azure login (OIDC / federated credential)
    uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  - name: Pull Azure data for the agent
    run: az account show -o json > /tmp/gh-aw/azure-context.json
---
# Body
Read /tmp/gh-aw/azure-context.json and summarize cost-optimization opportunities…
```

> Never pass the credential/token to the agent directly — drop data into a file or
> `jobs.<id>.outputs` and reference it from the body via `${{ needs.<job>.outputs.* }}`. Keep
> **write** operations on the deterministic side (`az` CLI, safe-outputs); MCP servers should
> be read-only.

### 5. Pass a custom job's output to the agent

```yaml
---
jobs:
  release:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.get.outputs.version }}
    steps:
      - id: get
        run: echo "version=${{ github.event.release.tag_name }}" >> $GITHUB_OUTPUT
---
Generate highlights for release ${{ needs.release.outputs.version }}…
```

### 6. Allow custom domains (Azure, …)

```yaml
---
strict: false        # required to allow custom domains
network:
  allowed:
    - defaults
    - "management.azure.com"
    - "*.vault.azure.net"
    - "login.microsoftonline.com"
---
```

## Prebuilt Microsoft / Azure MCP

gh-aw ships shared MCP configs (`.github/workflows/shared/mcp/*.md`) including Azure, Microsoft
Docs, and Fabric RTI. The Microsoft Docs MCP can be used directly:

```yaml
mcp-servers:
  microsoftdocs:
    url: "https://learn.microsoft.com/api/mcp"
    allowed: ["*"]
```

Add the Azure MCP with `gh aw mcp add` (from the registry) or import `shared/mcp/azure.md`.

## Recommended architecture

- **Reads** → give the agent an MCP tool (`env` / `headers` / `auth: github-oidc`; allow the
  domain in `network.allowed`).
- **Writes / Azure resource operations** → a deterministic step/job with `azure/login` (OIDC
  federation). Pass only results to the LLM, never the secret.
- **Secrets** flow only through `secrets:` + MCP/step — never workflow-level `env:`.
- Prefer **secret-less OIDC federated credentials** for Azure.

## Sources

- [Custom Steps and Jobs](https://github.github.com/gh-aw/reference/steps-jobs/)
- [Using MCPs](https://github.github.com/gh-aw/guides/mcps/)
- [Network Configuration](https://github.github.com/gh-aw/guides/network-configuration/)
- [Frontmatter](https://github.github.com/gh-aw/reference/frontmatter/)
