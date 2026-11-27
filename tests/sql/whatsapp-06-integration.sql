
-- 06A/B/C/E: real website RPCs, verified-sender relay RPCs, database invariants.
-- Disposable PostgreSQL CI only; all fixtures and helper functions roll back.
begin;
insert into auth.users(id,email) values
('a9700000-0000-4000-8000-000000000001','manager@example.invalid'),
('a9700000-0000-4000-8000-000000000002','farmer@example.invalid'),
('a9700000-0000-4000-8000-000000000003','customer@example.invalid'),
('a9700000-0000-4000-8000-000000000004','customer@example.invalid'),
('a9700000-0000-4000-8000-000000000005','manager@example.invalid');
insert into public.profiles(id,display_name,account_role) select id,'06 QA',split_part(email,'@',1) from auth.users where id::text like 'a9700000-%';
insert into public.fpos(id,name,location) values('b9700000-0000-4000-8000-000000000001','06 QA FPO','Test'),('b9700000-0000-4000-8000-000000000002','Other 06 FPO','Test');
insert into public.memberships(fpo_id,user_id,role,status) values
('b9700000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000001','manager','active'),
('b9700000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000002','farmer','active'),
('b9700000-0000-4000-8000-000000000002','a9700000-0000-4000-8000-000000000005','manager','active');
insert into private.wa_links(user_id,phone) values
('a9700000-0000-4000-8000-000000000001','919000009701'),
('a9700000-0000-4000-8000-000000000002','919000009702'),
('a9700000-0000-4000-8000-000000000003','919000009703'),
('a9700000-0000-4000-8000-000000000004','919000009704'),
('a9700000-0000-4000-8000-000000000005','919000009705');
-- CI helper exercises the actual durable RPC path, not direct business mutations.
create function public.qa06_message(p text,r text,c text) returns jsonb language plpgsql security invoker as $$
declare k text:=encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'); q jsonb;
begin
 if not public.wa_advanced_prepare(k,p,r,c) then raise exception 'FAIL prepare';end if;
 q:=public.wa_relay_take(p,k);
 if q is null then raise exception 'FAIL missing durable reply';end if;
 if not public.wa_relay_finish(k,1,'accepted','wamid.qa06.'||k,10) then raise exception 'FAIL finish';end if;
 return q->'reply';
end $$;
revoke all on function public.qa06_message(text,text,text) from public,anon,authenticated;
grant execute on function public.qa06_message(text,text,text) to service_role;
set local role service_role;
do $qa$ declare q jsonb; h text; begin
 if public.qa06_message('919000009702','harvest','FPOS')->>'body' not like '%06 QA FPO%' then raise exception 'FAIL farmer FPO';end if;
 q:=public.qa06_message('919000009702','harvest','HARVEST 1 | QA06 Tomatoes | 100 | 2026-01-01');
 h:=substring(q->>'body' from 'SUBMIT ([0-9a-f-]{36})');
 if h is null then raise exception 'FAIL harvest preview %',q;end if;
 perform set_config('qa06.harvest',h,true);
 if public.qa06_message('919000009702','harvest','SUBMIT '||h)->>'body' not like 'Harvest submitted!%' then raise exception 'FAIL harvest submit';end if;
 if public.qa06_message('919000009702','harvest','SUBMIT '||h)->>'body' not like 'Harvest already submitted%' then raise exception 'FAIL harvest replay';end if;
end $qa$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','a9700000-0000-4000-8000-000000000005',true);
do $qa$ begin
 if exists(select 1 from public.harvests where id=current_setting('qa06.harvest')::uuid) then raise exception 'FAIL other FPO reads harvest';end if;
 begin perform public.review_harvest(current_setting('qa06.harvest')::uuid,'A',4000,true,'');raise exception 'FAIL other FPO review';exception when raise_exception then if sqlerrm not like 'Manager required%' then raise;end if;end;
end $qa$;
select set_config('request.jwt.claim.sub','a9700000-0000-4000-8000-000000000001',true);
do $qa$ begin
 if not exists(select 1 from public.harvests where id=current_setting('qa06.harvest')::uuid and status='pending' and quantity_kg=100) then raise exception 'FAIL WhatsApp harvest visible to web manager';end if;
 if exists(select 1 from public.inventory_lots where harvest_id=current_setting('qa06.harvest')::uuid) then raise exception 'FAIL premature inventory';end if;
 perform public.review_harvest(current_setting('qa06.harvest')::uuid,'A',4000,true,'');
end $qa$;
reset role;
set local role service_role;
do $qa$ declare q jsonb; begin
 if public.qa06_message('919000009702','harvest','HARVESTS '||current_setting('qa06.harvest'))->>'body' not like '%Status: approved%' then raise exception 'FAIL website approval not visible in WhatsApp';end if;
 perform public.qa06_message('919000009703','guide','HI');perform public.qa06_message('919000009703','guide','1');
 if public.qa06_message('919000009703','guide','SEARCH QA06 Tomatoes')->>'body' not like '%100.000 kg%' then raise exception 'FAIL approved stock visibility';end if;
 if public.qa06_message('919000009703','guide','ADD 1 60')->>'body' not like '%Added%' then raise exception 'FAIL add';end if;
 q:=public.qa06_message('919000009703','guide','CHECKOUT');
 if q->'buttons'->0->>'id' is null then raise exception 'FAIL quote';end if;
 perform set_config('qa06.quote',q->'buttons'->0->>'id',true);
end $qa$;
reset role;
-- Inject a deterministic failure after business mutation but before durable outbox insertion.
create function private.qa06_abort_outbox() returns trigger language plpgsql as $$
begin if new.message_hash=repeat('6',64) then raise exception 'QA06 injected outbox failure';end if;return new;end $$;
create trigger qa06_abort before insert on private.wa_relay_outbox for each row execute function private.qa06_abort_outbox();
set local role service_role;
do $qa$ begin
 begin
  perform public.wa_advanced_prepare(repeat('6',64),'919000009703','button',current_setting('qa06.quote'));
  raise exception 'FAIL failure injection';
 exception when raise_exception then if sqlerrm<>'QA06 injected outbox failure' then raise;end if;end;
end $qa$;
reset role;
do $qa$ begin
 if exists(select 1 from public.orders where customer_id='a9700000-0000-4000-8000-000000000003') or exists(select 1 from public.whatsapp_webhook_receipts where message_hash=repeat('6',64)) or not exists(select 1 from public.inventory_lots where harvest_id=current_setting('qa06.harvest')::uuid and available_kg=100 and reserved_kg=0) then raise exception 'FAIL mutation rollback';end if;
end $qa$;
drop trigger qa06_abort on private.wa_relay_outbox;
set local role service_role;
do $qa$ declare q jsonb; begin
 if not public.wa_advanced_prepare(repeat('6',64),'919000009703','button',current_setting('qa06.quote')) then raise exception 'FAIL retry prepare';end if;
 if public.wa_advanced_prepare(repeat('6',64),'919000009703','button',current_setting('qa06.quote')) then raise exception 'FAIL duplicate receipt';end if;
 q:=public.wa_relay_take('919000009703',repeat('6',64));
 if q->'reply'->>'body' not like '%Test order confirmed%' then raise exception 'FAIL order response %',q;end if;
 if not public.wa_relay_finish(repeat('6',64),1,'retryable',null,20) then raise exception 'FAIL rate-limit retry';end if;
 if public.wa_relay_take('919000009703',repeat('6',64)) is not null then raise exception 'FAIL backoff';end if;
end $qa$;
reset role;
update private.wa_relay_outbox set due_at=clock_timestamp()-interval '1 second' where message_hash=repeat('6',64);
set local role service_role;
do $qa$ declare q jsonb; begin
 q:=public.wa_relay_take('919000009703',repeat('6',64));
 if q->>'attempt'<>'2' or q->'reply'->>'body' not like '%Test order confirmed%' then raise exception 'FAIL recovered stored reply';end if;
 perform public.wa_relay_finish(repeat('6',64),2,'accepted','wamid.qa06.order',20);
 perform public.wa_relay_delivery('919000009703','wamid.qa06.order','read');
 if public.qa06_message('919000009703','button',current_setting('qa06.quote'))->>'body' not like '%already confirmed%' then raise exception 'FAIL semantic replay';end if;
end $qa$;
reset role;
do $qa$ begin
 if (select count(*) from public.orders where customer_id='a9700000-0000-4000-8000-000000000003')<>1 then raise exception 'FAIL duplicate order';end if;
 if not exists(select 1 from public.inventory_lots where harvest_id=current_setting('qa06.harvest')::uuid and available_kg=40 and reserved_kg=60) then raise exception 'FAIL reservation';end if;
 if not exists(select 1 from private.wa_relay_outbox where message_hash=repeat('6',64) and state='accepted' and attempts=2 and delivery='read' and phone is null and reply is null) then raise exception 'FAIL recovery or privacy';end if;
end $qa$;
select set_config('qa06.order',(select id::text from public.orders where customer_id='a9700000-0000-4000-8000-000000000003'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','a9700000-0000-4000-8000-000000000004',true);
do $qa$ begin
 if exists(select 1 from public.orders where id=current_setting('qa06.order')::uuid) or exists(select 1 from public.order_events where order_id=current_setting('qa06.order')::uuid) then raise exception 'FAIL other customer reads';end if;
 begin perform public.checkout_order('b9700000-0000-4000-8000-000000000001','[{"crop":"QA06 Tomatoes","grade":"A","price_paise_per_kg":4000,"quantity_kg":50}]','QA test address',gen_random_uuid());raise exception 'FAIL oversell';exception when raise_exception then if sqlerrm not like 'Stock or price changed%' then raise;end if;end;
end $qa$;
select set_config('request.jwt.claim.sub','a9700000-0000-4000-8000-000000000001',true);
do $qa$ begin
 if not exists(select 1 from public.orders where id=current_setting('qa06.order')::uuid and source='whatsapp_test' and total_paise=240000 and farmer_pool_paise=204000) then raise exception 'FAIL website order visibility or split';end if;
 perform public.transition_order(current_setting('qa06.order')::uuid,'packed');
 perform public.transition_order(current_setting('qa06.order')::uuid,'out_for_delivery');
 perform public.transition_order(current_setting('qa06.order')::uuid,'delivered');
end $qa$;
reset role;
set local role service_role;
do $qa$ begin
 if public.qa06_message('919000009703','guide','STATUS '||current_setting('qa06.order'))->>'body' not like '%Status: delivered%' then raise exception 'FAIL delivered status in WhatsApp';end if;
 if public.qa06_message('919000009704','guide','STATUS '||current_setting('qa06.order'))->>'body' like '%Status: delivered%' then raise exception 'FAIL status isolation';end if;
 perform public.qa06_message('919000009702','guide','HI');perform public.qa06_message('919000009702','guide','1');
 if public.qa06_message('919000009702','guide','SUMMARY')->>'body' not like '%Delivered allocation estimate: ₹2040.00%' then raise exception 'FAIL farmer delivered value';end if;
end $qa$;
reset role;
do $qa$ begin
 if not exists(select 1 from public.inventory_lots where harvest_id=current_setting('qa06.harvest')::uuid and available_kg=40 and reserved_kg=0) or not exists(select 1 from public.order_allocations where order_id=current_setting('qa06.order')::uuid and status='delivered' and quantity_kg=60 and payout_paise=204000) then raise exception 'FAIL delivered stock conservation';end if;
 if (select array_agg(status order by id) from public.order_events where order_id=current_setting('qa06.order')::uuid) is distinct from array['confirmed','packed','out_for_delivery','delivered']::text[] then raise exception 'FAIL order timeline';end if;
end $qa$;
select 'PASS 06A/B/C/E: real cross-channel RPC supply chain, 100kg conservation, fee split, isolation, atomic outbox rollback, duplicate-safe recovery and delivery' result;
rollback;
