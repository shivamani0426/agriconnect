# AgriConnect

Mobile-first agricultural commerce demonstration. Farmer onboarding, FPO management, harvest approval, inventory, customer checkout, delivery tracking and restricted multilingual WhatsApp test assistant. React + TypeScript + Supabase. All payments and deliveries are simulated; ONDC remains a local sandbox. No paid infrastructure required for the current test scope.

Setup: configure VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY from the dedicated AgriConnect project. Never use a service-role key in the browser. Apply the database migrations before running the frontend. Optional VITE_WHATSAPP_TEST_NUMBER updates the public test sender display.

See [06G release and recovery runbook](docs/release-06g.md) for configuration, tests, rotation, monitoring and known limitations.

## Install on your phone

Open the deployed HTTPS website in Chrome on Android or Safari on iPhone. Use **Install app** in the footer, or the browser's Add to Home Screen option. Chrome/Edge on desktop can install it too. No store listing or APK is provided. The production build generates application icons and a manifest; a service worker caches only a public offline notice and icon. Sign-in and all agricultural operations require internet connectivity. No offline mutations or private data are cached by the service worker.
