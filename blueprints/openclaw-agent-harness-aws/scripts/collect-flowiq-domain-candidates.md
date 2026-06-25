# CoPilot FlowIQ domain collection workflow

1. Deploy with `policy_mode = "monitor"`.
2. Run the OpenClaw/NemoClaw terminal workflow from the private VM.
3. In CoPilot FlowIQ, filter source SmartGroup to `<name_prefix>-sg-agent-workload`.
4. Export destinations that match expected business function.
5. Add approved FQDNs to one of:
   - `approved_model_gateway_domains`
   - `approved_saas_api_domains`
   - `approved_mcp_gateway_domains`
   - `identity_and_telemetry_domains`
   - `package_registry_domains`
6. Open a pull request with justification and owner approval.
7. Apply Terraform again with `policy_mode = "enforce"`.

Do not approve broad wildcards unless the business owner and security owner agree.
Prefer exact FQDNs over `*.example.com`.
