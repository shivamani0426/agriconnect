begin;
create table public.whatsapp_webhook_receipts (
 message_hash text primary key check(message_hash ~ '^[a-f0-9]{64}$'),
 status text not null default 'claimed' check(status in ('claimed','sent','failed')),
 created_at timestamptz not null default now()
);
alter table public.whatsapp_webhook_receipts enable row level security;
revoke all on public.whatsapp_webhook_receipts from public,anon,authenticated;
grant select,insert,update on public.whatsapp_webhook_receipts to service_role;
commit;