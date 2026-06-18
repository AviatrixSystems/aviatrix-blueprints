# Feature: Onboard AKS Clusters with the Aviatrix Controller

> Status: **Implemented.** See `clusters/{frontend,backend}/onboarding.tf`, `network/dcf-k8s.tf`, and the README's "AKS Cluster Onboarding" section under *How It Works*. This document is preserved as the original design discussion; **the README is the source of truth for the deployed behavior**, including a few corrections to the spec below.
>
> Spec deltas (corrected during implementation):
> - **No AAD/Entra integration.** The Aviatrix DCF docs ([8.2 K8s onboarding](https://docs.aviatrix.com/docs/enterprise/8.2/guides/security/dcf/kubernetes-onboard#azure-aks)) require Kubernetes RBAC with local accounts; Entra-only auth is unsupported because the kubeconfig returned by ARM contains `exec` entries the controller can't process.
> - **No in-cluster `view-nodes` ClusterRole.** The kubeconfig from `listClusterUserCredential/action` is admin-equivalent; the AWS-EKS in-cluster RBAC pattern is not needed on Azure.
> - **No per-cluster role assignment.** Subscription-scoped Contributor on the Aviatrix Azure access account already covers the required ARM action.

## Background

After deploying the blueprint, **CoPilot → Cloud Workloads → Kubernetes Clusters** lists `aks-demo-frontend` and `aks-demo-backend` as **Onboarded: No**. They're discovered (because the VNets are managed by Aviatrix) but the controller isn't reading the cluster API. Consequence: all SmartGroups in `network/dcf.tf` use **VPC/VNet** selectors instead of the richer Kubernetes-typed selectors (`k8s_cluster_id`, `k8s_namespace`, `k8s_pod`, `k8s_service`). The k8s-firewall Helm chart we install handles **CRD-side** policy (FirewallPolicy, WebgroupPolicy authored as Kubernetes manifests), but it does **not** onboard the cluster as a Smart-Group source — that's a separate `aviatrix_kubernetes_cluster` registration with credentials the controller can use to call the AKS API.

The AWS analog (`blueprints/aws-eks-multicluster`) already does this. Once onboarded:

- DCF rules can target individual pods, namespaces, or services
- SmartGroup membership becomes dynamic — pods come and go and the controller updates the data plane
- The Gatus internal probes can use namespace/pod selectors instead of CIDR

## Reference: how AWS-EKS does it (template to adapt)

Two pieces of code in `aws-eks-multicluster/modules/eks-cluster/main.tf`:

```hcl
resource "aviatrix_kubernetes_cluster" "this" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  cluster_id          = module.eks.cluster_arn
  use_csp_credentials = true

  depends_on = [module.eks]
}
```

…plus an EKS access entry granting the **Aviatrix Controller IAM role** (`var.aviatrix_controller_role_arn`) cluster access, and an in-cluster `view-nodes` ClusterRole + binding so the controller can list pods/services/nodes.

```hcl
resource "aws_eks_access_entry" "aviatrix_controller" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = var.aviatrix_controller_role_arn
  kubernetes_groups = ["view-nodes"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "aviatrix_controller" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = var.aviatrix_controller_role_arn
  access_scope { type = "cluster" }
}

resource "kubernetes_cluster_role" "view_nodes" { ... }
resource "kubernetes_cluster_role_binding" "view_nodes" { ... }
```

EKS uses **IAM Roles for Service Accounts (IRSA)**: the Aviatrix Controller has an IAM role, that role is added as an EKS access entry with the `AmazonEKSViewPolicy`, and the access entry is bound to a Kubernetes group that has a custom `view-nodes` ClusterRole.

## What's different on Azure

Azure has no equivalent of EKS access entries. The integration models are:

| Mechanism | How it works | Suitability |
|---|---|---|
| **Service principal + kubeconfig** | Azure SP authenticates against AKS API via `az aks get-credentials`, kubeconfig holds the token | What the controller likely uses today |
| **Workload Identity / federated credentials** | Federated identity bound to the Aviatrix Controller's principal | More secure but requires the controller to be running in Azure (it's not — it's in AWS) |
| **AKS-managed AAD with RBAC** | Cluster has AAD integration enabled; AAD principal granted Kubernetes Cluster Reader role | Closest analog to the AWS access entry pattern; works regardless of where the controller runs |

Cleanest path for this blueprint: **AAD-integrated AKS + Azure RBAC role assignment** giving the Aviatrix Controller's principal `Azure Kubernetes Service RBAC Reader` (or `Cluster Admin` if pod listing requires it) on each cluster. This avoids managing kubeconfigs as Terraform-managed credentials.

**Open question for implementation:** what credential does the controller's `aviatrix_kubernetes_cluster` resource consume on Azure? The Terraform provider documentation needs a careful read — the AWS path uses `use_csp_credentials = true` which leans on the onboarded Azure account. If the same flag works on Azure (controller picks up the SP from the onboarded account and uses it to reach AKS), the Terraform side is much simpler than EKS. Otherwise, an explicit `kube_config` argument may be required.

## Reference docs to consult

The implementer should read these before writing code:

1. **Aviatrix DCF for Kubernetes — Onboard Cluster (Azure section)** — the live docs at https://docs.aviatrix.com under DCF → Kubernetes Clusters. Specifically what the controller needs to authenticate against AKS, and whether managed-identity or SP credentials are stored on the controller.
2. **Aviatrix Terraform provider — `aviatrix_kubernetes_cluster`** — argument schema, particularly the difference between `use_csp_credentials` and explicit credential args.
3. **AKS AAD integration / Azure RBAC for Kubernetes Authorization** — Microsoft Learn:
   - https://learn.microsoft.com/azure/aks/azure-ad-integration-cli
   - https://learn.microsoft.com/azure/aks/manage-azure-rbac
4. **Aviatrix Controller's Azure access account** — what subscription/RG scope it has on `var.aviatrix_azure_account_name`. Onboarding an AKS cluster inside that subscription should reuse those credentials, not require new ones.

## Proposed scope (what the implementation work covers)

### 1. Network layer — no change

Cluster onboarding is a per-cluster concern. Network layer stays as-is.

### 2. `clusters/{frontend,backend}/main.tf`

Add (toggleable via a variable, default `true`):

```hcl
variable "enable_aviatrix_onboarding" {
  description = "Register this AKS cluster with the Aviatrix Controller so DCF SmartGroups can target k8s namespaces, pods, and services"
  type        = bool
  default     = true
}
```

Enable AAD integration on the cluster:

```hcl
resource "azurerm_kubernetes_cluster" "aks" {
  # ...existing config...

  # Enable AAD integration so the controller can authenticate as an AAD principal
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    # admin_group_object_ids can stay empty for lab; cluster-admin is granted via RBAC
  }
}
```

Grant the Aviatrix Controller's SP a read role on the cluster:

```hcl
data "azurerm_client_config" "current" {}

# Aviatrix Controller's SP object ID — sourced from the Aviatrix Azure access account.
# Likely needs a new variable on the network layer to expose this.
variable "aviatrix_controller_principal_id" {
  description = "Object ID of the AAD principal the Aviatrix Controller uses to call Azure APIs"
  type        = string
}

resource "azurerm_role_assignment" "aviatrix_controller_aks_reader" {
  count                = var.enable_aviatrix_onboarding ? 1 : 0
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = var.aviatrix_controller_principal_id
}
```

If a custom RBAC role is needed for pod/node visibility analogous to the AWS `view-nodes` ClusterRole, add it as a `kubernetes_cluster_role` + binding.

Register the cluster:

```hcl
resource "aviatrix_kubernetes_cluster" "this" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  cluster_id          = azurerm_kubernetes_cluster.aks.id
  use_csp_credentials = true   # confirm this path works for Azure; otherwise pass kube_config

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_role_assignment.aviatrix_controller_aks_reader,
  ]
}
```

### 3. New input: controller principal ID

Two options:

- **Variable input** — operator pastes the controller's SP/managed identity object ID into `terraform.tfvars`. Simple, explicit, but a manual step.
- **Data source** — query the Aviatrix Controller API for the access account's `arm_ad_client_id`, then look up the SP object ID via `azuread_service_principal`. Fully derived but requires the `azuread` provider and login as someone who can read AAD.

Recommend variable input for v1; revisit derivation later.

### 4. Convert SmartGroups to K8s selectors

Once clusters are onboarded, replace VPC selectors in `network/dcf.tf`:

```hcl
# Before
resource "aviatrix_smart_group" "frontend_vnet" {
  name = "${var.name_prefix}-sg-frontend-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-frontend-vnet"
    }
  }
}

# After
resource "aviatrix_smart_group" "frontend_cluster" {
  name = "${var.name_prefix}-sg-frontend-cluster"
  selector {
    match_expressions {
      k8s_cluster_id = "${var.name_prefix}-frontend"   # or the AKS resource ID
    }
  }
}
```

Optionally add finer SmartGroups demonstrating the new capability:

```hcl
resource "aviatrix_smart_group" "gatus_pods" {
  name = "${var.name_prefix}-sg-gatus-pods"
  selector {
    match_expressions {
      k8s_namespace = "gatus"
      k8s_pod       = "app=frontend"   # or app=backend
    }
  }
}
```

DCF rules would then target `gatus_pods` instead of the whole VNet — much closer to a production Zero-Trust posture.

### 5. README updates

- Add an "AKS Cluster Onboarding" section under "How It Works" explaining the Azure-vs-AWS difference and the AAD/RBAC flow
- Update the variables table with the new `aviatrix_controller_principal_id`
- Update test scenarios to use the K8s-typed SmartGroups
- Mention this in the architecture diagram (controller now has a read path into the cluster)

## Acceptance criteria

- [ ] CoPilot → Cloud Workloads → Kubernetes Clusters shows both clusters as **Onboarded: Yes** with namespace/service/pod counts populated
- [ ] At least one DCF rule in the ruleset targets a `k8s_namespace` or `k8s_pod` SmartGroup and is observed enforcing in FlowIQ
- [ ] `terraform destroy` cleanly removes the role assignment and the `aviatrix_kubernetes_cluster` resource (no orphaned controller-side records)
- [ ] Toggle still works: setting `enable_aviatrix_onboarding = false` skips all the new resources without breaking the cluster apply
- [ ] CI `validate-blueprint` still verdicts READY FOR QA

## Risks / unknowns to investigate first

1. **Does `use_csp_credentials = true` work for Azure?** If not, the implementer needs to thread a kubeconfig through to the `aviatrix_kubernetes_cluster` resource. The provider doc has the answer.
2. **What principal does the controller actually use to call AKS?** The onboarded Azure access account has `arm_ad_client_id = 5d078f14-e51e-42f8-9fa9-4b84b72ddd1e` (visible via the Aviatrix `list_accounts` API). That's the principal that needs the RBAC role — but confirm before granting.
3. **Is AAD integration disruptive on an existing cluster?** Enabling `azure_rbac_enabled` on a live cluster may require a control-plane update. Plan the apply order: onboarding additions go in last so any roll happens after the cluster is otherwise stable.
4. **Does the AKS API authorized_ip_ranges allowlist need to include the controller's egress IP?** The current allowlist is the operator's IP plus the spoke GW public IP. The controller (running in AWS on a different egress) will get blocked unless its IP is added.
5. **Private DCF SmartGroups for hostnames** — currently "doesn't resolve private FQDNs" is a known limitation because `enable_vpc_dns_server` is OFF. K8s-service SmartGroups would side-step that limitation by referencing the K8s service name directly. Worth noting in the README.

## Out of scope for this feature

- Changing the spoke GW SNAT mode
- Re-enabling `enable_vpc_dns_server`
- Migrating from `single_ip_snat` to per-pod-CIDR `customized_snat`
- Adding pod-level NetworkPolicy (Calico/Cilium-native) — different layer

## Branching

A starter branch is already created and pushed: **`feat/azure-aks-cluster-onboarding`** (off the post-#35 main). The implementation work can pick this up directly.
