# Egress Policy Generator (translator shim)

Reads `../chart/librechat.yaml` (plus which `.env` keys are set) and emits an
Aviatrix `FirewallPolicy` CRD that permits only the egress the current LibreChat
configuration actually requires. Everything else stays denied by the base
cluster's DCF default-deny.

> This is the source of record for the generator — it ships with the blueprint
> and is covered by the `tests/` suite (golden-file + unit; run `pytest`). The
> tests document the behavior.

## Run it for this blueprint

The official chart labels the LibreChat pod `app.kubernetes.io/name: librechat`
(because `values.yaml` sets `fullnameOverride: librechat`). The generated policy
selector MUST match that label — note the non-default `--pod-label`:

```bash
pip install -r requirements.txt   # pyyaml

python generate.py \
  --config ../chart/librechat.yaml \
  --env ../chart/.env \
  --namespace librechat \
  --pod-label app.kubernetes.io/name=librechat \
  --output firewall-policy.yaml
```

Then apply it to the cluster (the Aviatrix CRD controller onboarded by the base
blueprint reconciles it into live DCF):

```bash
kubectl apply -f firewall-policy.yaml
```

## Default-deny (self-enforcing)

By default the generated policy ends with a per-pod `deny-other-egress` rule
(tcp/443 → `0.0.0.0/0`) placed after the permits. DCF is first-match, so
allowlisted FQDNs pass and everything else from the LibreChat pods is dropped —
the policy enforces least-privilege on its own, without depending on a
fabric-wide default-deny. Pass `--no-default-deny` to omit it and rely on the
fabric default-deny instead. (Verified live: allowlisted FQDNs connect; unlisted
destinations are reset.)

## Catalog

`egress-catalog.yaml` is the data-only extension point for domains not derived
directly from `librechat.yaml`: the Bedrock STS endpoint (`bedrock.sts_domains`,
emitted only when Bedrock is enabled) and optional integrations keyed on env vars
(`env_gated`). It deliberately lists **no** container-registry domains — image
pulls happen on the node, not the pod. Edit it — never the generated
`firewall-policy.yaml` — to add domains. To support Azure OpenAI without
configuring it as a custom endpoint, add an `env_gated` entry, e.g.:

```yaml
env_gated:
  AZURE_API_KEY:
    domains: ["*.openai.azure.com"]
```

## CI mode (no secrets)

Pass only the set key NAMES (never values):

```bash
python generate.py --config ../chart/librechat.yaml \
  --namespace librechat --pod-label app.kubernetes.io/name=librechat \
  --env-keys "AZURE_API_KEY,TAVILY_API_KEY" --strict
```

`--strict` exits non-zero when subprocess (`uvx`/`npx`) MCP servers are present.
See the blueprint `../README.md` for the full CI/CD recipe.
