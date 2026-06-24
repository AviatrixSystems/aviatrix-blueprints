# =============================================================================
# Plan-time safety guardrails
# =============================================================================
# Terraform check blocks are useful for operator visibility, but preconditions on
# this null_resource make unsafe policy combinations fail the plan/apply.

resource "null_resource" "policy_guardrails" {
  triggers = {
    policy_mode  = var.policy_mode
    install_mode = var.install_mode
  }

  lifecycle {
    precondition {
      condition     = length(local.model_domain_conflicts) == 0
      error_message = "A domain appears in both approved_model_gateway_domains and unapproved_model_provider_domains. Deny rules have higher priority; remove it from one list."
    }

    precondition {
      condition     = !(var.enable_tls_decryption_design && var.single_ip_snat)
      error_message = "Aviatrix TLS decryption designs should not be combined with single_ip_snat=true. Set single_ip_snat=false before adding TLS decryption."
    }

    precondition {
      condition     = !(var.single_ip_snat && var.program_private_default_route)
      error_message = "single_ip_snat=true already programs the private VPC default route via the egress Spoke Gateway ENI; also enabling program_private_default_route is rejected by the controller (AVXERR-TRANSIT-EDIT-0056). Set program_private_default_route=false."
    }

    precondition {
      condition     = !(var.auto_run_installer && contains(["nemoclaw", "hermes"], var.install_mode) && !var.auto_accept_third_party_software)
      error_message = "auto_run_installer=true with install_mode=nemoclaw/hermes requires auto_accept_third_party_software=true. Default is manual review via SSM."
    }

    precondition {
      condition     = !(var.policy_mode == "enforce" && var.install_bootstrap_packages)
      error_message = "install_bootstrap_packages=true is not safe with policy_mode=enforce unless you have private HTTPS package mirrors already allow-listed. Start in monitor mode or use a baked AMI."
    }
  }
}
