# Example: MCP servers in the egress allowlist

Shows how the egress-policy generator folds MCP server egress into the
`FirewallPolicy` allowlist. `librechat.yaml` here adds three MCP servers to the
base config; `firewall-policy.yaml` is the generated result.

## What each MCP shape produces

| `librechat.yaml` entry | Shape | Effect on the allowlist |
|---|---|---|
| `deepwiki` → `https://mcp.deepwiki.com/mcp` | remote (`streamable-http`) | host `mcp.deepwiki.com` permitted (tcp/443) |
| `sequential-thinking` → `npx ...` | subprocess (`stdio`) | `registry.npmjs.org` permitted **+ stderr warning** recommending the Aviatrix OBOT VCA (a subprocess MCP runs *inside* the pod and can't be domain-scoped per server) |
| `local-tool` → `http://host.docker.internal:3001/mcp` | internal | **skipped**, left as a `# notes:` comment (cluster-local, never egresses) |

So the generated `webGroups` allowlist is:

```
# --- always_on: image_registry ---   (registry.librechat.ai, docker.io, ...)
# --- always_on: bedrock_sts ---       (sts.amazonaws.com)
# --- bedrock runtime ---              (bedrock-runtime.us-east-1.amazonaws.com)
# --- remote mcp servers ---           (mcp.deepwiki.com)        <-- from deepwiki
# --- subprocess mcp package registries --- (registry.npmjs.org) <-- from npx server
# notes: (skipped internal MCP local-tool: http://host.docker.internal:3001/mcp)
```

…followed by the trailing per-pod `deny-other-egress` rule. Net effect: the
LibreChat pod can reach Bedrock **and** `mcp.deepwiki.com` **and**
`registry.npmjs.org`, and nothing else.

## Regenerate

```bash
python ../../egress-policy/generate.py \
  --config librechat.yaml --namespace librechat \
  --pod-label app.kubernetes.io/name=librechat \
  --env-keys "" --output firewall-policy.yaml
```

## Verified live

Applied to a running deployment on EKS: egress to `mcp.deepwiki.com` connected
(permitted), while an unlisted host (`example.org`) was reset by the deny rule.

## Note on subprocess MCP servers

`npx`/`uvx` servers run as child processes of the LibreChat pod, so a network
policy can only allow/deny at the *pod* level, not per server. The generator
permits their package registry (so the server can start) and warns. For true
per-server isolation, run the MCP server as its own workload via the
**Aviatrix OBOT VCA** (`obot-mcp-egress-aws` / `obot-mcp-egress-azure`), which
gives each MCP server its own `MCPNetworkPolicy`-driven egress.
