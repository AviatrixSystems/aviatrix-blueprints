# Changelog

## 2026-05-13

- Initial release
- Aviatrix spoke gateway with DCF Zero Trust egress policy for Azure AI Foundry agent subnet
- 6-rule DCF ruleset: ThreatIQ deny, ACA runtime permits (no decrypt), tool-call FQDN permit (TLS inspect), default deny
- All Aviatrix resource names and network resource group include random 4-digit suffix to support multiple deployments in same environment
- `tool_call_fqdns`, `aca_requirements_fqdns`, `aca_platform_svc_tags` variabilized for end-user customization
- `location` variable validated against Azure AI Foundry supported regions
