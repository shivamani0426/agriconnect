# WhatsApp relay v2 — Round 01 (05A–05D)

Test-only scope. Existing signed webhook, recipient allowlist, account-role checks, test checkout, harvest drafts and real confirmation-button requirement are preserved. ONDC is not modified. No real payment, delivery, voice or media in this round.

## Behavior

- 05A: receipt insert, command execution and reply preparation run in one database transaction. Duplicate inbound IDs do not replay orders, harvests or account links. The private outbox claims each attempt once. Explicit rate limits are retried up to three total attempts, after 30/60-second delays, within ten minutes. Timeouts, 5xx responses and crashed senders are marked unknown; never blindly resend these because the provider might already have accepted a message. Credential errors and permanent errors are terminal for this reply.
- 05B: acknowledge the signed webhook after the transaction commits, not after the external send. Supabase EdgeRuntime.waitUntil performs bounded sending; /relay provides catch-up independent of inbound traffic. Accepted means the provider returned a message ID, not delivery. Signed sent/delivered/read/failed callbacks are correlated with hashed outbound message IDs. Out-of-order updates cannot downgrade read/delivered status. /health shows aggregate states, delivery counts, attempt latency and oldest pending age.
- 05C: authenticated /health probes the fixed phone-number resource without sending a message. A readable phone resource proves read access only, not messaging permission or an expiry date. Invalid/missing token, credentials rejection, rate limit and network failure are distinguished without leaking tokens or raw provider errors.
- 05D: interactive language picker and role menus use the current server-side menu, localized titles and an expiring opaque token. Only actual signed list replies may select a menu row. Existing confirmation and cancel buttons retain their separate IDs; text commands remain usable. An outdated list is rejected, not used to execute an action.

## Rollout (not automatically deployed by a merge)

1. Confirm all WhatsApp relay checks and existing regression checks pass on the exact branch head.
2. Apply the checked-in migration to the existing Supabase project using its normal migration workflow. No destructive changes to existing data.
3. Deploy whatsapp-webhook with the existing signed-webhook configuration. Preserve WA_APP_SECRET, WA_VERIFY_TOKEN, WA_ACCESS_TOKEN, WA_TEST_RECIPIENTS and WA_TEST_REPLIES_ENABLED. Keep test mode and the existing sender allowlist.
4. Generate a new random worker-only secret (at least 32 characters) and set WA_RELAY_WORKER_TOKEN as an Edge Function secret. Never expose it to the frontend, source code, logs or screenshots. Set WA_RELAY_V2_ENABLED=true only after steps 1–3. With the flag unset or false, the legacy implementation remains active.
5. Configure a trusted server scheduler to POST to the existing function URL with /relay appended, approximately once per minute, using Authorization: Bearer <worker secret>. This is required for recovery when nobody sends a new message. Verify plan limits and invocation budget first. No scheduler or paid resource is created by this repository change. Keep the secret in the scheduler's secure store (e.g. Supabase Vault).
6. POST to /health with the same authentication; ensure enabled=true and token=phone_readable. Monitor queue states and pending age. Expired/ambiguous attempts are visible and not automatically resent. The /health call also expires jobs, reconciles delivery callbacks, and purges old telemetry; run it regularly from a trusted scheduler for retention maintenance. It never returns recipient identifiers or message content.
7. Send HI from each linked test role; select language and list rows, exercise a preview then Confirm or Cancel, and check actual handset receipt and matching website state. Test the text fallback and previously generated expired menu. Never disable the allowlist or send to real customers.

## Privacy, limits and rollback

The reply and recipient are kept in a restricted private table only while awaiting a safe send/retry. Terminal or expired rows scrub these fields and link identity; provider and recipient hashes remain pseudonymous (not anonymous) for seven days of telemetry. Cleanup depends on the worker/health schedule running. Existing hashed webhook receipts are retained for deduplication. No raw inbound command or linking code is stored in the outbox. Re-link or role changes invalidate queued replies at claim time; in-flight external calls cannot be withdrawn. Older failed interactive prompts are superseded by newer interactions. One active send per phone, bounded work per request. The queue does not promise exactly-once provider delivery; ambiguous submissions must be reconciled manually.

Rollback: set WA_RELAY_V2_ENABLED=false and stop the worker scheduler. Keep the migration and old receipts; do not drop tables or replay messages. Review pending/unknown jobs before enabling again. New list tokens are invalid when the legacy handler is active.

## Verification

`node --test tests/whatsapp*.test.mjs` exercises signed webhook behavior and relay transport with mocked provider responses. `tests/sql/whatsapp-relay.sql` exercises disposable PostgreSQL, role isolation, retries, callback ordering, private data scrubbing and menu validation. GitHub Actions workflow WhatsApp relay verification runs these with no live credentials. CI is not evidence of live WhatsApp acceptance or actual latency. Real Meta delivery, scheduled recovery, production quota and token rotation still require live test-mode acceptance.
