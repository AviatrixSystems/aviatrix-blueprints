# Agent Context: obot-mcp-egress-azure

Deploys Obot on a new AKS cluster with Aviatrix DCF enforcing per-pod FQDN egress at the network layer. No transit gateway required — the spoke gateway is the Policy Enforcement Point. Pod egress is routed via a UDR on the AKS node subnet pointing to the gateway EIP.

Read `README.md` for full documentation. This file provides the fast path for autonomous deployment.

## Required Variables

All variables must be set in `terraform.tfvars` before deploying.

| Variable | How to discover | Example |
|----------|----------------|---------|
| `azure_subscription_id` | Azure portal → Subscriptions → copy Subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `azure_location` | Azure region name — run `az account list-locations -o table` to list valid names | `UK South` |
| `controller_ip` | Aviatrix Controller VM public IP — Azure portal → Virtual machines → search "controller" | `52.1.2.3` |
| `controller_password` | Controller admin password set at install time | (sensitive — never commit to git) |
| `arm_account_name` | Aviatrix Controller UI → Accounts → Azure account name (already onboarded) | `azure-prod` |
| `arm_account_principal_id` | Run: `az ad sp show --id <arm_ad_client_id> --query id -o tsv` where `arm_ad_client_id` is the ARM service principal client ID shown in the Aviatrix Controller Azure account settings | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `copilot_private_ip` | CoPilot VM private IP — Azure portal → Virtual machines → search "copilot" → Networking | `10.0.1.50` |
| `copilot_public_ip` | CoPilot VM public IP — same VM → Overview | `52.2.3.4` |
| `obot_admin_password` | Set any strong password; becomes the Obot admin credential | (sensitive — never commit to git) |

**Non-obvious optional:** `copilot_syslog_index` defaults to `9`. Verify slot 9 is free before applying: Controller UI → Settings → Logging → Remote Syslog → confirm slot 9 is empty.

## Deploy Sequence

```bash
az login
cd blueprints/obot-mcp-egress-azure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill all REQUIRED fields above
terraform init
terraform plan
terraform apply
# Update kubeconfig after apply completes:
az aks get-credentials \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw aks_cluster_name)"
```

Deployment takes 15–20 minutes. Spoke gateway provisioning is the longest step.

## Verification

```bash
# 1. Obot pods running
kubectl get pods -n obot-system
# Expected: obot-* pod 1/1 Running; aviatrix-network-policy-controller-* 1/1 Running

# 2. ip-masq-agent ConfigMap applied (disables pod SNAT — required for per-pod enforcement)
kubectl get configmap azure-ip-masq-agent-config -n kube-system -o jsonpath='{.data.ip-masq-agent}' | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if '0.0.0.0/0' in d.get('nonMasqueradeCIDRs',[]) else 'MISSING')"
# Expected: OK

# 3. Obot API responding
kubectl port-forward -n obot-system svc/obot-obot 8080:80 &
sleep 3
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/mcp-servers
# Expected: 200
```

## Common Errors

```
Error: dc.services.visualstudio.com blocked (appears in DCF Monitor as denied flow)
Cause: AKS Application Insights telemetry — intentionally blocked by default-deny policy
Fix: no action required; AKS functions correctly without this endpoint; this is by design
```

```
Error: terraform destroy hangs on route table association
Cause: Azure prevents deleting route tables still associated with subnets
Fix:
  az network vnet subnet update \
    --name <aks-subnet-name> \
    --vnet-name <vnet-name> \
    --resource-group <resource-group-name> \
    --remove routeTable
  Then re-run: terraform destroy
```

```
Error: SmartGroups show workload_type as VM instead of k8s
Cause: Log Enrichment feature flag not applied
Fix: re-run terraform apply (re-runs null_resource.k8s_dcf_features); verify CoPilot → DCF → Settings → Log Enrichment = On
```

## Constraints

- Azure has no Internet Gateway concept. Pod egress routes via the AKS node subnet UDR → Aviatrix Gateway EIP. The gateway subnet has a direct default route to Internet.
- `dc.services.visualstudio.com` (Azure node telemetry) is intentionally blocked by default-deny. This is expected and correct zero-trust posture.
- `ip-masq-agent` ConfigMap disables pod SNAT for all destinations — required for CoPilot to see pod IPs in DCF Monitor and SmartGroup resolution. Do not remove this ConfigMap.
- Port 31284 (OTEL) must be open inbound on the CoPilot NSG from the spoke gateway public IP — required for DCF Monitor to populate.
- vCPU quota: `Standard_D4s_v3` requires 8 vCPUs for 2 nodes. Verify before deploying: `az vm list-usage --location "<azure_location>" --query "[?contains(name.value,'standardDSv3')]" -o table`.
