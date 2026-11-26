-- Run only on disposable local CI database.
begin;
insert into auth.users(id,email) values
('a5000000-0000-4000-8000-000000000001','manager@example.invalid'),
('a5000000-0000-4000-8000-000000000002','farmer-a@example.invalid'),
('a5000000-0000-4000-8000-000000000003','farmer-b@example.invalid'),
('a5000000-0000-4000-8000-000000000004','buyer@example.invalid'),
('a5000000-0000-4000-8000-000000000005','outsider@example.invalid');
insert into public.profiles(id,display_name,account_role) select id,'Day02 QA',case when email like 'manager%' then 'manager' when email like 'farmer%' then 'farmer' else 'customer' end from auth.users;
set local role authenticated;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000001',true);
select set_config('test.fpo',public.create_fpo('Day02 QA FPO','Test')::text,true);
reset role;
insert into public.memberships(fpo_id,user_id,role,status) values(current_setting('test.fpo')::uuid,'a5000000-0000-4000-8000-000000000002','farmer','active'),(current_setting('test.fpo')::uuid,'a5000000-0000-4000-8000-000000000003','farmer','active');
set local role authenticated;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000002',true);
insert into public.harvests(id,fpo_id,farmer_id,crop,quantity_kg,harvest_date) values('b5000000-0000-4000-8000-000000000001',current_setting('test.fpo')::uuid,auth.uid(),'QA tomatoes',60,current_date-1);
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000003',true);
insert into public.harvests(id,fpo_id,farmer_id,crop,quantity_kg,harvest_date) values('b5000000-0000-4000-8000-000000000002',current_setting('test.fpo')::uuid,auth.uid(),'QA tomatoes',40,current_date);
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000001',true);
select public.review_harvest('b5000000-0000-4000-8000-000000000001','A',1000,true,'');
select public.review_harvest('b5000000-0000-4000-8000-000000000002','A',1000,true,'');
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000004',true);
select set_config('test.cart','[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":75}]',true);
select set_config('test.order',public.checkout_order(current_setting('test.fpo')::uuid,current_setting('test.cart')::jsonb,'Test delivery address','c5000000-0000-4000-8000-000000000001')::text,true);
do $$ begin
if public.checkout_order(current_setting('test.fpo')::uuid,current_setting('test.cart')::jsonb,'Test delivery address','c5000000-0000-4000-8000-000000000001')<>current_setting('test.order')::uuid then raise exception 'FAIL idempotency';end if;
if not exists(select 1 from public.orders where id=current_setting('test.order')::uuid and total_paise=75000 and gateway_paise=1500 and platform_paise=3750 and logistics_paise=6000 and farmer_pool_paise=63750) then raise exception 'FAIL split';end if;
if exists(select 1 from public.order_allocations where order_id=current_setting('test.order')::uuid) then raise exception 'FAIL buyer sees farmer allocation';end if;
begin perform public.checkout_order(current_setting('test.fpo')::uuid,'[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":26}]','Test delivery address','c5000000-0000-4000-8000-000000000002');raise exception 'FAIL oversell';exception when raise_exception then if sqlerrm not like 'Stock or price changed%' then raise;end if;end;
begin perform public.transition_order(current_setting('test.order')::uuid,'delivered');raise exception 'FAIL customer delivery';exception when raise_exception then if sqlerrm<>'Invalid delivery transition' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000005',true);
do $$ begin if exists(select 1 from public.orders where id=current_setting('test.order')::uuid) then raise exception 'FAIL outsider sees order';end if;begin perform public.transition_order(current_setting('test.order')::uuid,'cancelled');raise exception 'FAIL outsider action';exception when raise_exception then if sqlerrm<>'Order unavailable' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000002',true);
do $$ begin if exists(select 1 from public.orders where id=current_setting('test.order')::uuid) then raise exception 'FAIL farmer customer privacy';end if;if (select count(*) from public.order_allocations where order_id=current_setting('test.order')::uuid)<>1 then raise exception 'FAIL farmer allocations';end if;end $$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000001',true);
do $$ begin if (select sum(quantity_kg) from public.order_allocations where order_id=current_setting('test.order')::uuid)<>75 or (select sum(payout_paise) from public.order_allocations where order_id=current_setting('test.order')::uuid)<>63750 or (select count(*) from public.order_allocations where order_id=current_setting('test.order')::uuid)<>2 then raise exception 'FAIL allocations';end if;if (select sum(available_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>25 then raise exception 'FAIL reservation';end if;end $$;
select public.transition_order(current_setting('test.order')::uuid,'packed');
select public.transition_order(current_setting('test.order')::uuid,'out_for_delivery');
select public.transition_order(current_setting('test.order')::uuid,'delivered');
do $$ begin if (select sum(reserved_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>0 or (select count(*) from public.order_allocations where order_id=current_setting('test.order')::uuid and status='delivered')<>2 then raise exception 'FAIL delivery';end if;end $$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000004',true);
select set_config('test.cancel',public.checkout_order(current_setting('test.fpo')::uuid,'[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":10}]','Test delivery address','c5000000-0000-4000-8000-000000000003')::text,true);
select public.transition_order(current_setting('test.cancel')::uuid,'cancelled');
do $$ begin if not exists(select 1 from public.orders where id=current_setting('test.cancel')::uuid and payment_status='simulated_refunded' and status='cancelled') then raise exception 'FAIL refund';end if;end $$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000001',true);
do $$ begin if (select sum(available_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>25 or (select sum(reserved_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>0 then raise exception 'FAIL cancellation restore';end if;end $$;
reset role;
select 'PASS: allocation across two farmers, exact payout split, idempotency, oversell rollback, role isolation, delivery, cancellation/refund and stock restoration' result;
-- Channel sandbox: the same real database stock engine, no external messages.
set local role authenticated;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000004',true);
select set_config('test.wa',public.checkout_demo_channel('whatsapp',current_setting('test.fpo')::uuid,'[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":10}]','Test address','c5000000-0000-4000-8000-000000000004')::text,true);
select set_config('test.ondc',public.checkout_demo_channel('ondc',current_setting('test.fpo')::uuid,'[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":5}]','Test address','c5000000-0000-4000-8000-000000000005')::text,true);
do $$ begin
if public.checkout_demo_channel('whatsapp',current_setting('test.fpo')::uuid,'[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":10}]','Test address','c5000000-0000-4000-8000-000000000004')<>current_setting('test.wa')::uuid then raise exception 'FAIL channel retry';end if;
if not exists(select 1 from public.orders where id=current_setting('test.wa')::uuid and source='whatsapp_demo') or not exists(select 1 from public.orders where id=current_setting('test.ondc')::uuid and source='ondc_demo') then raise exception 'FAIL channel attribution';end if;
begin perform public.checkout_demo_channel('ondc',current_setting('test.fpo')::uuid,'[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":10}]','Test address','c5000000-0000-4000-8000-000000000004');raise exception 'FAIL cross channel key';exception when raise_exception then if sqlerrm<>'Request key already used for another channel' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000001',true);
do $$ begin if (select sum(available_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>10 or (select sum(reserved_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>15 then raise exception 'FAIL shared inventory';end if;end $$;
reset role;
do $$ begin if (select count(*) from private.integration_events where event_type='demo_checkout')<>2 then raise exception 'FAIL channel event deduplication';end if;end $$;
select 'PASS: both demo channels share stock, retain attribution and deduplicate retries' result;
-- Exclusive role authorization checks, using the existing commerce fixtures.
set local role authenticated;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000002',true);
do $role$ begin
begin update public.profiles set account_role='manager' where id=auth.uid();raise exception 'FAIL role mutation';exception when raise_exception then if sqlerrm<>'Account role is permanent' then raise;end if;end;
begin perform public.create_fpo('Unauthorized FPO','Test');raise exception 'FAIL farmer creates FPO';exception when raise_exception then if sqlerrm<>'FPO manager account required' then raise;end if;end;
begin perform public.checkout_order(current_setting('test.fpo')::uuid,'[]','Test address',gen_random_uuid());raise exception 'FAIL farmer checkout';exception when raise_exception then if sqlerrm<>'Customer account required' then raise;end if;end;
begin perform public.checkout_demo_channel('whatsapp',current_setting('test.fpo')::uuid,'[]','Test address',gen_random_uuid());raise exception 'FAIL farmer demo checkout';exception when raise_exception then if sqlerrm<>'Customer account required' then raise;end if;end;
end $role$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000001',true);
do $role$ begin
begin update public.profiles set account_role='customer' where id=auth.uid();raise exception 'FAIL manager role mutation';exception when raise_exception then if sqlerrm<>'Account role is permanent' then raise;end if;end;
begin perform public.checkout_order(current_setting('test.fpo')::uuid,'[]','Test address',gen_random_uuid());raise exception 'FAIL manager checkout';exception when raise_exception then if sqlerrm<>'Customer account required' then raise;end if;end;
begin insert into public.memberships(fpo_id,user_id,role,status) values(current_setting('test.fpo')::uuid,auth.uid(),'farmer','pending');raise exception 'FAIL manager farmer membership';exception when raise_exception then if sqlerrm<>'Membership must match permanent account role' then raise;end if;end;
end $role$;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000004',true);
do $role$ begin
begin perform public.create_fpo('Unauthorized FPO','Test');raise exception 'FAIL customer creates FPO';exception when raise_exception then if sqlerrm<>'FPO manager account required' then raise;end if;end;
begin insert into public.memberships(fpo_id,user_id,role,status) values(current_setting('test.fpo')::uuid,auth.uid(),'farmer','pending');raise exception 'FAIL customer farmer membership';exception when raise_exception then if sqlerrm<>'Membership must match permanent account role' then raise;end if;end;
begin update public.profiles set account_role='farmer' where id=auth.uid();raise exception 'FAIL customer role mutation';exception when raise_exception then if sqlerrm<>'Account role is permanent' then raise;end if;end;
end $role$;
reset role;
select 'PASS: permanent roles, cross-role writes and web/demo checkout denied' result;
-- WhatsApp integration using disposable commerce fixtures, after all prior assertions.
insert into private.wa_links(user_id,phone) values('a5000000-0000-4000-8000-000000000004','919000000004'),('a5000000-0000-4000-8000-000000000002','919000000002'),('a5000000-0000-4000-8000-000000000001','919000000001'),('a5000000-0000-4000-8000-000000000005','919000000005');
do $$ begin
 if has_function_privilege('authenticated','public.wa_order_command(text,text)','execute') or has_function_privilege('anon','public.wa_order_command(text,text)','execute') or has_function_privilege('authenticated','private.checkout_order_for(uuid,uuid,jsonb,text,uuid)','execute') or has_table_privilege('authenticated','private.wa_shop','select') then raise exception 'FAIL WhatsApp privileges';end if;
end $$;
set local role service_role;
do $$ declare r text; begin
 if public.wa_order_command('919000000009','SHOP') not like 'Link your%' then raise exception 'FAIL unlinked';end if;
 if public.wa_order_command('919000000002','SHOP') not like '%Customer account%' or public.wa_order_command('919000000001','SHOP') not like '%Customer account%' then raise exception 'FAIL role';end if;
 if public.wa_order_command('919000000004','SHOP') not like '%QA tomatoes%' then raise exception 'FAIL shop';end if;
 if public.wa_order_command('919000000004','BUY 1 11') not like 'Stock or price%' then raise exception 'FAIL oversell quote';end if;
 r:=public.wa_order_command('919000000004','BUY 1 2');
 if r not like '%Total ₹20.00%' then raise exception 'FAIL quote %',r;end if;
 perform set_config('test.wa_quote',substring(r from 'CONFIRM ([0-9a-f-]{36})'),true);
end $$;
reset role;
do $$ begin if (select sum(available_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>10 then raise exception 'FAIL quote reserved stock';end if;end $$;
set local role service_role;
do $$ declare r text; begin
 if public.wa_order_command('919000000005','CONFIRM '||current_setting('test.wa_quote')) not like 'Quote expired or invalid%' then raise exception 'FAIL cross account quote';end if;
 r:=public.wa_order_command('919000000004','CONFIRM '||current_setting('test.wa_quote'));
 if r not like 'Test order confirmed!%' then raise exception 'FAIL confirm %',r;end if;
 perform set_config('test.wa_order',substring(r from 'Order ([0-9a-f-]{36})'),true);
 if public.wa_order_command('919000000004','CONFIRM '||current_setting('test.wa_quote')) not like 'Order already placed%' then raise exception 'FAIL duplicate';end if;
 if public.wa_order_command('919000000005','TRACK '||current_setting('test.wa_order')) not like 'No matching%' then raise exception 'FAIL private tracking';end if;
 if public.wa_order_command('919000000004','TRACK') not like '%Status: confirmed%' then raise exception 'FAIL tracking';end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.orders where source='whatsapp_test')<>1 or (select total_paise from public.orders where id=current_setting('test.wa_order')::uuid)<>2000 or (select sum(available_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>8 then raise exception 'FAIL shared stock and total';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000001',true);
select public.transition_order(current_setting('test.wa_order')::uuid,'packed');
reset role;
set local role service_role;
do $$ begin if public.wa_order_command('919000000004','TRACK') not like '%Status: packed%' then raise exception 'FAIL manager update';end if;
 if public.wa_order_command('919000000004','SHOP') not like '%QA tomatoes%' then raise exception 'FAIL second shop';end if;
 perform set_config('test.wa_stale',substring(public.wa_order_command('919000000004','BUY 1 8') from 'CONFIRM ([0-9a-f-]{36})'),true);
end $$;
reset role;
-- Web checkout consumes stock after quote; confirmation must fail atomically.
set local role authenticated;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000005',true);
select public.checkout_order(current_setting('test.fpo')::uuid,'[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":1}]','Test address',gen_random_uuid());
reset role;
set local role service_role;
do $$ begin if public.wa_order_command('919000000004','CONFIRM '||current_setting('test.wa_stale')) not like 'Order not placed%' then raise exception 'FAIL changed stock';end if;end $$;
reset role;
update private.wa_shop set quote_expires=clock_timestamp()-interval '1 second' where user_id='a5000000-0000-4000-8000-000000000004';
set local role service_role;
do $$ begin if public.wa_order_command('919000000004','CONFIRM '||current_setting('test.wa_stale')) not like 'Quote expired%' then raise exception 'FAIL expired quote';end if;end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000004',true);
select public.wa_unlink();
reset role;
do $$ begin if exists(select 1 from private.wa_shop where user_id='a5000000-0000-4000-8000-000000000004') or (select count(*) from public.orders where source='whatsapp_test')<>1 or (select sum(available_kg) from public.inventory_lots where fpo_id=current_setting('test.fpo')::uuid)<>7 then raise exception 'FAIL rollback or unlink cleanup';end if;end $$;
select 'PASS: signed-channel customer authorization, quote/confirm, stock sharing, idempotency, price, expiry, private tracking, manager updates and unlink cleanup' result;

rollback;
