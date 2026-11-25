# Day 01 acceptance gate
- Confirm distinct Supabase project on free plan. Apply migration and check advisories.
- Use separate manager, farmer and unrelated FPO accounts; test sign-up, joining, approving, submitting a harvest with a photo, grading and publishing. Confirm anonymous catalogue reveals no farmer identifiers; manager cannot access another FPO's records; farmer cannot self-approve or change role.
- Repeat approval and check that no duplicate inventory lot is created.
- Confirm Render build and public URL after configuration. No payment, WhatsApp or ONDC calls are made.
- Current source tests are structural checks, not database or browser integration tests. Admin and delivery are intentionally disabled until role policies and logistics are implemented.
- Day 02: atomic order reservation/allocation and fulfillment; payout ledger; payments simulated. Introduce additional tables through versioned migrations.
- Day 03/04: signed webhooks, verified identity mapping, deduplication, event retries, protocol adapters, sandbox validation. Never trust an external actor or client-supplied role. Use same inventory/order functions.
