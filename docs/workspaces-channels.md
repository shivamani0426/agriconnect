# Workspace and channel sandbox release

Three navigation workspaces share one login and database. Switching workspace is UI preference, not authorization. Farmer: submit, join, harvests, earnings. FPO: overview, members, harvests, inventory, delivery. Customer: market, cart, orders. No public admin workspace.

The optional cart channel sandbox submits authenticated test orders through the existing transaction engine, labels the source as whatsapp_demo or ondc_demo, records an idempotent private integration event and uses the same inventory and fulfillment. No provider requests, phone linking, messages, or callbacks are performed. Demo orders reserve the same stock; cancel test orders to restore stock. Never enter real delivery addresses during demos.

## Live integration gates
- WhatsApp: Meta Business portfolio, WhatsApp Business Account, test phone number/recipient, server-side credentials and signature-verified webhook, verified account linking, opt-in and pricing review. See https://www.postman.com/meta/whatsapp-business-platform/ and https://developers.facebook.com/docs/whatsapp/cloud-api/
- ONDC: participant or partner route, approved staging registry identity, retail domain contract, signing and verification, request replay protection and official Workbench compliance. See https://workbench.ondc.tech/developer-guide and https://github.com/ONDC-Official/developer-docs
- No production provider traffic, billing, or claims of protocol compliance until these gates are completed.
