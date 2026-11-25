-- Run only on disposable local CI database.
begin;
insert into auth.users(id,email) values
('a5000000-0000-4000-8000-000000000001','manager@example.invalid'),
('a5000000-0000-4000-8000-000000000002','farmer-a@example.invalid'),
('a5000000-0000-4000-8000-000000000003','farmer-b@example.invalid'),
('a5000000-0000-4000-8000-000000000004','buyer@example.invalid'),
('a5000000-0000-4000-8000-000000000005','outsider@example.invalid');
insert into public.profiles select id,'Day02 QA' from auth.users;
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
rollback;
