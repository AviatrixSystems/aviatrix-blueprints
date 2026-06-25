locals {
  name = var.name_prefix

  public_subnet_cidr = cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, 0)
  private_subnet_cidrs = [
    for i in range(var.availability_zone_count) : cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, i + 10)
  ]

  # AWS VPC resolver convention: base address + 2. It is explicitly permitted
  # before the external DNS deny rules so normal VPC DNS continues to work.
  vpc_dns_resolver_ip   = cidrhost(var.vpc_cidr, 2)
  vpc_dns_resolver_cidr = "${local.vpc_dns_resolver_ip}/32"

  # Aviatrix built-in anywhere group used by existing Aviatrix blueprint examples
  # for WebGroup destinations.
  aviatrix_anywhere_uuid = "def000ad-0000-0000-0000-000000000001"

  deny_like_action    = var.policy_mode == "enforce" ? "DENY" : "PERMIT"
  default_deny_action = var.policy_mode == "enforce" ? "DENY" : "PERMIT"

  create_package_webgroup      = var.enable_package_installs && length(var.package_registry_domains) > 0
  create_public_ref_webgroup   = var.enable_public_reference && length(var.public_reference_domains) > 0
  create_saas_webgroup         = length(var.approved_saas_api_domains) > 0
  create_mcp_webgroup          = length(var.approved_mcp_gateway_domains) > 0
  create_identity_webgroup     = length(var.identity_and_telemetry_domains) > 0
  create_model_webgroup        = length(var.approved_model_gateway_domains) > 0
  create_shadow_model_webgroup = length(var.unapproved_model_provider_domains) > 0
  create_os_update_webgroup    = length(var.os_update_domains) > 0

  # Region-specific AWS infrastructure endpoints. Additional organization-specific
  # AWS domains can be appended through var.aws_infra_domains.
  aws_infra_domains = distinct(concat([
    "ec2.${var.aws_region}.amazonaws.com",
    "ssm.${var.aws_region}.amazonaws.com",
    "ssmmessages.${var.aws_region}.amazonaws.com",
    "ec2messages.${var.aws_region}.amazonaws.com",
    "logs.${var.aws_region}.amazonaws.com",
    "sts.${var.aws_region}.amazonaws.com",
    "sts.amazonaws.com",
    "s3.${var.aws_region}.amazonaws.com",
    "s3.amazonaws.com",
    "*.s3.amazonaws.com",
    "*.s3.${var.aws_region}.amazonaws.com",
    "ecr.${var.aws_region}.amazonaws.com",
    "api.ecr.${var.aws_region}.amazonaws.com",
    "*.dkr.ecr.${var.aws_region}.amazonaws.com"
  ], var.aws_infra_domains))

  ssm_interface_endpoint_services = toset([
    "ssm",
    "ssmmessages",
    "ec2messages",
    "logs",
    "sts"
  ])

  model_domain_conflicts = setintersection(
    toset(var.approved_model_gateway_domains),
    toset(var.unapproved_model_provider_domains)
  )

  common_tags = merge(var.tags, {
    NamePrefix = local.name
    AgentClass = var.agent_class
  })
}
