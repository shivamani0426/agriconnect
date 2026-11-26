begin;
-- The checkout implementation is shared by authenticated web checkout and the private verified sender flow.
create function private.checkout_order_for(u uuid,p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare oid uuid; prior public.orders%rowtype; item jsonb; crop_name text; quality text; price integer; requested numeric; remaining numeric; take numeric; lot record; gross bigint; order_total bigint:=0; gateway bigint; platform bigint; logistics bigint; pool bigint; running bigint:=0; payout_running bigint:=0; alloc record; target bigint;
begin
if u is null or not exists(select 1 from public.profiles where id=u and account_role='customer') then raise exception 'Customer account required'; end if;
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
revoke all on function private.checkout_order_for(uuid,uuid,jsonb,text,uuid) from public,anon,authenticated,service_role;
create or replace function private.checkout_order(p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language sql security definer set search_path='' as $$ select private.checkout_order_for(auth.uid(),p_fpo,p_items,p_address,p_request) $$;
alter table public.orders drop constraint orders_source_check;
alter table public.orders add constraint orders_source_check check(source in ('web','whatsapp_demo','ondc_demo','whatsapp_test'));
create table private.wa_shop(
 user_id uuid primary key references private.wa_links(user_id) on delete cascade,
 products jsonb not null default '[]'::jsonb,
 catalogue_expires timestamptz not null,
 quote_id uuid unique, quote_item jsonb, quote_fpo uuid, quote_expires timestamptz
);
alter table private.wa_shop enable row level security;
revoke all on private.wa_shop from public,anon,authenticated,service_role;
create function private.wa_order_command(p_phone text,p_command text) returns text language plpgsql security definer set search_path='' as $$
declare u uuid; role_name text; cmd text:=lower(trim(p_command)); s private.wa_shop%rowtype; products jsonb; p jsonb; x text[]; n integer; page_no integer; qty numeric; item jsonb; qid uuid; oid uuid; o public.orders%rowtype; reply text; total bigint; live_qty numeric;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_command is null or length(p_command)>512 then return 'Invalid test command.';end if;
 select user_id into u from private.wa_links where phone=p_phone;
 if not found then return 'Link your AgriConnect account in Profile first: https://agriconnect-q7c2.onrender.com/';end if;
 select account_role into role_name from public.profiles where id=u for no key update;
 if not found or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone) then return 'Link your AgriConnect account first.';end if;
 if role_name is distinct from 'customer' then return 'WhatsApp shopping requires a Customer account. Your permanent role cannot be changed.';end if;
 select * into s from private.wa_shop where user_id=u;
 if cmd in ('hi','hello','help','menu') then
 return 'AgriConnect customer test menu: SHOP (browse), SHOP 2 (next page), BUY 1 2 (item 1, 2 kg), CONFIRM followed by your quote code, TRACK (latest test order), RESET (discard draft). No actual payment or delivery.';
 elsif cmd ~ '^shop( [1-9][0-9]{0,2})?$' then
 page_no:=coalesce(nullif(split_part(cmd,' ',2),''),'1')::integer;
 select coalesce(jsonb_agg(to_jsonb(z) order by z.fpo_name,z.crop,z.grade,z.price_paise_per_kg,z.fpo_id),'[]'::jsonb) into products from
 (select * from private.catalogue() order by fpo_name,crop,grade,price_paise_per_kg,fpo_id limit 8 offset ((page_no-1)*8)) z;
 insert into private.wa_shop(user_id,products,catalogue_expires) values(u,products,clock_timestamp()+interval '10 minutes')
 on conflict(user_id) do update set products=excluded.products,catalogue_expires=excluded.catalogue_expires,quote_id=null,quote_item=null,quote_fpo=null,quote_expires=null;
 if jsonb_array_length(products)=0 then return 'No produce on this page. Send SHOP to start again.';end if;
 select string_agg(ord::text||'. '||left(regexp_replace(v->>'crop','[[:cntrl:]]',' ','g'),100)||' | Grade '||(v->>'grade')||' | '||left(regexp_replace(v->>'fpo_name','[[:cntrl:]]',' ','g'),100)||' | ₹'||round((v->>'price_paise_per_kg')::numeric/100,2)::text||'/kg | '||(v->>'available_kg')||' kg',E'\n' order by ord) into reply from jsonb_array_elements(products) with ordinality e(v,ord);
 return 'Available produce — page '||page_no||E'\n'||reply||E'\n\nSend BUY 1 2 for item 1, 2 kg. Send SHOP '||(page_no+1)||' for more. List expires in 10 minutes.';
 elsif cmd ~ '^buy [1-8] [0-9]{1,5}(\.[0-9]{1,3})?$' then
 x:=regexp_match(cmd,'^buy ([1-8]) ([0-9]{1,5}(\.[0-9]{1,3})?)$');n:=x[1]::integer;qty:=x[2]::numeric;
 if s.user_id is null or s.catalogue_expires<=clock_timestamp() or n>jsonb_array_length(s.products) then return 'Send SHOP first and choose an item from the current list.';end if;
 if qty<0.001 or qty>10000 then return 'Enter a quantity from 0.001 to 10000 kg.';end if;
 p:=s.products->(n-1);
 select available_kg into live_qty from private.catalogue() where fpo_id=(p->>'fpo_id')::uuid and crop=p->>'crop' and grade=p->>'grade' and price_paise_per_kg=(p->>'price_paise_per_kg')::integer;
 if live_qty is null or qty>live_qty then return 'Stock or price changed. Send SHOP and try again.';end if;
 total:=round(qty*(p->>'price_paise_per_kg')::integer)::bigint;
 if total<1 then return 'Choose a larger quantity.';end if;
 qid:=gen_random_uuid();
 item:=jsonb_build_object('crop',p->>'crop','grade',p->>'grade','price_paise_per_kg',(p->>'price_paise_per_kg')::integer,'quantity_kg',qty);
 update private.wa_shop set quote_id=qid,quote_item=item,quote_fpo=(p->>'fpo_id')::uuid,quote_expires=clock_timestamp()+interval '10 minutes' where user_id=u;
 return 'Demo order preview: '||qty||' kg '||left(regexp_replace(p->>'crop','[[:cntrl:]]',' ','g'),100)||' | Grade '||(p->>'grade')||' | '||left(regexp_replace(p->>'fpo_name','[[:cntrl:]]',' ','g'),100)||E'\nTotal ₹'||round(total::numeric/100,2)::text||E'\nNo charge or real delivery. Stock is reserved only on confirmation. To place this exact test order within 10 minutes, send:\nCONFIRM '||qid::text;
 elsif cmd ~ '^confirm [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
 qid:=split_part(cmd,' ',2)::uuid;
 select * into o from public.orders where customer_id=u and request_key=qid and source='whatsapp_test';
 if found then return 'Order already placed. Order '||o.id::text||' | '||replace(o.status,'_',' ')||'. No duplicate order created.';end if;
 if s.quote_id is distinct from qid or s.quote_expires<=clock_timestamp() or s.quote_item is null then return 'Quote expired or invalid. Send SHOP for a fresh quote.';end if;
 begin
  oid:=private.checkout_order_for(u,s.quote_fpo,jsonb_build_array(s.quote_item),'WhatsApp test delivery - no real delivery',qid);
  update public.orders set source='whatsapp_test' where id=oid and customer_id=u and source='web';
  if not found then raise exception 'Invalid order channel';end if;
  insert into private.integration_events(channel,external_id,event_type,payload,status) values('whatsapp','test:'||qid::text,'whatsapp_test_checkout',jsonb_build_object('order_id',oid,'mode','test'),'processed');
 exception when raise_exception then
  return 'Order not placed. Stock, price or availability may have changed. Send SHOP for a fresh quote.';
 end;
 update private.wa_shop set quote_id=null,quote_item=null,quote_fpo=null,quote_expires=null where user_id=u;
 select * into o from public.orders where id=oid;
 return 'Test order confirmed! Order '||oid::text||E'\nTotal ₹'||round(o.total_paise::numeric/100,2)::text||E'\nPayment simulated. No real delivery. Send TRACK or open My orders on the website.';
 elsif cmd='track' or cmd ~ '^track [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
 if cmd='track' then select * into o from public.orders where customer_id=u and source='whatsapp_test' order by created_at desc,id desc limit 1;
 else select * into o from public.orders where id=split_part(cmd,' ',2)::uuid and customer_id=u and source='whatsapp_test';end if;
 if not found then return 'No matching WhatsApp test order for your account.';end if;
 return 'Order '||o.id::text||E'\nStatus: '||replace(o.status,'_',' ')||E'\nPayment: '||replace(o.payment_status,'_',' ')||E'\nTotal ₹'||round(o.total_paise::numeric/100,2)::text||E'\nManage or cancel eligible orders in My orders on the website.';
 elsif cmd='reset' then
 delete from private.wa_shop where user_id=u;return 'Draft cleared. Existing orders are unchanged. Send SHOP to browse.';
 else return 'Send SHOP, BUY 1 2, CONFIRM followed by your quote code, TRACK, or RESET.';end if;
end $$;
create function public.wa_order_command(p_phone text,p_command text) returns text language sql security invoker set search_path='' as $$select private.wa_order_command(p_phone,p_command)$$;
revoke all on function private.wa_order_command(text,text),public.wa_order_command(text,text) from public,anon,authenticated,service_role;
grant execute on function private.wa_order_command(text,text),public.wa_order_command(text,text) to service_role;
commit;