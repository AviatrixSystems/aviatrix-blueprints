# Testing Guide — AWS Self-Hosted Runner + Aviatrix DCF

This guide walks through a hands-on security test that demonstrates how
Aviatrix Distributed Cloud Firewall (DCF) controls egress from a GitHub
Actions self-hosted runner running on an EC2 instance in an AWS spoke VPC.

**Scenario:** the workflow simulates two concurrent behaviours from the same
runner:

- **Legitimate access** — the runner fetches a "message of the day" from
  `www.example.com`, representing a normal dependency call that should be
  permitted.
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
| Self-hosted runner deployed | `aws-self-hosted-runner` blueprint applied; runner shows **online** in `Settings → Actions → Runners` |
| Free webhook endpoint | Visit [webhook.site](https://webhook.site), copy your unique URL |
| Aviatrix CoPilot access | Browser access to CoPilot, logged in with DCF read/write permissions |

---

## Initial DCF rule state

After deployment the runner has five DCF policies in the global Distributed
Firewalling policy list (priorities 10–50):

| Priority | Name | Action | Scope |
|---|---|---|---|
| 10 | `deny-*-threat-group` | DENY (enforced) | Runner EC2 → Aviatrix ThreatIQ feed |
| 20 | `allow-*-github` | PERMIT | Runner EC2 → GitHub FQDNs (TCP 443) |
| 30 | `allow-*-tool-calls` | PERMIT | Runner EC2 → `www.example.com` (TCP 80/443) |
| 40 | `allow-*-linux-setup` | PERMIT | Runner EC2 → Ubuntu APT FQDNs (TCP 80/443) |
| **50** | **`deny-*-unmatched-web`** | **DENY + watch** | Runner EC2 → All-Web (TCP 80/443) |

> **Key:** rule 50 uses `watch = true`. In Aviatrix DCF, **watch mode means
> observe without enforce** — traffic matching this rule is **logged but
> allowed through**. This is intentional for the first phase: you want to
> see the exfil succeed so you have a baseline in the logs before tightening
> the policy.

---

## Step 1 — Run the PII exfiltration test (expect it to succeed)

1. Go to **Actions** → **Test PII Exfiltration (self-hosted runners)**.
2. Click **Run workflow** and fill in:
   - **webhook\_url** — paste your webhook.site URL
   - **cloud** — `aws`
   - **retries** — `3`
3. Click **Run workflow**.

### Expected result

Both steps succeed:

- **MOTD fetch** (`www.example.com`) → ✅ HTTP 200 — matched by rule 30.
- **PII POST** to `webhook.site` → ✅ all 3 retries succeed — matched by
  rule 50 (watch, no enforcement).

Step summary:

```
### MOTD (https://www.example.com)
✅ MOTD fetch HTTP 200 — www.example.com reachable

### PII exfil test (aws)
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

## Step 2 — Verify DCF logs (traffic logged by rule 50 watch)

1. Open **CoPilot** → **Security** → **Distributed Cloud Firewall** → **Logs**.
2. Filter:
   - **Source SmartGroup** = `gh-runner-*-vm`
   - **Rule** = `deny-*-unmatched-web` (priority 50)
   - **Time range** = last 15 minutes

You should see log entries for the three POST attempts to `webhook.site`:

| Field | Expected value |
|---|---|
| Rule name | `deny-<prefix>-unmatched-web` |
| Source | Runner EC2 IP (`10.20.10.x`) |
| Destination | `webhook.site` IP |
| Protocol / port | TCP 443 |
| Action | DENY (watch — not enforced) |

---

## Step 3 — Switch rule 50 to hard DENY in CoPilot UI

1. Go to **Security** → **Distributed Cloud Firewall** → **Policy**.
2. Find rule priority **50** (`deny-*-unmatched-web`).
3. Click **Edit**.
4. Set **Watch Mode** → **Off**.
5. Click **Save** / **Commit**.

Rule 50 is now a hard DENY — traffic is dropped without generating a watch
log entry.

---

## Step 4 — Re-run and confirm blocked exfil

1. Return to **Actions** → **Test PII Exfiltration (self-hosted runners)**.
2. Run the same workflow (same webhook URL, cloud=aws, retries=3).

### Expected result

- **MOTD fetch** (`www.example.com`) → ✅ HTTP 200 — rule 30 still permits it.
- **PII POST** to `webhook.site` → ❌ all 3 retries fail — hard DENY.

**webhook.site shows no new requests.**

---

## Step 5 — Confirm in DCF logs

1. Return to CoPilot → **Logs**, same filter.
2. **No new log entries** for `webhook.site` — hard DENY does not generate
   watch entries.
3. Check **hit count** on rule 50 in the policy list — incremented by the
   three blocked attempts.

---

## Cleanup

```bash
cd aws-self-hosted-runner
terraform destroy
```

The destroy provisioner best-effort unregisters the runner from GitHub. If
the runner row lingers as "offline", delete it manually under
`Settings → Actions → Runners`.

---

## Summary

| Phase | www.example.com | webhook.site POST | Rule 50 behaviour |
|---|---|---|---|
| Steps 1–2 (DENY+watch) | ✅ allowed (rule 30) | ✅ **allowed + logged** | Observe without enforce |
| Steps 4–5 (hard DENY) | ✅ allowed (rule 30) | ❌ **blocked, silent** | Hard drop, no log entry |
