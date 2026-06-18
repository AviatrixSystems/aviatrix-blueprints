# Testing Guide — Azure ARC + Aviatrix DCF

This guide walks through a hands-on security test that demonstrates how
Aviatrix Distributed Cloud Firewall (DCF) controls egress from GitHub Actions
workflow jobs running on ARC (Actions Runner Controller) pods inside an AKS
cluster in an Azure spoke VNet.

**Scenario:** the workflow simulates two concurrent behaviours from the same
ARC runner pod:

- **Legitimate access** — the runner fetches `www.example.com` (HTTP 200
  check), representing a normal dependency call that should be permitted.
- **Compromised dependency / supply-chain attack** — a malicious package
  silently POSTs PII (SSN, credit card, email, etc.) to an external webhook
  collector (`webhook.site`), representing data exfiltration that should
  ultimately be blocked.

The test shows how DCF can distinguish between the two, allow the first, and
block the second — with a CoPilot-only policy change, no redeployment required.

You will:

1. Run a simulated PII exfiltration workflow — traffic is **allowed and
   logged** by the catch-all DENY+watch rule (watch mode observes without
   enforcing).
2. Confirm the exfil POST reached the webhook and the traffic appears in
   CoPilot DCF logs.
3. Switch rule 50 from **watch** to **enforce** (hard DENY) via the
   Aviatrix CoPilot UI.
4. Re-run the workflow and confirm the exfiltration POST is now dropped —
   nothing reaches the webhook.

---

## Prerequisites

| Requirement | Detail |
|---|---|
| ARC blueprint deployed | `azure-action-runner-controller` blueprint applied; `terraform output arc_runner_label` shows the runner scale set name (e.g. `azure-arc`) |
| Free webhook endpoint | Visit [webhook.site](https://webhook.site), copy your unique URL |
| Aviatrix CoPilot access | Browser access to CoPilot, logged in with DCF read/write permissions |

> **ARC runner count note:** ARC scales to zero when idle (`minRunners = 0`).
> No runner pod appears in GitHub until a workflow job is queued — this is
> expected. The first job may take ~30 s longer while ARC spins up the pod.

---

## How the security probes relate to runner jobs

Two always-on probe pods run alongside the ARC runner and validate that the
same DCF rules apply to both pods and to workflow jobs:

| Probe | Namespace | Target | DCF rule |
|---|---|---|---|
| `ipify-probe` | `arc-runners` | `https://www.example.com` | Prio 30 — FQDN allow (SNI filter) |
| `tls-probe` | `arc-tls-probe` | `https://ipinfo.io/json` | Prio 25 — URL allow + `DECRYPT_ALLOWED` |

When `ipify-probe` logs `OK` and `tls-probe` returns a JSON response,
DCF policy is correctly in place before running the exfil workflow.

---

## Initial DCF rule state

After deployment the ARC runner pods have six DCF policies in the global
Distributed Firewalling policy list (priorities 5–50):

| Priority | Name | Action | Scope |
|---|---|---|---|
| 5 | `allow-*-arc-systems` | PERMIT | `arc-systems` pods → GitHub FQDNs (TCP 443) |
| 10 | `deny-*-threat-group` | DENY (enforced) | Runner pods → Aviatrix ThreatIQ feed |
| 20 | `allow-*-github` | PERMIT | Runner pods → GitHub FQDNs (TCP 443) |
| 25 | `allow-*-tls-probe-decrypt` | PERMIT + DECRYPT_ALLOWED | TLS-probe pod → `ipinfo.io/json` (TCP 443) |
| 30 | `allow-*-tool-calls` | PERMIT | Runner pods → `www.example.com` (TCP 80/443) |
| 40 | `allow-*-linux-setup` | PERMIT | Runner pods → Ubuntu APT / container registries (TCP 80/443) |
| **50** | **`deny-*-unmatched-web`** | **DENY + watch** | Runner pods → All-Web (TCP 80/443) |

> **Key:** rule 50 uses `watch = true`. In Aviatrix DCF, **watch mode means
> observe without enforce** — traffic matching this rule is **logged but
> allowed through**. This is intentional for the first phase: you want to
> see the exfil succeed so you have a baseline in the logs before tightening
> the policy.

---

## Step 1 — Validate probes before running the test

Check that both probes are running correctly:

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# ipify-probe — should print OK every 10s
kubectl logs -n arc-runners deployment/ipify-probe --tail=5

# tls-probe — should print JSON with an IP in the Azure range
kubectl logs -n arc-tls-probe deployment/tls-probe --tail=5
```

Expected output for `ipify-probe`:
```
10:15:01 OK
10:15:11 OK
```

Expected output for `tls-probe`:
```json
{
  "ip": "48.x.x.x",
  "city": "Amsterdam",
  "org": "AS8075 Microsoft Corporation",
  ...
}
```

The IP returned by `tls-probe` should be an Azure/Microsoft-owned address —
this confirms the spoke GW's SNAT is active and TLS decryption is working
(GW decrypts the session to match the URL path, then re-encrypts toward the origin).

---

## Step 2 — Run the PII exfiltration test (expect it to succeed)

1. Go to **Actions** → **Test PII Exfiltration (ARC / AKS runners)**.
2. Click **Run workflow** and fill in:
   - **webhook\_url** — paste your webhook.site URL
   - **retries** — `3`
3. Click **Run workflow**.

### Expected result

Both steps succeed:

- **`www.example.com` fetch** → ✅ HTTP 200 — matched by rule 30.
- **PII POST** to `webhook.site` → ✅ all 3 retries succeed — matched by
  rule 50 (watch, no enforcement).

Step summary:

```
### www.example.com reachability check
✅ HTTP 200 — www.example.com reachable

### PII exfil test (arc)
| Attempt | Result  | HTTP | Time   |
|---------|---------|------|--------|
| 1       | ✅ PASS  | 200  | 312ms  |
| 2       | ✅ PASS  | 200  | 298ms  |
| 3       | ✅ PASS  | 200  | 305ms  |

Result: 3/3 succeeded
```

Check **webhook.site** — you should see three incoming requests with the fake
PII payload (SSN, credit card, email, etc.).

---

## Step 3 — Verify DCF logs (traffic logged by rule 50 watch)

1. Open **CoPilot** → **Security** → **Distributed Cloud Firewall** → **Logs**.
2. Filter:
   - **Source SmartGroup** = `*-runner-pods` (the k8s SmartGroup for the `arc-runners` namespace)
   - **Rule** = `deny-*-unmatched-web` (priority 50)
   - **Time range** = last 15 minutes

You should see log entries for the three POST attempts to `webhook.site`:

| Field | Expected value |
|---|---|
| Rule name | `deny-<prefix>-unmatched-web` |
| Source | Runner pod IP (an IP from the AKS subnet, e.g. `10.10.30.x`) |
| Destination | `webhook.site` IP |
| Protocol / port | TCP 443 |
| Action | DENY (watch — not enforced) |

---

## Step 4 — Switch rule 50 to hard DENY in CoPilot UI

1. Go to **Security** → **Distributed Cloud Firewall** → **Policy**.
2. Find rule priority **50** (`deny-*-unmatched-web`).
3. Click **Edit**.
4. Set **Watch Mode** → **Off**.
5. Click **Save** / **Commit**.

Rule 50 is now a hard DENY — traffic is dropped without generating a watch
log entry.

---

## Step 5 — Re-run and confirm blocked exfil

1. Return to **Actions** → **Test PII Exfiltration (ARC / AKS runners)**.
2. Run the same workflow (same webhook URL, retries=3).

### Expected result

- **`www.example.com` fetch** → ✅ HTTP 200 — rule 30 still permits it.
- **PII POST** to `webhook.site` → ❌ all 3 retries fail (connection timeout) — hard DENY.

**webhook.site shows no new requests.**

---

## Step 6 — Confirm in DCF logs

1. Return to CoPilot → **Logs**, same filter.
2. **No new log entries** for `webhook.site` — hard DENY does not generate
   watch entries.
3. Check **hit count** on rule 50 in the policy list — incremented by the
   three blocked attempts.

---

## Cleanup

Pre-destroy state cleanup required — k8s/helm providers cannot connect to a deleted AKS cluster:

```bash
cd azure-action-runner-controller

# 1. Remove k8s/helm resources from state
terraform state rm helm_release.arc_controller
terraform state rm helm_release.arc_runner_scaleset
terraform state rm kubernetes_namespace.tls_probe[0]
terraform state rm kubernetes_secret.aviatrix_ca[0]
terraform state rm kubernetes_deployment.tls_probe[0]
terraform state rm kubernetes_deployment.ipify_probe[0]
terraform state rm kubernetes_config_map.disable_snat
terraform state rm kubernetes_annotations.restart_masq_agent

# 2. Destroy remaining infrastructure
terraform destroy
```

---

## Summary

| Phase | www.example.com | webhook.site POST | Rule 50 behaviour |
|---|---|---|---|
| Steps 2–3 (DENY+watch) | ✅ HTTP 200 (rule 30) | ✅ **allowed + logged** | Observe without enforce |
| Steps 5–6 (hard DENY) | ✅ HTTP 200 (rule 30) | ❌ **blocked, silent** | Hard drop, no log entry |
