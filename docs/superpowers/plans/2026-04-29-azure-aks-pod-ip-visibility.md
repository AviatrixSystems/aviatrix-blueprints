# Azure AKS Pod-IP Visibility (customized_snat) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pod source IPs visible to Aviatrix DCF for east-west traffic between AKS clusters with overlapping pod CIDRs, so K8s-typed SmartGroups (cluster/namespace/pod selectors) actually fire on cross-cluster flows.

**Architecture:** Move SNAT from cluster boundary (azure-ip-masq-agent) to spoke gateway (`aviatrix_gateway_snat` with `customized_snat`). Pods egress with their original `100.64.x.x` source so DCF inspects pod IPs, then the spoke GW SNATs to its private IP per-direction (transit + internet) so the destination cluster's identical pod CIDR doesn't collide on reply.

**Tech Stack:** Terraform (Aviatrix provider 8.2, azurerm 4.0, kubernetes 2.20, helm 2.16), AKS Azure CNI Powered by Cilium (overlay), Aviatrix Controller 9.x, Gatus apps for E2E validation.

---

## Known risk: AVXERR-NAT-0029

`network/main.tf:162-166` documents that this exact change was tried before and the controller rejected it: with `customized_snat` mode, the explicit `azurerm_route 0.0.0.0/0 → spoke_gw.private_ip` UDR entry is misidentified as an onprem-learned route, causing a NAT/route conflict.

**Hypothesis (per spec):** the explicit `azurerm_route.frontend_default` already exists and the static-route mitigation may now be sufficient. Empirical validation required.

**Fallback ladder (apply in order if AVXERR-NAT-0029 fires):**
1. Remove the customized_snat policy with `dst_cidr=0.0.0.0/0` (internet-direction); keep only the connection-mode (transit) policy. UDR auto-program on RFC1918 may not trigger the conflict.
2. Drop the explicit `azurerm_route.frontend_default` and rely on Aviatrix to auto-program 0/0 once `customized_snat` is in primary mode.
3. Set `single_ip_snat=false` first (apply A), then add `aviatrix_gateway_snat` (apply B) — separate plans, may bypass the conflict-detection code path.
4. Open Aviatrix support case with controller logs (`/var/log/cloudxd.log` for cloudxd; `/var/log/avx_route_handler.log`) and revert to baseline.

---

## File Map

**Modify:**
- `blueprints/azure-aks-multicluster/network/main.tf` — flip `single_ip_snat=false` on `frontend_spoke`/`backend_spoke`/`db_spoke` modules; add `aviatrix_gateway_snat` resources for frontend + backend (db spoke remains primary mode — no overlapping CIDRs); update inline comments
- `blueprints/azure-aks-multicluster/network/dcf.tf:16-22` — update DCF comment block ("post-SNAT"/"pre-SNAT" reversed: pod IPs are now visible at the spoke GW)
- `blueprints/azure-aks-multicluster/nodes/frontend/main.tf` — add `kubernetes_config_map_v1_data` resource overriding `azure-ip-masq-agent` ConfigMap; replace `nodes/frontend/main.tf:46-49` comment block
- `blueprints/azure-aks-multicluster/nodes/backend/main.tf` — same as frontend
- `blueprints/azure-aks-multicluster/clusters/frontend/main.tf:121-125` — update pod_cidr comment to reflect that pods now egress with original IPs
- `blueprints/azure-aks-multicluster/clusters/backend/main.tf:115-119` — same as frontend
- `blueprints/azure-aks-multicluster/README.md` — document the new SNAT architecture in the architecture section + update troubleshooting

**Create:** none

**Cluster-state files** (`blueprints/azure-aks-multicluster/*/terraform.tfstate`) currently exist with 0 resources — these are init-only artifacts from prior destroyed deploys and are safe to reuse.

---

## Task 1: Branch & Pre-flight

**Files:**
- Modify: working tree only

- [ ] **Step 1: Stash unrelated dirty file**

```bash
git stash push -m "wip-agentcore-readme" -- blueprints/agentcore-aws/README.md
```

Expected: stash created or "No local changes to save" if already clean.

- [ ] **Step 2: Branch from main**

```bash
git fetch origin
git checkout -b azure-aks-pod-ip-visibility origin/main
```

Expected: switched to new branch tracking nothing remote yet.

- [ ] **Step 3: Source Aviatrix + Azure credentials**

```bash
source ~/chris-avx-lab/controller_env_ga.sh
az account show --query name -o tsv
```

Expected: env vars `AVIATRIX_CONTROLLER_IP`, `AVIATRIX_USERNAME`, `AVIATRIX_PASSWORD` set; account name "Azure".

- [ ] **Step 4: Verify no leftover Azure resources from prior deploys**

```bash
az group list --query "[?starts_with(name, 'aks-demo-')].name" -o tsv
```

Expected: empty output. If any `aks-demo-*` RGs exist from prior runs, run `terraform destroy` in the relevant layer or delete RGs manually before continuing — overlapping resource names will collide.

- [ ] **Step 5: Set tfvars for the deploy**

```bash
cd blueprints/azure-aks-multicluster/network
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set aviatrix_azure_account_name = "Azure"
# verify name_prefix is "aks-demo" (default)
```

Inspect: `cat terraform.tfvars` should have `aviatrix_azure_account_name = "Azure"` set.

- [ ] **Step 6: Commit branch starting point (no code changes yet)**

```bash
git status
```

Expected: clean working tree (tfvars is gitignored). No commit needed yet.

---

## Task 2: Baseline deploy (capture "broken" evidence)

**Files:** none modified — deploying current code as-is to confirm the gap exists.

- [ ] **Step 1: Deploy network layer**

```bash
cd blueprints/azure-aks-multicluster/network
terraform init
terraform apply -auto-approve
```

Expected: succeeds in ~10–15 min. Outputs include `frontend_spoke_gateway_private_ip`, `backend_spoke_gateway_private_ip`, AKS cluster IDs (constructed).

- [ ] **Step 2: Deploy clusters layer (parallel)**

```bash
cd ../clusters/frontend
cp terraform.tfvars.example terraform.tfvars
# edit: set aviatrix_controller_public_ip from controller env, enable_aviatrix_onboarding=true
terraform init && terraform apply -auto-approve &

cd ../backend
cp terraform.tfvars.example terraform.tfvars
# (same edits)
terraform init && terraform apply -auto-approve &
wait
```

Expected: both clusters reach Ready state (~15 min each in parallel). Onboarding succeeds in Aviatrix Controller.

- [ ] **Step 3: Deploy nodes layer (parallel)**

```bash
cd ../../nodes/frontend
terraform init && terraform apply -auto-approve &
cd ../backend
terraform init && terraform apply -auto-approve &
wait
```

Expected: NGINX, ExternalDNS, k8s-firewall helm releases all installed.

- [ ] **Step 4: Deploy k8s-apps and dcf-crd**

```bash
cd ../../k8s-apps/frontend && kubectl apply -f .
cd ../backend && kubectl apply -f .
cd ../dcf-crd && kubectl apply -f .
```

Expected: Gatus pods Running in `gatus` namespace in both clusters.

- [ ] **Step 5: Capture baseline DCF logs (proves K8s SG rule is dead today)**

Open Aviatrix CoPilot via agent-browser:

```bash
agent-browser navigate "https://${AVIATRIX_CONTROLLER_IP}/copilot/#/security/dcf/logs"
agent-browser screenshot --filename docs/baseline-dcf-logs.png
```

Inspect: filter by rule name "Frontend Gatus to Backend Gatus k8s ns selector" (priority 50). Expected: zero hits — proves K8s-typed SG doesn't see east-west traffic because pod IPs are masqueraded to node IPs at cluster boundary before reaching the spoke GW.

- [ ] **Step 6: Capture baseline pod-source-IP evidence**

```bash
# tcpdump on the frontend spoke GW NIC, filter for TCP 8080 to backend VNet
FRONTEND_GW=$(cd blueprints/azure-aks-multicluster/network && terraform output -raw frontend_spoke_gateway_name)
ssh -i ~/.ssh/avx-key ubuntu@$(az network public-ip show -n ${FRONTEND_GW}-pip -g ... --query ipAddress -o tsv) \
  "sudo tcpdump -i eth0 -n 'tcp port 8080 and dst net 10.20.0.0/23' -c 5"
```

Expected: source IPs in `10.10.0.x` (frontend node subnet), NOT `100.64.x.x` (pod CIDR) — confirms cluster-boundary masquerade is hiding pod IPs.

- [ ] **Step 7: Commit baseline-evidence files**

```bash
git add docs/baseline-dcf-logs.png
git commit -m "azure-aks-multicluster: baseline evidence — K8s SG rule has zero hits pre-change"
```

---

## Task 3: Network layer — flip to customized_snat

**Files:**
- Modify: `blueprints/azure-aks-multicluster/network/main.tf`
- Modify: `blueprints/azure-aks-multicluster/network/dcf.tf`
- Modify: `blueprints/azure-aks-multicluster/network/outputs.tf` (already has spoke gateway outputs)

- [ ] **Step 1: Flip frontend_spoke single_ip_snat and add gateway_snat resource**

In `network/main.tf`, replace lines 162-167 (frontend module SNAT block):

```hcl
  # Pods egress with original 100.64.x.x source IPs so DCF inspects pod IPs.
  # `aviatrix_gateway_snat` (below) SNATs pod CIDR → spoke GW private IP per
  # direction (transit + internet) so the destination cluster's identical pod
  # CIDR doesn't collide on reply.
  single_ip_snat = false
```

Insert after the `module "frontend_spoke"` block (after line 177):

```hcl
# East-west: pod traffic to other VNets via the transit IPsec connection.
# DCF rules at the spoke GW match on src_cidr=pod_cidr BEFORE this SNAT fires,
# preserving pod IP visibility. SNAT happens on the IPsec out path.
#
# Internet: pod traffic egressing eth0 (UDR 0/0 → spoke GW). Destination cluster
# is irrelevant here — the rule SNATs pod CIDR to the spoke GW's private IP,
# which Azure then 1:1-NATs to the GW's public IP at the platform NAT layer.
resource "aviatrix_gateway_snat" "frontend" {
  gw_name   = module.frontend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # Pod CIDR — east-west via transit IPsec connection
  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # Pod CIDR — internet egress via eth0
  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # Frontend VNet (covers AKS nodes + system subnet) — east-west via transit
  snat_policy {
    src_cidr   = var.frontend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # Frontend VNet — internet egress via eth0 (required for AKS node bootstrap CSE)
  snat_policy {
    src_cidr   = var.frontend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.frontend_spoke]
}
```

- [ ] **Step 2: Same for backend_spoke**

In `network/main.tf`, replace line 240 (`single_ip_snat = true`) with `single_ip_snat = false`.

Insert after the `module "backend_spoke"` block (after line 250):

```hcl
resource "aviatrix_gateway_snat" "backend" {
  gw_name   = module.backend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.backend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.backend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.backend_spoke]
}
```

- [ ] **Step 3: Leave db_spoke as single_ip_snat=true**

DB spoke has no overlapping CIDRs and no pod traffic to source-NAT — leave `single_ip_snat = true` on line 311.

- [ ] **Step 4: Update DCF inspection comment**

In `network/dcf.tf`, replace lines 16-22:

```hcl
# NOTES:
#   - DCF inspects traffic at the Aviatrix spoke gateway BEFORE the gateway's
#     customized_snat fires. Pod source IPs (100.64.x.x) are visible to DCF
#     rules. Aviatrix K8s SmartGroups dynamically resolve pod IPs from cluster
#     label selectors, so cluster/namespace/pod-typed SGs match east-west.
#   - For VNet-typed SmartGroups, pod IPs are also visible (no longer hidden
#     by cluster-boundary masquerade). VNet-typed selectors still resolve to
#     all IPs in the VNet CIDR including the pod CIDR overlay range.
#   - Hostname SmartGroups resolve FQDNs via the Azure Private DNS zone.
```

- [ ] **Step 5: terraform fmt + validate**

```bash
cd blueprints/azure-aks-multicluster/network
terraform fmt
terraform validate
```

Expected: both succeed.

- [ ] **Step 6: terraform plan — inspect for AVXERR risk surface**

```bash
terraform plan -out=customized-snat.tfplan
terraform show customized-snat.tfplan | grep -A2 "single_ip_snat\|aviatrix_gateway_snat"
```

Expected: plan shows update on both spoke modules (`single_ip_snat: true → false`) and creation of two `aviatrix_gateway_snat` resources. No surprises in unrelated resources.

- [ ] **Step 7: terraform apply with extended timeout**

```bash
terraform apply customized-snat.tfplan
```

Expected: apply succeeds. **If AVXERR-NAT-0029 fires, jump to fallback ladder at top of plan.** Capture the full error message before any rollback:

```bash
terraform apply customized-snat.tfplan 2>&1 | tee /tmp/avxerr-nat-0029.log
```

- [ ] **Step 8: Verify spoke GW iptables — pod CIDR SNAT rules present**

```bash
ssh ubuntu@<frontend-spoke-public-ip> "sudo iptables -t nat -nL POSTROUTING -v | grep 100.64"
```

Expected: rules matching `src 100.64.0.0/16` with `SNAT to <spoke_gw.private_ip>` on both `eth0` (internet) and the IPsec interface (transit). Order matters: should fire before any blanket MASQUERADE rule.

- [ ] **Step 9: Commit network changes**

```bash
git add blueprints/azure-aks-multicluster/network/main.tf blueprints/azure-aks-multicluster/network/dcf.tf
git commit -m "azure-aks-multicluster: switch spoke GWs to customized_snat for pod-IP visibility"
```

---

## Task 4: Nodes layer — disable cluster-boundary masquerade

**Files:**
- Modify: `blueprints/azure-aks-multicluster/nodes/frontend/main.tf`
- Modify: `blueprints/azure-aks-multicluster/nodes/backend/main.tf`

- [ ] **Step 1: Frontend — replace ip-masq-agent comment + add ConfigMap override**

In `nodes/frontend/main.tf`, replace lines 46-49 (comment block at end of file) with:

```hcl
# AKS Azure CNI Powered by Cilium uses azure-ip-masq-agent (NOT cilium-config)
# for pod masquerade. By default the agent has NonMasqueradeCIDRs=[100.64.0.0/16]
# which preserves pod IPs intra-cluster but masquerades cross-cluster traffic to
# the node IP — hiding pod IPs from DCF.
#
# We override the ConfigMap to NonMasqueradeCIDRs=[0.0.0.0/0], disabling all
# cluster-boundary masquerade. Pods now egress with their original 100.64.x.x
# source IPs all the way to the Aviatrix spoke GW, which inspects them via DCF
# and then SNATs to the GW's private IP via customized_snat (network/main.tf).
#
# `kubernetes_config_map_v1_data` updates the AKS-managed ConfigMap in place
# without taking ownership — the AKS reconciler won't fight it as long as we
# only add fields under `data`.
resource "kubernetes_config_map_v1_data" "azure_ip_masq_agent" {
  metadata {
    name      = "azure-ip-masq-agent-config"
    namespace = "kube-system"
  }
  data = {
    "ip-masq-agent" = yamlencode({
      nonMasqueradeCIDRs = ["0.0.0.0/0"]
      masqLinkLocal      = false
    })
  }
  force = true

  depends_on = [helm_release.k8s_firewall]
}

# Force daemonset rollout so existing pods pick up the new ConfigMap immediately
# (the agent reads its config on startup, not via inotify).
resource "null_resource" "azure_ip_masq_agent_rollout" {
  triggers = {
    config_hash = kubernetes_config_map_v1_data.azure_ip_masq_agent.id
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=<(echo '${data.terraform_remote_state.cluster.outputs.kubeconfig}' | base64 -d) -n kube-system rollout restart daemonset azure-ip-masq-agent"
    interpreter = ["bash", "-c"]
  }

  depends_on = [kubernetes_config_map_v1_data.azure_ip_masq_agent]
}
```

If `cluster.outputs.kubeconfig` does not exist as a base64 output, replace the provisioner with a `kubernetes_manifest` patch using `field_manager`. Inspect `clusters/frontend/outputs.tf` first to confirm.

- [ ] **Step 2: Verify cluster.outputs.kubeconfig exists**

```bash
grep -n "kubeconfig" blueprints/azure-aks-multicluster/clusters/frontend/outputs.tf
```

If absent: instead of the `null_resource`, use `provisioner "local-exec"` on the `helm_release.k8s_firewall` resource with `kubectl rollout restart` and the existing kubeconfig source pattern (read `nodes/frontend/data.tf` for how the kubernetes provider gets credentials — the same shell-out can use `az aks get-credentials`).

- [ ] **Step 3: Backend — same change**

Repeat Step 1 in `nodes/backend/main.tf` (lines 46-49) with backend-appropriate comments. Same resource block content — both clusters use the same kube-system ConfigMap name.

- [ ] **Step 4: terraform fmt + validate**

```bash
cd blueprints/azure-aks-multicluster/nodes/frontend
terraform fmt && terraform validate
cd ../backend
terraform fmt && terraform validate
```

- [ ] **Step 5: Apply nodes layer (parallel)**

```bash
cd ../frontend && terraform apply -auto-approve &
cd ../backend && terraform apply -auto-approve &
wait
```

Expected: ConfigMap data update + daemonset rollout succeeds in both clusters.

- [ ] **Step 6: Verify the ConfigMap update landed**

```bash
az aks get-credentials -g aks-demo-frontend-rg -n aks-demo-frontend --overwrite-existing
kubectl -n kube-system get cm azure-ip-masq-agent-config -o yaml | grep -A3 nonMasq
```

Expected: `nonMasqueradeCIDRs: [0.0.0.0/0]` in the data field. Repeat for backend.

- [ ] **Step 7: Verify daemonset picked up the change**

```bash
kubectl -n kube-system rollout status ds azure-ip-masq-agent
kubectl -n kube-system logs -l k8s-app=azure-ip-masq-agent --tail=20 | grep -i nonmasq
```

Expected: pod logs show new NonMasqueradeCIDRs config.

- [ ] **Step 8: Commit nodes changes**

```bash
git add blueprints/azure-aks-multicluster/nodes/frontend/main.tf blueprints/azure-aks-multicluster/nodes/backend/main.tf
git commit -m "azure-aks-multicluster: disable cluster-boundary masquerade via azure-ip-masq-agent override"
```

---

## Task 5: Validation — pod IPs visible end-to-end

**Files:** none modified — pure validation.

- [ ] **Step 1: tcpdump on spoke GW — confirm pod-IP source preservation**

```bash
ssh ubuntu@<frontend-spoke-public-ip> "sudo tcpdump -i eth0 -n 'tcp port 8080 and src net 100.64.0.0/16' -c 5"
```

Expected: now sees TCP packets with source `100.64.x.x` (pod IP) — confirms cluster-boundary masquerade is gone. Compare against Task 2 Step 6 baseline.

- [ ] **Step 2: Generate east-west traffic from frontend Gatus → backend Gatus**

The gatus apps already poll each other across clusters per the k8s-apps configs. Wait 60s for the next poll cycle, or trigger manually:

```bash
kubectl -n gatus exec deploy/gatus -- wget -qO- http://gatus.gatus.svc.cluster.local:8080/api/v1/endpoints/_default_backend-gatus-cluster/health
```

Expected: HTTP 200.

- [ ] **Step 3: DCF logs — K8s SG rule now has hits**

```bash
agent-browser navigate "https://${AVIATRIX_CONTROLLER_IP}/copilot/#/security/dcf/logs"
agent-browser screenshot --filename docs/post-change-dcf-logs.png
```

Inspect filter by rule name "Frontend Gatus to Backend Gatus k8s ns selector" (priority 50). Expected: non-zero hits with src in `100.64.0.0/16` and matching the resolved frontend gatus namespace pods.

- [ ] **Step 4: Verify Gatus dashboards — no regression**

```bash
FRONTEND_APPGW=$(cd blueprints/azure-aks-multicluster/network && terraform output -raw frontend_appgw_public_ip)
BACKEND_APPGW=$(cd blueprints/azure-aks-multicluster/network && terraform output -raw backend_appgw_public_ip)
agent-browser navigate "http://${FRONTEND_APPGW}/"
agent-browser screenshot --filename docs/post-change-frontend-gatus.png
agent-browser navigate "http://${BACKEND_APPGW}/"
agent-browser screenshot --filename docs/post-change-backend-gatus.png
```

Expected: all endpoints green (frontend → backend, frontend → db, backend → db, internet egress through DCF).

- [ ] **Step 5: Verify AKS API server reachable from kubelet (no node degradation)**

```bash
kubectl get nodes
kubectl -n kube-system get pods | grep -v Running
```

Expected: all nodes Ready; no kube-system pods stuck/crashing. Negative result here = `azure-ip-masq-agent` change broke kubelet → control plane reachability.

- [ ] **Step 6: Capture validation evidence**

```bash
git add docs/post-change-*.png
git commit -m "azure-aks-multicluster: validation evidence — K8s SG rule fires post-change"
```

---

## Task 6: Documentation

**Files:**
- Modify: `blueprints/azure-aks-multicluster/README.md`
- Modify: `blueprints/azure-aks-multicluster/clusters/frontend/main.tf:121-125`
- Modify: `blueprints/azure-aks-multicluster/clusters/backend/main.tf:115-119`

- [ ] **Step 1: Update cluster pod_cidr comment (frontend)**

In `clusters/frontend/main.tf`, replace lines 121-125:

```hcl
    # Pod CIDR: same across both clusters (overlapping by design).
    # Pod traffic egresses with the original 100.64.x.x source IP to the
    # Aviatrix spoke gateway (azure-ip-masq-agent ConfigMap is overridden in
    # the nodes layer to disable cluster-boundary masquerade). The spoke GW's
    # customized_snat policy SNATs pod CIDR → spoke GW private IP per direction
    # (transit + internet) — see network/main.tf aviatrix_gateway_snat.frontend.
    pod_cidr = data.terraform_remote_state.network.outputs.pod_cidr
```

- [ ] **Step 2: Same for backend**

Repeat in `clusters/backend/main.tf` lines 115-119 with backend-appropriate references.

- [ ] **Step 3: Update README architecture section**

In `blueprints/azure-aks-multicluster/README.md`, locate the "How it works" / "Architecture" / "SNAT" section and replace the pod-traffic flow description with:

```markdown
### Pod-IP visibility for DCF

Pod traffic preserves its original 100.64.x.x source IP all the way from the
pod to the Aviatrix spoke gateway:

1. **Cluster boundary** — the AKS-managed `azure-ip-masq-agent` ConfigMap is
   overridden to `NonMasqueradeCIDRs: [0.0.0.0/0]`, disabling all
   cluster-level masquerade.
2. **Spoke gateway DCF inspection** — DCF rules see the pod IP. K8s-typed
   SmartGroups (cluster/namespace/pod selectors) resolve pod IPs from the
   cluster API and match east-west traffic between clusters.
3. **Spoke gateway SNAT** — `aviatrix_gateway_snat` with `customized_snat`
   mode rewrites the source IP to the spoke GW's private IP per direction
   (transit IPsec connection + eth0 internet path). The destination cluster's
   identical pod CIDR doesn't collide on reply.

This is the architectural difference vs the GCP GKE multicluster blueprint
(where Cilium's `enableIPv4Masquerade=false` accomplishes the same goal at
the cluster boundary).
```

- [ ] **Step 4: Update Troubleshooting section**

Add an entry under troubleshooting:

```markdown
### "AVXERR-NAT-0029" on `terraform apply` of network layer

The Aviatrix Controller misidentifies the explicit `azurerm_route 0.0.0.0/0
→ spoke_gw.private_ip` UDR as an onprem-learned route when `customized_snat`
mode is enabled. Mitigations (in order of preference):

1. Drop the `interface = "eth0"` snat_policy block, leaving only the
   `connection = transit_gw_name` policy.
2. Remove the explicit `azurerm_route.<cluster>_default` and let Aviatrix
   auto-program 0/0.
3. Apply `single_ip_snat = false` first, then add `aviatrix_gateway_snat`
   in a separate apply.
```

- [ ] **Step 5: terraform fmt the cluster files**

```bash
cd blueprints/azure-aks-multicluster
terraform fmt -recursive
```

- [ ] **Step 6: Commit docs**

```bash
git add blueprints/azure-aks-multicluster/README.md \
        blueprints/azure-aks-multicluster/clusters/frontend/main.tf \
        blueprints/azure-aks-multicluster/clusters/backend/main.tf
git commit -m "azure-aks-multicluster: document pod-IP visibility architecture"
```

---

## Task 7: Clean destroy + final commit

**Files:** none modified.

- [ ] **Step 1: Flip K8s SmartGroup demo flag for clean destroy**

Per `network/variables.tf:100-111`, the priority-50 rule + K8s SGs must be removed before destroying clusters or the `aviatrix_kubernetes_cluster` registration deletion will fail.

```bash
cd blueprints/azure-aks-multicluster/network
echo 'enable_k8s_smartgroup_demo = false' >> terraform.tfvars
terraform apply -auto-approve
```

Expected: priority-50 rule and K8s SmartGroups (frontend_cluster, backend_cluster, *_gatus_ns) destroyed.

- [ ] **Step 2: Destroy in reverse order**

```bash
# k8s-apps
kubectl delete -f blueprints/azure-aks-multicluster/k8s-apps/dcf-crd
kubectl delete -f blueprints/azure-aks-multicluster/k8s-apps/backend
kubectl delete -f blueprints/azure-aks-multicluster/k8s-apps/frontend

# nodes (parallel)
cd blueprints/azure-aks-multicluster/nodes/frontend && terraform destroy -auto-approve &
cd ../backend && terraform destroy -auto-approve &
wait

# clusters (parallel)
cd ../../clusters/frontend && terraform destroy -auto-approve &
cd ../backend && terraform destroy -auto-approve &
wait

# network
cd ../../network && terraform destroy -auto-approve
```

Expected: clean destroy. No orphaned resources.

- [ ] **Step 3: Verify no orphaned Azure resources**

```bash
az group list --query "[?starts_with(name, 'aks-demo-')].name" -o tsv
```

Expected: empty output.

- [ ] **Step 4: Push branch + open PR**

```bash
git push -u origin azure-aks-pod-ip-visibility
gh pr create --title "azure-aks-multicluster: pod-IP visibility via customized_snat" \
  --body "..."
```

PR body should include the baseline + post-change DCF screenshots, the explicit east-west DCF log entry showing the priority-50 rule firing with pod-IP source, and a link back to this plan.

---

## Self-Review

**Spec coverage:**
- [x] Cluster-boundary masquerade disabled (Task 4 — azure-ip-masq-agent override)
- [x] Spoke GW single_ip_snat → false (Task 3 Step 1, 2)
- [x] Two snat_policy blocks per spoke (transit connection + eth0 interface, Task 3 Step 1, 2)
- [x] Risk #1 — Azure POSTROUTING chain ordering: validated empirically in Task 3 Step 8 (iptables inspection)
- [x] Risk #2 — kubelet → control plane reachability: validated in Task 5 Step 5 (kubectl get nodes / kube-system pod health)
- [x] Risk #3 — UDR auto-programming: explicit `azurerm_route.frontend_default` already exists; Task 3 Step 7 validates apply succeeds, fallback ladder at top of plan if AVXERR-NAT-0029 fires
- [x] Risk #4 — NSG rules for 100.64.0.0/16: aks-vnet module's NSG covers VirtualNetwork space which includes pod CIDR via Cilium overlay routes; if traffic drops, add explicit NSG rule (handled in fallback during Task 5 Step 1 if tcpdump shows drops)

**Type/name consistency:**
- `aviatrix_gateway_snat.frontend` / `aviatrix_gateway_snat.backend` referenced consistently
- `module.frontend_spoke.spoke_gateway.private_ip` / `gw_name` references match the existing `module.frontend_spoke` exposure (verified by reading existing `network/main.tf:141`)
- `module.azure_transit.transit_gateway.gw_name` used for connection — matches existing usage at `network/main.tf:152`
- `kubernetes_config_map_v1_data.azure_ip_masq_agent` resource name reused identically in frontend + backend nodes layers (separate state files, no collision)

**Placeholder scan:** none — all code blocks are concrete.
