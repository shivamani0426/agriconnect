# Pipeline 03B: WhatsApp test webhook
This is NOT a live ordering integration. No changes to the website, account roles, inventory or commerce engine. It only answers Hi, Hello, Help and Menu from explicit test recipients on the fixed Meta test number/account, within ten minutes of the inbound message. All other inputs ignored. Signed POSTs and GET verification are separate; verify_jwt=false is required for Meta and only this function. HMAC signature verified on raw bytes before parsing. Receipt hashes prevent duplicate replies; a failed or ambiguous send is not automatically retried (send a fresh Hi instead). No raw sender, message or token is stored in the receipts table. Test-only receipts can be cleaned manually after testing.
## Supabase secrets
WA_VERIFY_TOKEN: user-generated random 32+ character string.
WA_APP_SECRET: Meta App settings > Basic > App secret (not access token).
WA_ACCESS_TOKEN: temporary Meta token from Try it out.
WA_TEST_RECIPIENTS: explicitly verified test recipient digits only, country code included, comma-separated.
WA_TEST_REPLIES_ENABLED: false until webhook verification; then true to enable testing. Set false to stop replies.
## Meta settings
Callback URL https://wlbavjnwkkxvloioybhd.supabase.co/functions/v1/whatsapp-webhook
Verify token: exactly the WA_VERIFY_TOKEN value. Subscribe to messages and verify the test WABA is subscribed to the app. Do not add production phone or payment method. Send Hi from your allowlisted phone. If temporary token expires, replace it. Never share tokens in chat, GitHub or frontend.
