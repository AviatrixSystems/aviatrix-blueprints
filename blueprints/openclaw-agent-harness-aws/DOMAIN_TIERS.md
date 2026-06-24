# Domain Tiers

## Restricted

For regulated or data-sensitive agents.

```hcl
enable_package_installs = false
enable_public_reference = false
approved_model_gateway_domains = ["llm-gateway.example.com"]
approved_saas_api_domains = []
approved_mcp_gateway_domains = ["mcp-tools.example.com"]
```

## Balanced

For coding and terminal workflows during monitor-first rollout.

```hcl
enable_package_installs = true
enable_public_reference = false
approved_model_gateway_domains = [
  "integrate.api.nvidia.com",
  "inference-api.nvidia.com"
]
```

## Open demo

For workshops only.

```hcl
enable_package_installs = true
enable_public_reference = true
```

Promote from monitor to enforce only after FlowIQ evidence shows the required destination set.
