-- CI only, after all rollback-based regressions, disposable loopback PostgreSQL.
do $$ begin if current_database()<>'agricitest' or inet_server_addr() is distinct from '127.0.0.1'::inet or current_user<>'postgres' then raise exception 'Disposable CI database required';end if;if exists(select 1 from auth.users) then raise exception 'Expected empty disposable auth fixture';end if;end $$;
begin;
insert into auth.users(id,email) values ('d1000000-0000-4000-8000-000000000001','manager@example.invalid'),('d1000000-0000-4000-8000-000000000002','farmer-a@example.invalid'),('d1000000-0000-4000-8000-000000000003','farmer-b@example.invalid'),('d1000000-0000-4000-8000-000000000004','buyer-a@example.invalid'),('d1000000-0000-4000-8000-000000000005','buyer-b@example.invalid');
insert into public.profiles(id,display_name,account_role) select id,'ONDC disposable QA',case when email like 'manager%' then 'manager' when email like 'farmer%' then 'farmer' else 'customer' end from auth.users;
insert into public.fpos(id,name,location) values('a0000000-0000-4000-8000-000000000001','Demo Green FPO','Test');
insert into public.memberships values('a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','manager','active'),('a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000002','farmer','active'),('a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000003','farmer','active');
insert into public.harvests(id,fpo_id,farmer_id,crop,quantity_kg,harvest_date) values('d2000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000002','Tomatoes',12,current_date-1),('d2000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000003','Tomatoes',18,current_date);
select private.review_harvest_for('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','A',3000,true,'');
select private.review_harvest_for('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002','A',3000,true,'');
create schema ondc_fixture;
revoke all on schema ondc_fixture from public,anon,authenticated,service_role;
create function ondc_fixture.actor(b text) returns uuid language sql immutable set search_path='' as $$ select case b when 'fixture-buyer-a' then 'd1000000-0000-4000-8000-000000000004'::uuid when 'fixture-buyer-b' then 'd1000000-0000-4000-8000-000000000005'::uuid end $$;
create function ondc_fixture.result(b text,t uuid) returns jsonb language sql stable set search_path='' as $$select jsonb_build_object('id',id,'provider',fpo_id,'total_paise',total_paise,'status',status,'payment_status',payment_status) from public.orders where customer_id=ondc_fixture.actor(b) and request_key=t and source='ondc_demo'$$;
create function ondc_fixture.checkout(p jsonb) returns jsonb language plpgsql set search_path='' as $$
declare u uuid:=ondc_fixture.actor(p->>'buyer');t uuid:=(p->>'transaction')::uuid; f uuid:=(p->>'provider')::uuid; oid uuid; o public.orders%rowtype;
begin
 if u is null or f is distinct from 'a0000000-0000-4000-8000-000000000001'::uuid then raise exception 'Unknown fixture buyer or provider';end if;
 oid:=private.checkout_order_for(u,f,p->'items','ONDC LOCAL TEST - no real delivery',t);
 select * into o from public.orders where id=oid for update;
 if o.total_paise<>(p->>'total_paise')::bigint then raise exception 'Quote total mismatch';end if;
 if o.source='web' then
  update public.orders set source='ondc_demo' where id=oid;
  insert into private.integration_events(channel,external_id,event_type,payload,status) values('ondc',oid::text,'local_protocol_checkout',jsonb_build_object('order_id',oid,'mode','local_ci'),'processed');
 elsif o.source<>'ondc_demo' then raise exception 'Order source conflict';end if;
 return ondc_fixture.result(p->>'buyer',t);
end $$;
create function ondc_fixture.transition(b text,t uuid,n text,manager boolean) returns jsonb language plpgsql set search_path='' as $$
declare u uuid:=ondc_fixture.actor(b);oid uuid;
begin select id into oid from public.orders where customer_id=u and request_key=t and source='ondc_demo';if not found then raise exception 'Order unavailable';end if;
 perform private.transition_order_for(case when manager then 'd1000000-0000-4000-8000-000000000001'::uuid else u end,oid,n);
 return ondc_fixture.result(b,t);
end $$;
revoke all on all functions in schema ondc_fixture from public,anon,authenticated,service_role;
commit;
