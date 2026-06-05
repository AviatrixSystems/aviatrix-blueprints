resource "aviatrix_spoke_gateway" "runner" {
  cloud_type     = 1
  account_name   = var.aviatrix_account_name
  gw_name        = coalesce(var.spoke_gateway_name, "${local.name_prefix}-spoke-gw")
  vpc_id         = aws_vpc.runner.id
  vpc_reg        = var.aws_region
  gw_size        = var.aviatrix_gw_size
  subnet         = var.gw_subnet_cidr
  single_ip_snat = true
  tags           = local.common_tags

  depends_on = [
    aws_subnet.gw,
    aws_route_table_association.gw,
    aws_internet_gateway.this,
  ]
}
