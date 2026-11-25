begin;
alter table public.orders add column source text not null default 'web' check(source in ('web','whatsapp_demo','ondc_demo'));
-- Authenticated, internal channel simulator only. Never accepts a provider identity or claims a real webhook.
create function private.checkout_demo_channel(p_channel text,p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); oid uuid; existing public.orders%rowtype; source_name text;
begin
if u is null or p_channel is null or p_channel not in ('whatsapp','ondc') or p_request is null or p_fpo is null then raise exception 'Authenticated demo channel required'; end if;
source_name:=p_channel||'_demo';
perform 1 from public.fpos where id=p_fpo for update;
if not found then raise exception 'FPO not found'; end if;
select * into existing from public.orders where customer_id=u and request_key=p_request;
if found and existing.source<>source_name then raise exception 'Request key already used for another channel'; end if;
-- Same validation, allocation, pricing, stock locking and idempotency as web orders.
oid:=private.checkout_order(p_fpo,p_items,p_address,p_request);
update public.orders set source=source_name where id=oid and customer_id=u;
insert into private.integration_events(channel,external_id,event_type,payload,status)
values(p_channel,'sandbox:'||u::text||':'||p_request::text,'demo_checkout',jsonb_build_object('order_id',oid,'mode','simulation'),'processed')
on conflict(channel,external_id,event_type) do nothing;
return oid;
end $$;
create function public.checkout_demo_channel(p_channel text,p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language sql security invoker set search_path='' as $$ select private.checkout_demo_channel(p_channel,p_fpo,p_items,p_address,p_request) $$;
revoke all on function private.checkout_demo_channel(text,uuid,jsonb,text,uuid),public.checkout_demo_channel(text,uuid,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function private.checkout_demo_channel(text,uuid,jsonb,text,uuid),public.checkout_demo_channel(text,uuid,jsonb,text,uuid) to authenticated;
commit;