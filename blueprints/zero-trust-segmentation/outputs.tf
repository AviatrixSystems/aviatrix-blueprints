output "transit_gateway_name" {
  description = "Name of the Aviatrix Transit Gateway"
  value       = aviatrix_transit_gateway.main.gw_name
}

output "transit_gateway_id" {
  description = "ID of the Aviatrix Transit Gateway"
  value       = aviatrix_transit_gateway.main.id
}

output "spoke_gateways" {
  description = "Map of spoke gateway names"
  value = {
    for k, v in aviatrix_spoke_gateway.spokes : k => v.gw_name
  }
}

output "spoke_vpc_ids" {
  description = "Map of spoke VPC IDs"
  value = {
    for k, v in aws_vpc.spokes : k => v.id
  }
}

output "test_vm_private_ips" {
  description = "Private IP addresses of test VMs"
  value = {
    for k, v in aws_instance.test_vms : k => v.private_ip
  }
}

output "test_vm_ids" {
  description = "Instance IDs of test VMs"
  value = {
    for k, v in aws_instance.test_vms : k => v.id
  }
}

output "smartgroup_uuids" {
  description = "UUIDs of created SmartGroups"
  value = {
    dev  = aviatrix_smart_group.dev.uuid
    prod = aviatrix_smart_group.prod.uuid
    db   = aviatrix_smart_group.db.uuid
  }
}

output "test_scenarios" {
  description = "Test scenarios to validate segmentation"
  value = {
    scenario_1 = {
      name        = "Dev trying to access DB (SHOULD BE BLOCKED)"
      source      = "dev-test-vm (${aws_instance.test_vms["dev"].private_ip})"
      destination = "db-test-vm (${aws_instance.test_vms["db"].private_ip})"
      expected    = "FAIL - Connection should be denied by DCF"
      test_command = "ping ${aws_instance.test_vms["db"].private_ip}"
    }
    scenario_2 = {
      name        = "Prod accessing DB (SHOULD BE ALLOWED)"
      source      = "prod-test-vm (${aws_instance.test_vms["prod"].private_ip})"
      destination = "db-test-vm (${aws_instance.test_vms["db"].private_ip})"
      expected    = "SUCCESS - Connection should be permitted"
      test_command = "ping ${aws_instance.test_vms["db"].private_ip}"
    }
    scenario_3 = {
      name        = "Dev accessing Prod (SHOULD BE ALLOWED - ICMP only)"
      source      = "dev-test-vm (${aws_instance.test_vms["dev"].private_ip})"
      destination = "prod-test-vm (${aws_instance.test_vms["prod"].private_ip})"
      expected    = "SUCCESS - Ping should work"
      test_command = "ping ${aws_instance.test_vms["prod"].private_ip}"
    }
    scenario_4 = {
      name        = "Prod trying to access Dev (SHOULD BE BLOCKED)"
      source      = "prod-test-vm (${aws_instance.test_vms["prod"].private_ip})"
      destination = "dev-test-vm (${aws_instance.test_vms["dev"].private_ip})"
      expected    = "FAIL - Connection should be denied by DCF"
      test_command = "ping ${aws_instance.test_vms["dev"].private_ip}"
    }
  }
}

output "copilot_verification_steps" {
  description = "Steps to verify deployment in CoPilot"
  value = [
    "1. Open CoPilot and navigate to Topology",
    "2. Verify transit gateway and 3 spoke gateways are visible",
    "3. Navigate to Security > Distributed Cloud Firewall > SmartGroups",
    "4. Verify 3 SmartGroups exist: dev, prod, db",
    "5. Navigate to Security > Distributed Cloud Firewall > Rules",
    "6. Verify 5 policies are configured",
    "7. Navigate to Security > Distributed Cloud Firewall > Monitor",
    "8. Run test scenarios and observe traffic (allowed vs denied)"
  ]
}
