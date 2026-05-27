# =============================================================================
# UI rule catalog — generated from terraform state at apply time.
#
# The agentcore-aws UI server reads /opt/agentcore-ui/rules.json to render
# the "DCF rule" / "IAM policy" block on each scenario card. We render that
# file here so the UI's catalog cannot drift from the actual policies that
# terraform applied.
#
# Only the rules referenced by scenario cards are exported. New scenarios that
# reference new rules need to add entries here too.
# =============================================================================

locals {
  # Explicit catalog keyed by rule name. We don't iterate the live
  # aviatrix_distributed_firewalling_policy_list.main.policies because:
  #   (a) the list order is sensitive to additions in dcf.tf
  #   (b) the provider doesn't expose all the human-friendly fields we want
  #       (e.g., SmartGroup names — only their UUIDs are on policy objects)
  # So we restate the structured fields here in HCL. The single source of
  # truth for the rule contents remains dcf.tf / iam.tf; this catalog just
  # mirrors them for the UI to render.
  ui_rules_catalog = {
    "${var.name_prefix}-29-runtime-deny-supply-chain-ioc-github" = {
      type             = "dcf"
      name             = "${var.name_prefix}-29-runtime-deny-supply-chain-ioc-github"
      priority         = 29
      action           = "DENY"
      protocol         = "TCP"
      port_ranges      = ["443"]
      src_smart_groups = ["runtime-subnet (${aws_subnet.agentcore_runtime.cidr_block})"]
      dst_smart_groups = ["github_hosts (FQDN raw.githubusercontent.com, github.com)"]
      web_groups       = ["supply_chain_ioc_github (URL-path patterns)"]
      decrypt_policy   = "DECRYPT_ALLOWED"
      logging          = true
      watch            = false
    }
    "${var.name_prefix}-50-runtime-dns-exfil-deny" = {
      type             = "dcf"
      name             = "${var.name_prefix}-50-runtime-dns-exfil-deny"
      priority         = 50
      action           = "DENY"
      protocol         = "UDP"
      port_ranges      = ["53"]
      src_smart_groups = ["runtime-subnet (${aws_subnet.agentcore_runtime.cidr_block})"]
      dst_smart_groups = ["any (catch-all)"]
      decrypt_policy   = null
      logging          = true
      watch            = false
    }
    "${var.name_prefix}-100-runtime-default-deny" = {
      type             = "dcf"
      name             = "${var.name_prefix}-100-runtime-default-deny"
      priority         = 100
      action           = "DENY"
      protocol         = "ANY"
      src_smart_groups = ["runtime-subnet (${aws_subnet.agentcore_runtime.cidr_block})"]
      dst_smart_groups = ["any (catch-all)"]
      decrypt_policy   = null
      logging          = true
      watch            = false
    }
    "${var.name_prefix}-vpc-mode-guardrail" = {
      type        = "iam"
      name        = "${var.name_prefix}-vpc-mode-guardrail"
      effect      = "DENY"
      action      = "bedrock-agentcore-control:CreateAgentRuntime"
      resource    = "arn:aws:bedrock-agentcore:*:*:runtime/*"
      condition   = "Null on bedrock-agentcore:subnets OR ForAnyValue:StringNotEquals on approved subnets"
      attached_to = "platform-eng / ci-cd / human-admin roles"
    }
  }
}

# Render the catalog to disk so the existing aws_s3_object in ui.tf can
# upload it. Keeping the file in path.module/ui/rules.json mirrors the
# layout the EC2 user_data expects.
resource "local_file" "ui_rules_json" {
  filename        = "${path.module}/ui/rules.json"
  content         = jsonencode(local.ui_rules_catalog)
  file_permission = "0644"
}
