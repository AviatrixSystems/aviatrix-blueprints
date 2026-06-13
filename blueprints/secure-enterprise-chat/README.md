# Secure Enterprise Chat

Deploy **LibreChat** onto an **already-running, Aviatrix-protected Kubernetes
cluster** and enforce least-privilege egress with the Aviatrix Distributed Cloud
Firewall (DCF). This blueprint is **not** a cluster builder — it layers a chat
app onto a cluster you already stood up with one of the Kubernetes blueprints
(e.g. `azure-aks-singlecluster`, `aws-eks-singlecluster`).

It is, deliberately, **really just a Helm chart**:

- a **values overlay** for the **official** LibreChat chart (official container
  images, no custom build, no vendored application source),
- the app config (`librechat.yaml`) and a secret template (`.env.example`),
- a **translator shim** that turns `librechat.yaml` into an Aviatrix
  `FirewallPolicy` CRD so egress is allowed only to the backends you configured,
- and three ways to apply it: raw Helm, an optional thin Terraform wrapper, or
  ArgoCD/GitOps.

## Architecture

```
  Existing Aviatrix-protected cluster (built by a base k8s blueprint)
  ┌───────────────────────────────────────────────────────────────┐
  │  ns: librechat                                                  │
  │   ┌─────────────┐   in-cluster    ┌───────────┐ ┌────────────┐ │
  │   │  LibreChat  │◄───────────────►│  MongoDB  │ │ MeiliSearch│ │
  │   │   (API pod) │                 └───────────┘ └────────────┘ │
  │   └──────┬──────┘  app.kubernetes.io/name=librechat            │
  │          │ external egress (TCP 443)                           │
  └──────────┼──────────────────────────────────────────────────  │
             ▼
      Aviatrix spoke gateway  ──  DCF evaluates the FirewallPolicy CRD
             │                     (permit listed domains, deny the rest)
             ▼
      Bedrock / Azure OpenAI / image registries / approved integrations
```

The base blueprint already provides: the cluster, the Aviatrix spoke gateway
with DCF **default-deny** egress, and the **Aviatrix CRD controller** (K8s
SmartGroup onboarding). This blueprint adds the workload and a `FirewallPolicy`
CRD that the controller reconciles into live DCF rules scoped to the LibreChat
pod. Nothing here is permitted to egress until it appears in that policy.

## What's in this folder

| Path | Purpose |
|---|---|
| `chart/values.yaml` | Overlay for the official LibreChat chart (pins the official image, ingress, deps). |
| `chart/librechat.yaml` | App config **and** the single source of truth for the egress allowlist. |
| `chart/.env.example` | Template for the `librechat-credentials-env` Secret (AI creds, JWT/CREDS keys). |
| `egress-policy/` | The translator shim: `generate.py` + `egress-catalog.yaml`. Produces the `FirewallPolicy` CRD. |
| `argocd/application.yaml` | Example ArgoCD Application (multi-source) for GitOps deploys. |
| `main.tf`, `variables.tf`, `versions.tf`, `outputs.tf` | **Optional** thin Terraform `helm_release` wrapper. |

> No LibreChat application source is vendored here. The chart pulls
> `registry.librechat.ai/danny-avila/librechat`.

## Prerequisites

### Already deployed
- A Kubernetes blueprint cluster with **DCF egress default-deny** and the
  **Aviatrix K8s CRD controller** onboarded (any singlecluster blueprint; the
  multicluster blueprints also work per-cluster). Confirm the cluster shows
  fully onboarded (not "Partial") in CoPilot before relying on CRD enforcement.

### Required tools
- `kubectl`, configured for the target cluster
- `helm` >= 3.8 (OCI support) — for the raw-Helm path
- `python3` + `pip` — for the egress-policy shim (`pip install -r egress-policy/requirements.txt`)
- `terraform` >= 1.5 — only for the optional TF wrapper

## Deploy

### Step 1 — Create the credentials Secret

```bash
cd blueprints/secure-enterprise-chat
cp chart/.env.example chart/.env
# edit chart/.env: set CREDS_KEY/CREDS_IV/JWT_*/MEILI_MASTER_KEY and your AI creds
kubectl create namespace librechat 2>/dev/null || true
kubectl -n librechat create secret generic librechat-credentials-env \
  --from-env-file=chart/.env
```

### Step 2 — Generate and apply the egress FirewallPolicy

The policy is derived from `chart/librechat.yaml`. Note the `--pod-label`: the
chart labels the pod `app.kubernetes.io/name=librechat`.

```bash
pip install -r egress-policy/requirements.txt
python egress-policy/generate.py \
  --config chart/librechat.yaml \
  --env chart/.env \
  --namespace librechat \
  --pod-label app.kubernetes.io/name=librechat \
  --output egress-policy/firewall-policy.yaml

kubectl apply -f egress-policy/firewall-policy.yaml
```

Review the generated file first — it lists exactly which domains will be
permitted. Anything not listed stays denied by the base cluster's DCF.

### Step 3 — Install the chart (pick ONE)

**A) Raw Helm**

```bash
helm install librechat oci://ghcr.io/danny-avila/librechat-chart/librechat \
  --version 2.0.2 \
  --namespace librechat --create-namespace \
  -f chart/values.yaml \
  --set-file librechat.configYamlContent=chart/librechat.yaml \
  --set ingress.hosts[0].host=chat.example.com
```

**B) Terraform wrapper**

```bash
cp terraform.tfvars.example terraform.tfvars   # set kube_context, ingress_host
terraform init
terraform apply
```

**C) ArgoCD / GitOps** — see [`argocd/application.yaml`](argocd/application.yaml)
and the GitOps section below.

All three consume the **same** `chart/values.yaml` + `chart/librechat.yaml`.

## CI/CD integration

The egress policy must be regenerated whenever `chart/librechat.yaml` (or the
catalog) changes, so the allowlist never drifts from the running config. This
repo ships the shim but **not** a workflow — wire it into your pipeline. Run the
generator with `--env-keys` so secret *values* never touch CI (only key names):

```yaml
# .github/workflows/secure-enterprise-chat-egress.yml (reference)
name: secure-enterprise-chat-egress
on:
  push:
    paths:
      - blueprints/secure-enterprise-chat/chart/librechat.yaml
      - blueprints/secure-enterprise-chat/egress-policy/egress-catalog.yaml
jobs:
  generate:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - run: pip install -r blueprints/secure-enterprise-chat/egress-policy/requirements.txt
      - name: Derive set env keys from secrets
        id: keys
        run: |
          KEYS=""
          [ -n "${{ secrets.AZURE_API_KEY }}" ] && KEYS="$KEYS,AZURE_API_KEY"
          [ -n "${{ secrets.TAVILY_API_KEY }}" ] && KEYS="$KEYS,TAVILY_API_KEY"
          echo "keys=${KEYS#,}" >> "$GITHUB_OUTPUT"
      - run: |
          python blueprints/secure-enterprise-chat/egress-policy/generate.py \
            --config blueprints/secure-enterprise-chat/chart/librechat.yaml \
            --namespace librechat --pod-label app.kubernetes.io/name=librechat \
            --env-keys "${{ steps.keys.outputs.keys }}" \
            --output blueprints/secure-enterprise-chat/egress-policy/firewall-policy.yaml \
            --strict
      - name: Commit regenerated policy
        run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add blueprints/secure-enterprise-chat/egress-policy/firewall-policy.yaml
          git diff --cached --quiet || git commit -m "chore: regenerate LibreChat egress FirewallPolicy"
          git push
```

`--strict` fails the build if subprocess (`uvx`/`npx`) MCP servers are present
(they can't be domain-isolated in-pod — use the Aviatrix OBOT VCA instead).

## GitOps: a standalone app repo

Because `chart/` and `egress-policy/` are self-contained, you can lift them into
their own app repo and let ArgoCD/Flux drive everything:

1. Copy `chart/` + `egress-policy/` into a new repo.
2. Point [`argocd/application.yaml`](argocd/application.yaml) `repoURL` at it.
3. Have CI regenerate `firewall-policy.yaml` on config change (above) and sync
   it as a second, tiny ArgoCD Application (directory source).
4. The loop becomes: edit `librechat.yaml` → CI regenerates the CRD → Argo syncs
   both the chart and the policy. Config and its firewall posture move together.

## Variables (Terraform wrapper)

| Variable | Default | Description |
|---|---|---|
| `kubeconfig_path` | `~/.kube/config` | kubeconfig for the existing cluster |
| `kube_context` | `""` | context for the target cluster (empty = current) |
| `namespace` | `librechat` | install namespace (match the policy `--namespace`) |
| `release_name` | `librechat` | keep as `librechat` to preserve the pod label |
| `chart_version` | `2.0.2` | official LibreChat chart version |
| `ingress_host` | `chat.example.com` | ingress hostname |

## Outputs (Terraform wrapper)

| Output | Description |
|---|---|
| `release_name` | Installed Helm release name |
| `namespace` | Install namespace |
| `chart_version` | Installed chart version |
| `pod_label_selector` | The label the FirewallPolicy must select (`--pod-label`) |

## Test Scenarios

### Scenario 1: Permitted backend reaches its target
Open a chat against a configured backend (e.g. Bedrock). It responds. In CoPilot
→ Security → DCF → Monitor, the flow to `bedrock-runtime.<region>.amazonaws.com`
shows **permitted** against the `librechat-egress` policy.

### Scenario 2: Default-deny blocks the unlisted
From the LibreChat pod, attempt egress to a domain not in the policy:
```bash
kubectl -n librechat exec deploy/librechat -- \
  curl -sS --max-time 5 https://example.org || echo "blocked as expected"
```
It is denied; the drop is visible in DCF Monitor.

### Scenario 3: Config change tightens/loosens the policy
Remove the `bedrock` block from `chart/librechat.yaml`, regenerate
(Step 2), `kubectl apply`, and confirm Bedrock egress is now denied — the
allowlist tracks the config exactly.

## Cleanup

```bash
# Chart
helm uninstall librechat -n librechat        # or: terraform destroy
# Egress policy
kubectl delete -f egress-policy/firewall-policy.yaml
# Secret + namespace
kubectl -n librechat delete secret librechat-credentials-env
kubectl delete namespace librechat
```

The base cluster (and its DCF default-deny) is left intact — tear it down with
its own blueprint when finished.

## Troubleshooting

**Policy doesn't match the pod / no enforcement.** The selector must equal the
pod label. The chart uses `app.kubernetes.io/name: librechat` (from
`fullnameOverride`). If you changed the release name, regenerate with
`--pod-label app.kubernetes.io/name=<release>`. Verify:
`kubectl -n librechat get pod -l app.kubernetes.io/name=librechat`.

**Pods stuck pulling images / app can't start.** Image pulls happen on the node;
ensure the base blueprint permits node egress to the image registries. Runtime
pod egress to registries is covered by the catalog's `always_on` domains.

**LibreChat crashes on boot.** Confirm the `librechat-credentials-env` Secret
exists in the namespace and contains `CREDS_KEY`, `CREDS_IV`, `JWT_SECRET`,
`JWT_REFRESH_SECRET`, and `MEILI_MASTER_KEY`.

**Azure OpenAI egress denied.** The generator parses `endpoints.custom[].baseURL`,
not the first-class `azureOpenAI` block. Configure Azure as a custom endpoint
(see `chart/librechat.yaml`) or add an `env_gated` entry for `AZURE_API_KEY` →
`*.openai.azure.com` in `egress-policy/egress-catalog.yaml`.

**CRD not reconciled.** Confirm the base cluster shows fully onboarded (not
"Partial") in CoPilot and the Aviatrix CRD controller is healthy.

## Tested With

| Component | Version |
|---|---|
| LibreChat chart | 2.0.2 (appVersion v0.8.4) |
| Aviatrix Controller | 8.1+ (FQDN SmartGroups); 9.0+ for path-level filtering |
| Helm | 3.8+ |
| Terraform (wrapper) | >= 1.5, hashicorp/helm ~> 2.17 |
| Base blueprint | azure-aks-singlecluster (dev target); any singlecluster |
