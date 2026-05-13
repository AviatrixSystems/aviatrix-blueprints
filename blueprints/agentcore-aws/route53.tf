# =============================================================================
# Shared Route 53 Private Hosted Zones for the AgentCore regional hostnames.
#
# We register the hostname of each PrivateLink service as its own PHZ, with
# an apex ALIAS A record pointing at the interface VPC endpoint. The PHZ is
# associated with BOTH the AgentCore spoke VPC (so the agent runtime reaches
# the endpoint for any AWS SDK calls) and the client spoke VPC (so the
# invoker EC2's InvokeAgentRuntime calls resolve to the private endpoint).
#
# Aviatrix FQDN SmartGroups also use these names - the gateway's DNS
# resolver, configured to use the VPC resolver, will see the private IPs
# because the VPC is associated with the PHZ.
# =============================================================================

# -----------------------------------------------------------------------------
# Data plane: bedrock-agentcore.<region>.amazonaws.com
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "agentcore_data" {
  name = local.agentcore_data_host

  vpc {
    vpc_id = aws_vpc.agentcore.id
  }

  lifecycle {
    # Associations are managed by separate resources below
    ignore_changes = [vpc]
  }

  tags = {
    Name = "${local.name_prefix}-phz-agentcore-data"
  }
}

resource "aws_route53_zone_association" "agentcore_data_client" {
  zone_id = aws_route53_zone.agentcore_data.zone_id
  vpc_id  = aws_vpc.client.id
}

resource "aws_route53_record" "agentcore_data_apex" {
  zone_id = aws_route53_zone.agentcore_data.zone_id
  name    = local.agentcore_data_host
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.agentcore_data.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.agentcore_data.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# -----------------------------------------------------------------------------
# Control plane: bedrock-agentcore-control.<region>.amazonaws.com
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "agentcore_control" {
  name = local.agentcore_control_host

  vpc {
    vpc_id = aws_vpc.agentcore.id
  }

  lifecycle {
    ignore_changes = [vpc]
  }

  tags = {
    Name = "${local.name_prefix}-phz-agentcore-control"
  }
}

resource "aws_route53_zone_association" "agentcore_control_client" {
  zone_id = aws_route53_zone.agentcore_control.zone_id
  vpc_id  = aws_vpc.client.id
}

resource "aws_route53_record" "agentcore_control_apex" {
  zone_id = aws_route53_zone.agentcore_control.zone_id
  name    = local.agentcore_control_host
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.agentcore_control.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.agentcore_control.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}
