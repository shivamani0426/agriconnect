# AgriConnect — 06G demonstration release and recovery runbook

Scope: restricted Meta test recipients only, simulated payments/delivery, ONDC local sandbox, no purchased number or paid infrastructure. Voice transcription remains disabled unless separately configured and approved. Public rollout is not certified.

## Release gates

- Verify exact commit on GitHub: Day 01 (build, unit, local mocked browser and deployed smoke checks), Commerce SQL, WhatsApp relay SQL and concurrency.
- Verify frontend via Render deployment commit and phone smoke test: Get started → role selection → login; test each account role. Check reduced-motion, mobile layout and profile linking. Existing accounts must land in their actual registered role.
- Deploy all six webhook files together (index.ts, config.mjs, handler.mjs, transport.mjs, relay.mjs, media.mjs). No database migration is required for 06G.
- Keep previous deployed commit/function source for rollback. Never regenerate tokens merely for a UI deployment.
- Verify authenticated health, actual handset HI and matching delivery receipt. Readability of phone resource does not prove outbound send permission or expiry.
- Check aggregate inventory conservation, reserved allocations, simulated financial totals and terminal reply scrubbing. Do not create real orders for testing.

## Number replacement without changing code

The two Edge Function secrets/settings WA_PHONE_NUMBER_ID and WA_BUSINESS_ACCOUNT_ID must be supplied together as numeric Meta identifiers. If both are absent, the existing test sender remains the default. An empty, partial or invalid pair fails closed. VITE_WHATSAPP_TEST_NUMBER is the public international display number (+ followed by 7–15 digits); defaults to the current test number. This is a public frontend build setting, not the Meta resource ID. Never use VITE_ for tokens or private secrets.

1. Confirm replacement test sender availability in Meta and system user messaging permissions. Meta controls availability; no guarantee of replacement or indefinite renewal.
2. Schedule a maintenance window. Disable WA_TEST_REPLIES_ENABLED and pause recovery dispatch; leave relay/retention logic available for inspection. Do not switch IDs while old sends, pending/retry jobs or media claims are active. Let bounded leases expire; inspect ambiguous/unknown attempts without replaying them. Reconcile queued replies before resuming. Existing linked identities remain tied to recipient accounts, not the business number.
3. Set both IDs, update WA_ACCESS_TOKEN only if required by permissions, subscribe the new account to the existing signed webhook, verify callback, and update WA_TEST_RECIPIENTS. Keep existing app secret/verify token if same Meta app; if changing app, securely replace those too. Never expose any secret in screenshots or logs.
4. Update VITE_WHATSAPP_TEST_NUMBER in Render and rebuild the frontend. Ensure public instructions match the actual configured sender. If reverting to the old sender, restore both IDs together and the associated credentials/display number.
5. Check authenticated /health and verify no pending old-sender jobs. Resume test replies/recovery; send HI from an allowlisted recipient, inspect receipt and confirm correct role. Exercise fresh linking if needed. Do not disable the recipient restriction. No data reset needed.

## Monitoring and recovery

Existing cron jobs: agriconnect-whatsapp-recovery checks each minute but invokes relay only for due work or periodic cleanup; agriconnect-whatsapp-retention runs hourly at minute 17. Keep these schedules rather than polling every second. Check cron.job_run_details and sanitized net._http_response status; cron success alone means HTTP request scheduling succeeded, not necessarily provider success. Authenticated POST /health with worker bearer (stored in Vault, not browser) reports sender_configuration, token, queue aggregates and enabled flags. The hourly health probe logs only safe token status categories, disabled mode and empty allowlist. Review recent wa_health_* and wa_relay_provider_error events. No automatic external alert or message is sent.

- Missing/invalid/credentials: check paired IDs, system user token and business messaging permissions; do not blindly renew the token.
- Phone readable but sends rejected: inspect numeric provider code and recipient restriction, verify real delivery/read callback.
- Rate limit: existing bounded retry handles explicit rate limits. Unknown/ambiguous: reconcile, never replay automatically. Keep private receipt deduplication.
- Database error: inspect error and recovery state; existing atomic preparation prevents duplicate mutations. Do not truncate inventory, orders or receipts.
- Restore: check Supabase plan-specific backup availability in dashboard. Create encrypted, access-restricted offsite logical exports with authorized tools before destructive maintenance. Include private schema, auth and storage objects as applicable; document restore dependencies. Test restore in a disposable isolated database, not live. This release does not provision backup storage or claim a tested disaster restore. Do not export credentials or user data into public GitHub.
- Rollback: redeploy previous known-good frontend commit and previous five-file webhook version as a unit, retain database migrations, reconcile queue first. Do not run migrations backwards or delete data.

## Resource guardrails

Keep existing free plans and bounded workers; no extra cloud service. Use the existing retention job, review database/storage/egress/Edge usage in Supabase and deployment bandwidth in Render before the demonstration. Browser motion is CSS/SVG, not a continuous WebGL loop. Use device reduced-motion preferences. Current limits and actual billing must be checked in the project dashboards; no promise of indefinite free messaging or capacity.

## Release audit evidence (2026-11-27)

Read-only live snapshot before deployment: 9 inventory lots, zero conservation violations; zero order gross/payout sum discrepancies; no ordinary public table without RLS. Database size 15,078,091 bytes. Outbox 147 accepted, 4 rejected, 1 credentials, no active jobs in snapshot (accepted is not delivery). Both cron jobs active with recent successful runs. Supabase advisor reports intentional restricted tables with RLS/no public policies (INFO) and leaked-password protection disabled (WARN). Do not claim the warning is resolved; assess availability without upgrading plan. CI does not certify actual mobile GPU performance, public onboarding, real payments or a disaster restore.
