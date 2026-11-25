begin;
create table public.orders (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.profiles(id), fpo_id uuid not null references public.fpos(id),
 request_key uuid not null, items jsonb not null, delivery_address text not null check(length(trim(delivery_address)) between 5 and 300),
 status text not null default 'confirmed' check(status in ('confirmed','packed','out_for_delivery','delivered','cancelled')),
 total_paise bigint not null default 0 check(total_paise>=0), gateway_paise bigint not null default 0 check(gateway_paise>=0),
 platform_paise bigint not null default 0 check(platform_paise>=0), logistics_paise bigint not null default 0 check(logistics_paise>=0), farmer_pool_paise bigint not null default 0 check(farmer_pool_paise>=0),
 payment_status text not null default 'simulated_paid' check(payment_status in ('simulated_paid','simulated_refunded')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(customer_id,request_key), check(total_paise=gateway_paise+platform_paise+logistics_paise+farmer_pool_paise)
);
create index orders_customer_idx on public.orders(customer_id,created_at desc);
create index orders_fpo_idx on public.orders(fpo_id,status);
create table public.order_allocations (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id), lot_id uuid not null references public.inventory_lots(id), fpo_id uuid not null references public.fpos(id), farmer_id uuid not null references public.profiles(id),
 crop text not null, grade text not null check(grade in ('A','B','C')), quantity_kg numeric(12,3) not null check(quantity_kg>0), price_paise_per_kg integer not null check(price_paise_per_kg>0),
 gross_paise bigint not null check(gross_paise>=0), payout_paise bigint not null default 0 check(payout_paise>=0 and payout_paise<=gross_paise),
 status text not null default 'reserved' check(status in ('reserved','delivered','cancelled')), unique(order_id,lot_id)
);
create index allocation_farmer_idx on public.order_allocations(fpo_id,farmer_id,status);
create index allocation_order_idx on public.order_allocations(order_id);
create table public.order_events (
 id bigint generated always as identity primary key, order_id uuid not null references public.orders(id), status text not null check(status in ('confirmed','packed','out_for_delivery','delivered','cancelled')), created_at timestamptz not null default now()
);
create index order_events_order_idx on public.order_events(order_id,id);
alter table public.orders enable row level security;
alter table public.order_allocations enable row level security;
alter table public.order_events enable row level security;
revoke all on public.orders,public.order_allocations,public.order_events from public,anon,authenticated;
grant select on public.orders,public.order_allocations,public.order_events to authenticated;
create policy orders_read on public.orders for select to authenticated using(customer_id=(select auth.uid()) or private.is_manager(fpo_id));
create policy allocation_read on public.order_allocations for select to authenticated using(farmer_id=(select auth.uid()) or private.is_manager(fpo_id));
create policy events_read on public.order_events for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id));
create function private.checkout_order(p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); oid uuid; prior public.orders%rowtype; item jsonb; crop_name text; quality text; price integer; requested numeric; remaining numeric; take numeric; lot record; gross bigint; order_total bigint:=0; gateway bigint; platform bigint; logistics bigint; pool bigint; running bigint:=0; payout_running bigint:=0; alloc record; target bigint;
begin
if u is null or not exists(select 1 from public.profiles where id=u) then raise exception 'Sign in and complete profile first'; end if;
if p_request is null or p_fpo is null or p_address is null or length(trim(p_address)) not between 5 and 300 then raise exception 'Valid delivery address and request required'; end if;
if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Cart must be an array'; end if;
if jsonb_array_length(p_items) not between 1 and 20 then raise exception 'Cart must contain 1 to 20 items'; end if;
-- Serialize orders and lifecycle changes per FPO; use a consistent stock lock order.
perform 1 from public.fpos where id=p_fpo for update;
if not found then raise exception 'FPO not found'; end if;
select * into prior from public.orders where customer_id=u and request_key=p_request;
if found then
 if prior.fpo_id<>p_fpo or prior.items<>p_items or prior.delivery_address<>trim(p_address) then raise exception 'Request key already used for different checkout'; end if;
 return prior.id;
end if;
if (select count(distinct (x->>'crop',x->>'grade',x->>'price_paise_per_kg')) from jsonb_array_elements(p_items) x)<>jsonb_array_length(p_items) then raise exception 'Duplicate cart item'; end if;
insert into public.orders(customer_id,fpo_id,request_key,items,delivery_address) values(u,p_fpo,p_request,p_items,trim(p_address)) returning id into oid;
for item in select value from jsonb_array_elements(p_items) order by value->>'crop',value->>'grade',value->>'price_paise_per_kg' loop
 crop_name:=item->>'crop';quality:=item->>'grade';price:=(item->>'price_paise_per_kg')::integer;requested:=(item->>'quantity_kg')::numeric;
 if crop_name is null or length(crop_name) not between 1 and 100 or quality is null or quality not in ('A','B','C') or price is null or price<=0 or requested is null or requested<0.001 or requested>10000 or requested<>round(requested,3) then raise exception 'Invalid cart item'; end if;
 remaining:=requested;
 -- Fairness: lowest previously allocated non-cancelled kilograms first within the chosen FPO/product; oldest harvest then stable id tie-break.
 while remaining>0 loop
  select l.id,l.available_kg,h.farmer_id into lot
  from public.inventory_lots l join public.harvests h on h.id=l.harvest_id
  where l.fpo_id=p_fpo and l.published and l.available_kg>0 and l.crop=crop_name and l.grade=quality and l.price_paise_per_kg=price
  and exists(select 1 from public.memberships m where m.fpo_id=p_fpo and m.user_id=h.farmer_id and m.role='farmer' and m.status='active')
  order by (select coalesce(sum(a.quantity_kg),0) from public.order_allocations a where a.fpo_id=p_fpo and a.farmer_id=h.farmer_id and a.status<>'cancelled'),h.harvest_date,l.id limit 1 for update of l;
  if not found then raise exception 'Stock or price changed. Refresh marketplace and try again'; end if;
  take:=least(remaining,lot.available_kg);
  -- Cumulative rounding guarantees the item subtotal equals rounded quantity times price.
  gross:=round((requested-remaining+take)*price)::bigint-round((requested-remaining)*price)::bigint;
  update public.inventory_lots set available_kg=available_kg-take,reserved_kg=reserved_kg+take where id=lot.id;
  insert into public.order_allocations(order_id,lot_id,fpo_id,farmer_id,crop,grade,quantity_kg,price_paise_per_kg,gross_paise) values(oid,lot.id,p_fpo,lot.farmer_id,crop_name,quality,take,price,gross);
  remaining:=remaining-take;order_total:=order_total+gross;
 end loop;
end loop;
if order_total<1 then raise exception 'Order total must be at least one paise'; end if;
-- Demo only: blueprint's illustrative 2/5/8% fees, remainder to farmer pool. No gateway call.
gateway:=round(order_total*0.02)::bigint;platform:=round(order_total*0.05)::bigint;logistics:=round(order_total*0.08)::bigint;pool:=order_total-gateway-platform-logistics;
update public.orders set total_paise=order_total,gateway_paise=gateway,platform_paise=platform,logistics_paise=logistics,farmer_pool_paise=pool where id=oid;
for alloc in select id,gross_paise from public.order_allocations where order_id=oid order by id loop
 running:=running+alloc.gross_paise;target:=floor(running::numeric*pool/order_total)::bigint;
 update public.order_allocations set payout_paise=target-payout_running where id=alloc.id;
 payout_running:=target;
end loop;
insert into public.order_events(order_id,status) values(oid,'confirmed');
insert into private.audit_events(actor,fpo_id,action,subject) values(u,p_fpo,'order_confirmed',oid);
return oid;
end $$;
create function private.transition_order(p_id uuid,p_next text) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); o public.orders%rowtype; manager boolean; a record;
begin
if u is null then raise exception 'Sign in required'; end if;
select * into o from public.orders where id=p_id for update;
if not found then raise exception 'Order unavailable'; end if;
manager:=private.is_manager(o.fpo_id);
if not manager and o.customer_id<>u then raise exception 'Order unavailable'; end if;
if p_next is null then raise exception 'Invalid transition'; end if;
if p_next='cancelled' then
 if not ((o.customer_id=u and o.status='confirmed') or (manager and o.status in ('confirmed','packed'))) then raise exception 'Cancellation not allowed'; end if;
elsif not manager or not ((o.status='confirmed' and p_next='packed') or (o.status='packed' and p_next='out_for_delivery') or (o.status='out_for_delivery' and p_next='delivered')) then raise exception 'Invalid delivery transition'; end if;
perform 1 from public.fpos where id=o.fpo_id for update;
if p_next in ('cancelled','delivered') then
 for a in select * from public.order_allocations where order_id=o.id order by lot_id loop
  if a.status<>'reserved' then raise exception 'Allocation already finalized'; end if;
  update public.inventory_lots set reserved_kg=reserved_kg-a.quantity_kg,available_kg=available_kg+case when p_next='cancelled' then a.quantity_kg else 0 end where id=a.lot_id and reserved_kg>=a.quantity_kg;
  if not found then raise exception 'Reservation inconsistent'; end if;
  update public.order_allocations set status=p_next where id=a.id;
 end loop;
end if;
update public.orders set status=p_next,payment_status=case when p_next='cancelled' then 'simulated_refunded' else payment_status end,updated_at=now() where id=o.id;
insert into public.order_events(order_id,status) values(o.id,p_next);
insert into private.audit_events(actor,fpo_id,action,subject) values(u,o.fpo_id,'order_'||p_next,o.id);
end $$;
create function public.checkout_order(p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language sql security invoker set search_path='' as $$ select private.checkout_order(p_fpo,p_items,p_address,p_request) $$;
create function public.transition_order(p_id uuid,p_next text) returns void language sql security invoker set search_path='' as $$ select private.transition_order(p_id,p_next) $$;
revoke all on function private.checkout_order(uuid,jsonb,text,uuid),private.transition_order(uuid,text),public.checkout_order(uuid,jsonb,text,uuid),public.transition_order(uuid,text) from public,anon,authenticated;
grant execute on function private.checkout_order(uuid,jsonb,text,uuid),private.transition_order(uuid,text),public.checkout_order(uuid,jsonb,text,uuid),public.transition_order(uuid,text) to authenticated;
commit;
