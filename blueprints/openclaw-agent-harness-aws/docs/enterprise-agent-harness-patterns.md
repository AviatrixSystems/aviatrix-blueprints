# Enterprise Agent Harness Adoption Pattern

## How enterprise developers actually use agent harnesses

Common patterns seen in enterprise developer workflows:

1. **Persistent coding operator**: a terminal host with Git, package managers, local files, and approval loops. Developers want it to pull repos, run tests, open PRs, and keep context across sessions.
2. **Tool gateway client**: an agent talks to MCP/tool gateways for tickets, CRM, document stores, observability, and internal APIs.
3. **Model gateway client**: the agent should use the enterprise-approved model gateway, not arbitrary direct model-provider APIs.
4. **Sandboxed execution runtime**: the harness runs build/test/package commands and needs carefully scoped package registries.
5. **Autonomous long-running worker**: Hermes-style workflows need daemon/process lifecycle, telemetry, and strict egress boundaries.

## Viral architecture move

Make this blueprint the "golden subnet" for agent harnesses:

```text
Agent Class tfvars  ->  Terraform PR  ->  Private Harness VM  ->  Aviatrix SmartGroup  ->  FlowIQ Review  ->  Enforce
```

The viral loop is not "install a firewall." It is:

1. Developer asks for an agent runtime.
2. Platform team gives them a reusable agent-class tfvars file.
3. Developer gets a private SSM-accessible VM and a short list of approved destinations.
4. First week runs in monitor mode.
5. FlowIQ observations become a pull request to WebGroups.
6. The same policy becomes enforce mode for every future instance of that agent class.

## Agent-class presets

| Agent class | Package installs | Public reference | Model path | Tool path |
|---|---:|---:|---|---|
| Coding | Enabled in lab, trimmed in prod | Off by default | Enterprise/NVIDIA model gateway | GitHub, artifact store, MCP gateway |
| Research | Usually disabled after bootstrap | Optional in demo only | Enterprise model gateway | Search/document APIs |
| Support | Disabled unless needed | Off | Enterprise model gateway | Ticketing/CRM APIs |
| Healthcare PHI | Disabled | Off | Internal model gateway only | FHIR/EHR gateway, audited MCP gateway |
| Hermes worker | Case-by-case | Off | Enterprise/NVIDIA model gateway | Messaging/workflow APIs |

## Default pull request policy

A destination should not be added because "the agent asked for it." It should be added only when the PR includes:

- agent class and business function
- exact FQDN or CIDR
- data class reachable by the agent
- whether TLS decryption/IDS inspection is in scope
- owner and expiration/review date
- FlowIQ evidence or test command

## Demo story that lands with developers and CISOs

1. Show a normal OpenClaw/NemoClaw terminal task succeeds.
2. Ask the agent to call an unapproved model provider.
3. Show the terminal failure in enforce mode.
4. Show the named deny in CoPilot FlowIQ.
5. Add one approved destination by PR/tfvars.
6. Apply, rerun, and show live policy update without changing the agent code.

The message: developers keep their agent workflow; security owns the destination boundary.
