# UI smoke checklist

Run after `terraform apply` against a fresh deploy. ~10 minutes.

1. `terraform output -raw ui_alb_url` — open in browser.
2. Status strip shows real `region`, `runtime`, `data plane`, `dcf rules`, `controller`.
3. Click each scenario chip in turn — page swaps via HTMX, story pane updates per scenario.
4. Toggle **Containment OFF** in the status strip — switch slides to red, URL gains `?containment=off`.
5. Run **LLM01** with toggle ON → verdict `CONTAINED`; attack flow shows Aviatrix Gateway node with DENY action; rule block shows `agentcore-vca-100-runtime-default-deny`; Control Evidence shows TLS termination at spoke GW.
6. Run **LLM01** with toggle OFF → verdict `BREACH` + `SIMULATED` ribbon; same nodes but Aviatrix Gateway shows PERMIT; final egress node green ("HTTP 200, 38 bytes sent").
7. Run **LLM02** (`dns_exfil`), **LLM05** (`compromised_mcp`), **LLM05b** (`supply_chain_url_path`), and **LLM08** (`shadow_model`) with toggle ON, then OFF — verify each card adapts. (LLM03/04/06/07 are deferred to v2.)
8. Run **Drift** with toggle ON → CONTAINED; rule block has `IAM` pill instead of `DCF`; Control Evidence shows `AccessDeniedException`.
9. Run **Drift** with toggle OFF → still CONTAINED + IAM-note: "IAM is a separate enforcement plane".
10. Visit `/chat` — send a message; reply appears; `DCF -30-` badge visible.
11. Visit `/forensics/tool` — submit form; JSON result rendered.
12. Visit `/forensics/mcp` — submit form with `https://mcp.deepwiki.com/mcp`; JSON tool list rendered.
