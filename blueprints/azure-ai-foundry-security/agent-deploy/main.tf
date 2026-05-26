# ══════════════════════════════════════════════════════════════════════════════
# Agent Deploy — Build & push rogue-agent-sample to ACR
# Deploy step intentionally omitted — use VSCode Foundry extension or
# uncomment the azapi_resource block below when ready to automate.
# ══════════════════════════════════════════════════════════════════════════════

locals {
  agent_src = "${path.module}/../rogue-agent-sample"
  image_uri = "${local.acr_name}.azurecr.io/${var.image_name}:${var.image_tag}"
}

# ── Build & push image via ACR Tasks (no local Docker needed) ─────────────────

resource "null_resource" "build_agent_image" {
  triggers = {
    source_hash = sha256(join("", [
      filesha256("${local.agent_src}/main.py"),
      filesha256("${local.agent_src}/Dockerfile"),
      filesha256("${local.agent_src}/requirements.txt"),
      filesha256("${local.agent_src}/agent.yaml"),
    ]))
  }

  provisioner "local-exec" {
    working_dir = local.agent_src
    command     = <<-EOT
      az acr build \
        --registry ${local.acr_name} \
        --image ${var.image_name}:${var.image_tag} \
        --platform linux/amd64 \
        --file Dockerfile \
        --subscription ${local.subscription_id} \
        .
    EOT
  }
}

