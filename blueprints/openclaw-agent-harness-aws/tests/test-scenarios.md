# Validated test scenarios for the OpenClaw VM blueprint

Run from the private VM after Terraform apply. In monitor mode, blocked tests may still connect but should produce named logs. In enforce mode, blocked tests should fail.

## 1. Permit passes: OpenClaw/NemoClaw core

```bash
curl -I https://openclaw.ai
curl -I https://docs.openclaw.ai
curl -I https://clawhub.ai
```

Expected in enforce mode: permit events in CoPilot FlowIQ against `vca-openclaw-allow-core`.

## 2. Permit passes: model gateway

```bash
curl -I https://integrate.api.nvidia.com
curl -I https://inference-api.nvidia.com
```

Expected: permit events against `vca-openclaw-allow-model-gateways`, or your enterprise model gateway WebGroup.

## 3. Optional permit passes: HTTPS OS/update path

```bash
curl -I https://archive.ubuntu.com
curl -I https://security.ubuntu.com
```

Expected: permit events against `vca-openclaw-allow-os-updates-https` when the destination uses HTTPS/SNI. This is not a guarantee for HTTP-based apt mirrors; use baked AMIs or private HTTPS mirrors for strict enforce-from-first-boot.

## 4. Terminal package workflow permit

```bash
curl -I https://registry.npmjs.org
curl -I https://pypi.org
curl -I https://github.com
```

Expected: permit events against `vca-openclaw-allow-packages` when `enable_package_installs=true`. If `enable_package_installs=false`, these should default-deny.

## 5. Shadow model provider blocked

```bash
curl -I https://api.openai.com
curl -I https://api.anthropic.com
```

Expected in enforce mode: deny events named `vca-openclaw-shadow-model-deny` unless these domains were explicitly removed from the deny list and added to approved model gateways.

## 6. DNS exfiltration blocked while VPC DNS works

```bash
getent hosts openclaw.ai
# external resolver should fail in enforce mode
dig @8.8.8.8 openclaw.ai
```

Expected: normal VPC resolver lookup works; public resolver UDP/TCP 53 is denied by `vca-openclaw-deny-dns-exfil-udp` or `vca-openclaw-deny-dns-exfil-tcp`.

## 7. Default-deny catches unknown destinations

```bash
curl -I https://example.com
```

Expected in enforce mode: deny by the POST_RULES default action. Add a destination only after confirming it is required and approved.

## 8. East-west isolation

From the agent VM, attempt to connect to an adjacent private RFC1918 address that is not explicitly allowed.

```bash
nc -vz 10.0.0.10 443
```

Expected in enforce mode: deny against `vca-openclaw-deny-eastwest` if the destination matches `east_west_deny_cidrs`.

## 9. Live policy update

1. Keep `policy_mode="enforce"`.
2. Try a required but undeclared business API; confirm deny in FlowIQ.
3. Add the exact FQDN to `approved_saas_api_domains` or `approved_mcp_gateway_domains`.
4. `terraform apply`.
5. Retry; confirm permit against the named allow rule.

## 10. Guardrail validation

Set the same domain in `approved_model_gateway_domains` and `unapproved_model_provider_domains`, then run `terraform plan`.

Expected: Terraform fails before changing DCF policy state.
