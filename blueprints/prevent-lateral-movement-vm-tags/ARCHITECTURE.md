# Architecture Deep Dive — Prevent Lateral Movement - VM Tags

This document explains every component deployed by this blueprint, how they connect, and why each decision was made. Read this before a customer demo call.

---

## Big Picture

The blueprint proves one thing: **a compromised workload in one environment cannot reach workloads in another environment** — even though they share the same Aviatrix transit network.

It does this using **Aviatrix Distributed Cloud Firewall (DCF)** with **SmartGroups** — a tag-based policy engine that classifies workloads automatically and enforces Zero Trust without security group sprawl.

---

## Component Map

```
┌─────────────────────────────────────────────────────┐
│                Aviatrix Control Plane                │
│  ┌──────────────┐        ┌──────────────────────┐   │
│  │  Controller  │◄──────►│       CoPilot        │   │
│  │  (Terraform/ │        │  (Topology, DCF UI,  │   │
│  │   API)       │        │   FlowIQ, Monitor)   │   │
│  └──────┬───────┘        └──────────────────────┘   │
│         │ manages via API                            │
└─────────┼───────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────┐
│                    AWS (us-east-1)                   │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │            Transit VPC (10.0.0.0/23)         │    │
│  │     ┌────────────────────────────────┐       │    │
│  │     │  Aviatrix Transit Gateway      │       │    │
│  │     │  (plm-transit-gw, t3.small)    │       │    │
│  │     └───┬─────────────┬─────────┬───┘       │    │
│  └─────────┼─────────────┼─────────┼───────────┘    │
│            │             │         │                  │
│     ┌──────┘      ┌──────┘  ┌──────┘                 │
│     ▼             ▼         ▼                         │
│  Dev VPC      Prod VPC    DB VPC                     │
│  10.1.0.0/24  10.2.0.0/24 10.3.0.0/24               │
│  Spoke GW     Spoke GW    Spoke GW                   │
│  Dev VM       Prod VM     DB VM                      │
│  EICE         EICE+Gatus  EICE                       │
└─────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Aviatrix Controller (pre-existing prerequisite)

**What it is:** The management plane for all Aviatrix resources. Terraform talks to the Controller API to create gateways, SmartGroups, and DCF policies.

**What it does in this blueprint:**
- Receives Terraform API calls to create/manage all Aviatrix resources
- Orchestrates gateway deployment in AWS
- Stores and enforces DCF policy configuration
- Manages SmartGroup membership in real time

> **DCF is managed by this blueprint.** `terraform apply` enables DCF; `terraform destroy` disables it. If your Controller has other active DCF policies you want to preserve, remove the `aviatrix_distributed_firewalling_config` resource from `dcf.tf` before running `terraform destroy`.

**What to show in the demo:** The Controller itself is mostly invisible during the demo — everything is shown in CoPilot. Mention it exists as the management plane.

---

### 2. Aviatrix CoPilot (pre-existing prerequisite)

**What it is:** The GUI for visualization, monitoring, and day-2 operations. Accessed through the Controller — click the CoPilot link in the top navigation bar.

**Key views for the demo:**

| CoPilot View | Navigation | What to show |
|---|---|---|
| Topology | Cloud Fabric > Topology | Hub-and-spoke architecture — all gateways connected |
| SmartGroups | Security > DCF > SmartGroups | Tag-based groups with VM membership |
| DCF Rules | Security > DCF > Rules | All 5 policies with priority order |
| DCF Monitor | Security > DCF > Monitor | Live PERMITTED/DENIED traffic entries |

---

### 3. Transit VPC + Aviatrix Transit Gateway

**What it is:** The central hub of the hub-and-spoke network. All spoke-to-spoke traffic passes through here.

**CIDR:** `10.0.0.0/23`
**Gateway size:** `t3.small`
**Key settings:**
- `enable_segmentation = true` — required for DCF to evaluate traffic between spokes
- `connected_transit = true` — allows spoke-to-spoke connectivity through the transit

**Why it matters:** Without the transit gateway, the three spoke VPCs would be isolated islands. The transit gateway connects them AND gives DCF a point to evaluate and enforce policy on all cross-VPC traffic.

---

### 4. Spoke Gateways + VPCs (Dev, Prod, DB)

**What they are:** Three spoke VPCs, each with an Aviatrix Spoke Gateway attached to the Transit Gateway.

| Spoke | VPC CIDR | Purpose |
|-------|----------|---------|
| Dev | 10.1.0.0/24 | Development workloads (less trusted) |
| Prod | 10.2.0.0/24 | Production workloads (business-critical) |
| DB | 10.3.0.0/24 | Database workloads (most sensitive) |

**Each VPC contains:**
- Public subnet (for the gateway)
- Private subnet (for test VMs)
- Internet Gateway (for gateway internet access)
- Route tables directing cross-VPC traffic through the Aviatrix gateway

**How traffic flows:** When the Dev VM tries to ping the DB VM, the traffic goes:
`Dev VM → Dev Spoke Gateway → Transit Gateway → DB Spoke Gateway → DB VM`

At the Transit Gateway, DCF intercepts and evaluates the traffic against the policy list. If no PERMIT rule matches, the `default-deny-all` policy at priority 1000 drops it.

---

### 5. DCF SmartGroups

**What they are:** Dynamic, tag-based groupings of workloads. When a VM has a matching tag, it's automatically classified into the SmartGroup — no manual IP management.

| SmartGroup | Tag Selector | Members |
|---|---|---|
| `dev-smartgroup` | `Environment=development` | Dev test VM |
| `prod-smartgroup` | `Environment=production` | Prod test VM + Gatus monitoring VM |
| `db-smartgroup` | `Environment=database` | DB test VM |

**Why tags instead of IPs:** New workloads tagged `Environment=production` instantly inherit all production policies. No engineer needs to update a security group or firewall rule. This is the automation story — *tag once, secured forever.*

**What to show in demo:** Click into a SmartGroup to show the tag selector, then show the VM members list. The key message: "This is how Zero Trust scales — policy follows the workload, not the IP address."

---

### 6. DCF Policies

Five policies, evaluated in priority order (lowest number = evaluated first):

| Priority | Policy | Source | Destination | Protocol | Action | Why |
|---|---|---|---|---|---|---|
| 100 | `allow-prod-to-db` | prod | db | ANY | PERMIT | Production legitimately needs to read/write the database |
| 110 | `allow-dev-to-prod-read-only` | dev | prod | ICMP only | PERMIT | Dev can ping prod for diagnostics — TCP is blocked |
| 200 | `deny-dev-to-db` | dev | db | ANY | DENY | **The key Zero Trust control** — dev cannot reach production data |
| 210 | `deny-prod-to-dev` | prod | dev | ANY | DENY | Compromised production cannot pivot to dev environment |
| 1000 | `default-deny-all` | ANY | ANY | ANY | DENY | Zero Trust baseline — nothing is trusted by default |

**Priority evaluation:** The first matching policy wins. Traffic from dev to db hits priority 200 (DENY) before reaching the default-deny at 1000. Traffic from prod to db hits priority 100 (PERMIT) immediately.

**Watch mode:** The `deny-dev-to-db` policy has `watch = true` — this highlights it in CoPilot DCF Monitor so you can easily see it fire during the demo.

---

### 7. Test VMs

Three `t3.micro` EC2 instances (Amazon Linux 2), one per spoke VPC, deployed in private subnets.

**Private IP assignment:** IPs are pinned at deploy time (10th host in the private subnet) so Gatus can reference them without waiting for DHCP assignment.

**Tags:** Each VM is tagged `Environment=<environment>` — this is what puts them into the correct SmartGroup automatically.

**Security groups:** SSH is restricted — no `0.0.0.0/0` access. Dev and prod VMs accept SSH only from their EC2 Instance Connect Endpoint security group. DB VM accepts SSH only from within its VPC CIDR.

---

### 8. EC2 Instance Connect Endpoints (EICE)

**What they are:** AWS-managed tunnels that let you SSH into private EC2 instances using only your existing AWS credentials — no bastion host, no public IP, no key file management.

**Deployed for:** All three spoke VPCs — Dev, Prod, and DB. All test VMs are reachable via EC2 Instance Connect for manual test scenarios.

**How to use:**
```bash
aws ec2-instance-connect ssh --instance-id <instance-id> --region us-east-1
```

**Security model:**
- EICE has its own security group (`eice-sg`) that allows only outbound SSH (port 22) to the spoke VPC CIDR
- Test VM security groups allow SSH ingress only from the EICE security group — no direct internet SSH possible
- The EICE itself authenticates using your AWS IAM identity (not a password or key)

**Why this matters for the demo:** SEs can SSH into any test VM from their laptop with a single command, without needing to manage key pairs or a bastion host. This makes running live test scenarios on a customer call frictionless.

---

### 9. Gatus Live Dashboard

**What it is:** An open-source monitoring tool running in a Docker container on a `t3.micro` EC2 instance in the Prod VPC. Exposed publicly via an Application Load Balancer — no SSH required to view it.

**What it monitors:**

| Probe | From | To | Protocol | Expected | Why |
|---|---|---|---|---|---|
| G1 | Gatus (prod) | DB VM | ICMP | 🟢 GREEN | `allow-prod-to-db` — legitimate traffic |
| G2 | Gatus (prod) | DB VM | TCP:5432 | 🟢 GREEN | `allow-prod-to-db` — database port permitted end-to-end |
| G3 | Gatus (prod) | Dev VM | ICMP | 🔴 RED | `deny-prod-to-dev` — lateral movement blocked |
| G4 | Gatus (prod) | Dev VM | TCP:22 | 🔴 RED | `default-deny-all` — default deny catches everything else |

**Why Gatus is in the Prod SmartGroup:** The Gatus VM is tagged `Environment=production` so it's classified into `prod-smartgroup`. This means the `allow-prod-to-db` policy applies — Gatus probes can reach the DB VM and show GREEN. If it were tagged differently and unclassified, `default-deny-all` would block all its probes.

**Gatus gap:** Policies 110 and 200 (dev-originated traffic) can't be covered by Gatus because Gatus only runs in the prod spoke. Manual SSH from the dev VM is required for those two policies.

**Demo tip:** Open the Gatus URL in a browser tab before the call. Leave it running — the audience watches live enforcement in real time with no commands needed. One green tile (legitimate traffic) and two red tiles (lateral movement blocked) tell the whole story visually.

---

## How It All Connects — Traffic Flow Example

**Scenario: Attacker compromises Dev VM, tries to reach DB**

```
1. Dev VM (10.1.0.74) sends ICMP to DB VM (10.3.0.74)
2. Traffic enters Dev Spoke Gateway
3. Dev Spoke Gateway forwards to Transit Gateway
4. DCF at Transit Gateway evaluates against policy list:
   - Priority 100 (allow-prod-to-db): source is dev, not prod → SKIP
   - Priority 110 (allow-dev-to-prod-read-only): dest is db, not prod → SKIP
   - Priority 200 (deny-dev-to-db): source is dev ✓, dest is db ✓ → DENY ✓
5. Traffic is dropped. DCF Monitor logs a DENIED entry.
6. Gatus dashboard: no change (Gatus is in prod, not dev)
7. Manual test: ping times out from dev VM
```

**Customer message:** "The attacker is stopped at the network fabric — not at the destination host. There's nothing to compromise at the DB because the traffic never arrives."

---

## Deployment Time Breakdown

| Phase | Duration | What happens |
|---|---|---|
| VPC + Subnet creation | ~1 min | AWS networking resources |
| Transit Gateway deployment | ~3–5 min | Aviatrix gateway in transit VPC |
| Spoke Gateway deployment (×3, parallel) | ~3–5 min | Three gateways deploy in parallel |
| Transit-Spoke attachments | ~1 min | Routing established |
| DCF + SmartGroups + Policies | ~30 sec | Policy configuration via Controller API |
| Test VMs + Gatus + ALB | ~2 min | EC2 instances and load balancer |
| Gatus startup (Docker) | ~3–5 min | After apply — wait before opening dashboard |
| **Total** | **~15 min** | |

---

## What's NOT Deployed (By Design)

| Item | Why not |
|---|---|
| CoPilot | Pre-existing prerequisite — the Controller can only associate one CoPilot at a time |
| NAT Gateway | Not needed — gateways have public IPs via EIPs |
| VPN / Direct Connect | Out of scope for this demo |
| HA Gateways | Demo environment — HA can be enabled via `transit_gateway.ha_enabled = true` variable |
| Multi-region | Single region demo — Aviatrix DCF works identically across regions and clouds |
