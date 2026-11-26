# WhatsApp advanced relay (05E–05O)

All operations remain test-only. ONDC remains unchanged. The advanced release is opt-in; apply migrations in order, redeploy the existing webhook, keep `WA_RELAY_V2_ENABLED=true`, then set `WA_ADVANCED_ENABLED=true`. The signed worker scheduler and health endpoint described in [Round 01](whatsapp-relay-v2.md) are still required. No new billable service is provisioned. Leave all flags off until the test environment is ready.

## Command reference

Send HI to start, MORE for the extra commands or /MORE to explicitly leave current guided input. Initial Kannada, Telugu and Hindi greetings detect the language; the stored language choice is respected. Supported natural phrases map conservatively to read-only navigation. Arbitrary text, voice, and guessed intent never automatically confirm an action. Existing four-language guided interactions remain; the added reports and advanced command responses are presently English.

| Role | Commands |
| --- | --- |
| Farmer | SUMMARY (harvest totals, available/reserved stock, simulated payout estimates), HARVESTS (references) |
| Customer | SEARCH tomatoes, ADD 1 2 (item 1, 2 kg), CART, REMOVE 1, CLEARCART, CHECKOUT (actual Confirm/Cancel button), HISTORY 2, STATUS <order UUID> |
| Manager | REPORT, REPORT 2 (scoped FPO summaries), existing review and order menus |

Cart: one FPO, up to ten distinct items, prices and availability revalidated, no reservation until confirmation. Cart expires after thirty minutes, search selection after ten and checkout preview after five. No actual payment/delivery. History includes the account's orders across channels and status events. Existing ownership and active-membership rules apply.

## Photo (05H)

Set `WA_PHOTO_ENABLED=true` only in the existing signed/allowlisted test relay. Submit a harvest first, then send a JPEG, PNG or WebP (up to 5 MiB) with the caption `PHOTO <harvest UUID>`. Only the linked farmer's own pending harvest with no attached photo is eligible. Bytes are fetched using the server token from the restricted Meta media host, checked against metadata, size, content signature and hash, uploaded to the existing private harvest-photos bucket and attached transactionally. Failed uploads are eligible for bounded Storage API cleanup on /relay; successful referenced files are not deleted. The media signature checks are not a full malware/image-decoding scanner; do not use real sensitive photos in this test. A crashed media job expires rather than automatically replaying an uncertain upload. Retry with a new message after expiry.

## Voice (05G)

Optional, disabled unless `WA_VOICE_ENABLED=true`, `WA_VOICE_ENDPOINT` and `WA_VOICE_SERVICE_TOKEN` are configured. The operator must approve a reachable HTTPS endpoint that accepts raw audio/ogg and returns JSON `{"text":"..."}`. Send /VOICE ON for ten-minute consent, then send a short Ogg voice note (2 MiB cap); /VOICE OFF revokes. Only the preview is returned; send text yourself to execute. No voice-based payments, order confirmation or other state mutations. No recording is stored by the relay; a short-lived queued transcript is retained only for reply delivery. The optional `services/whatsapp-voice/server.py` uses an already-downloaded local Faster Whisper model on CPU, bounded 60-second decode and a single inference slot. Install the pinned requirements yourself, set the strong token and local model path, run the server on loopback, and configure your own secure HTTPS reverse proxy if using Supabase remotely. Model files, hardware, speech quality and endpoint reachability must be validated; CI mocks transcription and does not download models. Keep the endpoint disabled if no approved zero-cost infrastructure is available.

## Release acceptance (05M–05O)

The dedicated workflow checks migrations, authorization, stock/order invariants, the legacy guided flows, webhook signatures, media transport with mocks, and competing real PostgreSQL transactions in disposable CI. These tests are not a live Meta load benchmark. Verify the /health response, retry scheduling, actual delivery, language flow, two-product checkout and cancellation, order history, cross-role isolation, consent/short voice transcription, photo visibility and rejected upload cleanup with existing allowlisted test accounts. Validate free quotas and real latency before widening any scope. Roll back by disabling the advanced flag (and media flags), keeping the Round 01 relay active. Do not drop migrations or delete live records.

