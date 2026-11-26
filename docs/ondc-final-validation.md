# 04I / 04J — Local validation evidence and final audit
Reviewed 2026-11-26. **Not a certification, official network test or registration.**
## Commands
- `node --test tests/ondc-final-audit.test.mjs` — ten local tests.
- `node ondc/final-audit.mjs` — offline final report. Both local scenarios and crypto must pass, but release_ready and ondc_connected remain false.
- `node ondc/final-audit.mjs --trace delivery > /tmp/agriconnect-delivery-local.json`
- `node ondc/final-audit.mjs --trace cancellation > /tmp/agriconnect-cancel-local.json`
Traces use fictional data, ephemeral Ed25519 public keys, raw request/callback bytes encoded in base64, signature headers and correlation IDs. No real buyer data, private keys or network traffic. Verify historical signatures against the trace's own public keys and signed creation timestamps; this detects accidental modification or mismatched trace data, not forgery by someone who can generate their own keys. Stock and ACK metadata are fixture observations, not signed proof. Do not submit synthetic traces as official compliance evidence.
## Validation scope
The official ONDC GitHub profile lists RET 1.2.5 as latest but Workbench availability varies by version/flow (the profile links Workbench under 1.2.0). Confirm version and enabled test flows in the portal before integration. The official log validation utility supports RET10 1.2.0 and 1.2.5; its documented 1.2.5 standard delivery flow 004 requires full catalogue refresh and extra unsolicited fulfilment statuses. Our local trace implements paired request/callbacks, not the full official flow. The official utility is NOT invoked and full schemas are NOT validated by our tool.
Sources:
- https://github.com/ONDC-Official/.github/blob/main/profile/README.md
- https://github.com/ONDC-Official/log-validation-utility (RET 1.2.5, flow 004)
- https://workbench.ondc.tech/developer-guide
- https://portal.ondc.org/
## Independent verification checklist (manual gates; no self-certification)
1. Get written ONDC confirmation of free preprod eligibility and legal profile/hostname requirements; no paid domain or real transactions.
2. Confirm registry lookup returns approved participant ID, public keys, RET10 domain, seller type and environment. Never export actual private keys.
3. Run official Workbench schema and applicable scenario tests for approved version; retain validation result IDs, exact commit and redacted error reports. Resolve errors before acceptance.
4. Use an independent approved test buyer for discovery and 2 orders (delivery and cancellation). Use designated synthetic FPO inventory only. Match signed request/callback message and transaction IDs, order ID, quantity, quote, manager status, reservations, payout estimate and restored stock. No real personal details.
5. Record official network logs, not just local traces; confirm zero oversell, duplicate orders, cross-tenant exposure, missing events and incorrect payouts. Run full GitHub CI on exact release; verify Vite audit and lockfile separately.
6. Sign off with ONDC and user before enabling external traffic. Production obligations (grievance, compliance, taxes, settlement, privacy, logistics) remain distinct.
## Remaining engineering
Registry on_subscribe challenge and actual lookup, dynamic callback hosting, real key lifecycle, full catalogue and protocol contracts, persistent external identity and transaction/order/outbox implementation remain open. Do not expose the simulator or its local-only buyer_ref or LOCAL_* error codes to an external network. No changes to package.json, database migrations or deployed app.
