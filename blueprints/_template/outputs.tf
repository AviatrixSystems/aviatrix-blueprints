# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# -----------------------------------------------------------------------------
# Aviatrix Outputs
# -----------------------------------------------------------------------------

# output "spoke_gateway_name" {
#   description = "Name of the Aviatrix Spoke Gateway"
#   value       = aviatrix_spoke_gateway.example.gw_name
# }

# output "spoke_gateway_public_ip" {
#   description = "Public IP of the Aviatrix Spoke Gateway"
#   value       = aviatrix_spoke_gateway.example.eip
# }

# -----------------------------------------------------------------------------
# Test Instance Outputs
# -----------------------------------------------------------------------------

# output "test_instance_id" {
#   description = "ID of the test EC2 instance"
#   value       = aws_instance.test.id
# }

# output "test_instance_public_ip" {
#   description = "Public IP of the test EC2 instance"
#   value       = aws_instance.test.public_ip
# }

# output "test_instance_private_ip" {
#   description = "Private IP of the test EC2 instance"
#   value       = aws_instance.test.private_ip
# }

# -----------------------------------------------------------------------------
# Connection Information
# -----------------------------------------------------------------------------

# output "ssh_command" {
#   description = "SSH command to connect to the test instance"
#   value       = "ssh -i <your-key.pem> ec2-user@${aws_instance.test.public_ip}"
# }

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    region      = var.aws_region
    name_prefix = var.name_prefix
    vpc_id      = aws_vpc.main.id
    vpc_cidr    = aws_vpc.main.cidr_block
  }
}
