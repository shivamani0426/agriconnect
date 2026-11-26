begin;
-- Round 02/03: private, link-scoped conversational state. Legacy guided flows remain available.
create table private.wa_advanced_cart(
 user_id uuid primary key references private.wa_links(user_id) on delete cascade,
 products jsonb not null default '[]', items jsonb not null default '[]', fpo_id uuid,
 list_expires timestamptz, expires_at timestamptz not null default (clock_timestamp()+interval '30 minutes'),
 quote_id uuid unique, quote_expires timestamptz
);
create table private.wa_voice_permission(
 user_id uuid primary key references private.wa_links(user_id) on delete cascade,
 expires_at timestamptz not null
);
alter table private.wa_advanced_cart enable row level security;
alter table private.wa_voice_permission enable row level security;
revoke all on private.wa_advanced_cart,private.wa_voice_permission from public,anon,authenticated,service_role;
create function private.wa_money(v bigint) returns text language sql immutable set search_path='' as $$ select '₹'||round(coalesce(v,0)::numeric/100,2)::text $$;
create function private.wa_clean(v text,n integer) returns text language sql immutable set search_path='' as $$ select left(regexp_replace(coalesce(v,''),'[[:cntrl:]]',' ','g'),n) $$;
-- Only high-confidence, non-mutating language aliases. Never interpret free-form harvest names,
-- quantities, reasons or opaque confirmation codes as actions.
create function private.wa_intent(v text,r text) returns text language sql immutable set search_path='' as $$
 select case
 when lower(trim(v)) in ('help me','show menu','main menu','home','ಮೆನು','మెనూ','मेनू') then '0'
 when lower(trim(v)) in ('more options','show commands','what can i do') then 'more'
 when r='farmer' and lower(trim(v)) in ('show my earnings','my earnings','how much did i earn','my inventory','my harvest summary','ನನ್ನ ಆದಾಯ','నా ఆదాయం','मेरी कमाई') then 'summary'
 when r='customer' and lower(trim(v)) in ('show my orders','my orders','order history','ನನ್ನ ಆರ್ಡರ್‌ಗಳು','నా ఆర్డర్లు','मेरे ऑर्डर') then 'history'
 when r='customer' and lower(trim(v)) in ('show my cart','my cart','shopping cart') then 'cart'
 when r='manager' and lower(trim(v)) in ('show report','fpo report','manager report') then 'report'
 else v end
$$;
alter function private.wa_guide(text,text,boolean) rename to wa_guide_round01;
revoke all on function private.wa_guide_round01(text,text,boolean) from public,anon,authenticated,service_role;
create function private.wa_guide(p_phone text,p_text text,p_button boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; r text; g private.wa_guides%rowtype; c private.wa_advanced_cart%rowtype; cmd text; raw text:=trim(p_text); reply text; lang text; n integer; qty numeric; live_qty numeric; p jsonb; item jsonb; v_products jsonb; v_items jsonb; f uuid; token uuid; oid uuid; o public.orders%rowtype; total bigint; page integer; term text; rows_text text; received bigint; pending bigint; approved_kg numeric; available_kg numeric; reserved_kg numeric; num_h bigint; pending_h bigint; num_f bigint; num_o bigint; x text[];
begin
 if current_setting('app.wa_advanced',true) is distinct from 'on' then return private.wa_guide_round01(p_phone,p_text,p_button);end if;
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or raw is null or length(raw) not between 1 and 512 then return private.wa_guide_round01(p_phone,p_text,p_button);end if;
 select w.user_id into u from private.wa_links w where w.phone=p_phone;
 if u is null then return private.wa_guide_round01(p_phone,p_text,p_button);end if;
 select account_role into r from public.profiles where id=u for no key update;
 if not found or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone) then return jsonb_build_object('body','Link your account first.');end if;
 select * into g from private.wa_guides where user_id=u;
 lang:=coalesce(g.lang,'en');
 raw:=translate(raw,'೦೧೨೩೪೫೬೭೮೯౦౧౨౩౪౫౬౭౮౯०१२३४५६७८९','012345678901234567890123456789');
 cmd:=lower(raw);
 if not p_button and cmd='/photohelp' then return jsonb_build_object('body','Submit a harvest first. Send a JPEG, PNG or WebP image (up to 5 MB) with caption PHOTO <your pending harvest reference>. Only your own pending harvest without a photo can be updated.');end if;
 if not p_button and cmd='/voicehelp' then return jsonb_build_object('body','Voice transcription requires an administrator-configured service and /VOICE ON consent. Short Ogg voice notes only. If unavailable, type your command.');end if;
 -- Detect script only on an initial greeting, never silently override an explicit language choice.
 if not p_button and g.lang is null and cmd in ('ನಮಸ್ಕಾರ','ನಮಸ್ತೆ','నమస్కారం','నమస్తే','नमस्ते','नमस्कार') then
  perform private.wa_guide_round01(p_phone,'HI',false);
  return private.wa_guide_round01(p_phone,case when cmd in ('ನಮಸ್ಕಾರ','ನಮಸ್ತೆ') then '2' when cmd in ('నమస్కారం','నమస్తే') then '3' else '4' end,false);
 end if;
 if not p_button and (g.step is null or g.step='menu' or g.expires_at<=clock_timestamp()) then cmd:=lower(private.wa_intent(raw,r));end if;
 select * into c from private.wa_advanced_cart where user_id=u;
 -- Cart confirmations remain actual signed button events, not text or voice.
 if p_button then
  if r='customer' and cmd ~ '^ac_(confirm|cancel):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   token:=split_part(cmd,':',2)::uuid;
   if cmd like 'ac_confirm:%' and exists(select 1 from public.orders where customer_id=u and request_key=token and source='whatsapp_test') then return jsonb_build_object('body','This test order is already confirmed. Send HISTORY for details.');end if;
   if c.quote_id=token then
    if c.quote_expires<=clock_timestamp() or c.expires_at<=clock_timestamp() then return jsonb_build_object('body','Cart quote expired. Send CHECKOUT for a fresh preview.');end if;
    if cmd like 'ac_cancel:%' then update private.wa_advanced_cart set quote_id=null,quote_expires=null where user_id=u;return jsonb_build_object('body','Checkout cancelled. Cart kept. No order placed.');end if;
    begin
     oid:=private.checkout_order_for(u,c.fpo_id,c.items,'WhatsApp test delivery - no real delivery',token);
     update public.orders set source='whatsapp_test' where id=oid and customer_id=u and source='web';
     if not found then raise exception 'Invalid order channel';end if;
     insert into private.integration_events(channel,external_id,event_type,payload,status) values('whatsapp','test:'||token::text,'whatsapp_test_checkout',jsonb_build_object('order_id',oid,'mode','test'),'processed');
    exception when raise_exception then
     update private.wa_advanced_cart set quote_id=null,quote_expires=null where user_id=u;
     return jsonb_build_object('body','Order not placed. Stock, price or availability changed. Review your cart and search again.');
    end;
    delete from private.wa_advanced_cart where user_id=u;
    select * into o from public.orders where id=oid;
    return jsonb_build_object('body','Test order confirmed! '||oid::text||E'\nTotal: '||private.wa_money(o.total_paise)||E'\nPayment simulated. No real delivery. Send HISTORY.');
   end if;
  end if;
  return private.wa_guide_round01(p_phone,p_text,true);
 end if;
 -- Cancel old cart quotes on any later non-button interaction except explicitly reviewing the cart.
 if cmd not in ('cart','checkout') then update private.wa_advanced_cart set quote_id=null,quote_expires=null where user_id=u;end if;
 -- Preserve active guided input: only explicit slash commands interrupt an unfinished step.
 if g.step is not null and g.step not in ('menu','language') and g.expires_at>clock_timestamp() and raw not like '/%' then return private.wa_guide_round01(p_phone,p_text,false);end if;
 if raw like '/%' then
  cmd:=lower(trim(substring(raw from 2)));
  if g.step not in ('menu','language') then perform private.wa_guide_round01(p_phone,'0',false);end if;
 end if;
 if cmd in ('0','hi','hello','help','menu','language','3 languages') then
  update private.wa_advanced_cart set quote_id=null,quote_expires=null where user_id=u;
  return private.wa_guide_round01(p_phone,cmd,false);
 elsif cmd='more' then
  return jsonb_build_object('body',case r when 'farmer' then 'Farmer commands: SUMMARY (harvest, stock, estimated earnings), HARVESTS (references). To attach a crop photo, submit a harvest first and send a photo with caption PHOTO <harvest reference>.'
  when 'customer' then 'Customer commands: SEARCH tomatoes, ADD 1 2 (item 1, 2 kg), CART, REMOVE 1, CLEARCART, CHECKOUT, HISTORY, HISTORY 2, STATUS <order reference>. One FPO per cart.'
  when 'manager' then 'Manager commands: REPORT (your FPOs), REPORT 2 (next page). Send 0 for review, membership and order operations.' else 'Link your account first.' end||E'\nVoice: /VOICE ON permits a configured transcription service for 10 minutes; /VOICE OFF revokes permission. Send 0 for menu. Prefix a command with / to leave guided input.');
 elsif cmd='voice on' or cmd='voice off' then
  if cmd='voice on' then insert into private.wa_voice_permission(user_id,expires_at) values(u,clock_timestamp()+interval '10 minutes') on conflict(user_id) do update set expires_at=excluded.expires_at;
   return jsonb_build_object('body','Voice permission granted for 10 minutes. If enabled by the administrator, audio goes to the configured speech-to-text service. Transcripts are previews only; send text to execute. Send /VOICE OFF to revoke.');
  else delete from private.wa_voice_permission where user_id=u;return jsonb_build_object('body','Voice permission revoked.');end if;
 elsif cmd='summary' and r='farmer' then
  select count(*),count(*) filter(where status='pending'),coalesce(sum(quantity_kg) filter(where status='approved'),0) into num_h,pending_h,approved_kg from public.harvests where farmer_id=u;
  select coalesce(sum(i.available_kg),0),coalesce(sum(i.reserved_kg),0) into available_kg,reserved_kg from public.inventory_lots i join public.harvests h on h.id=i.harvest_id where h.farmer_id=u;
  select coalesce(sum(payout_paise) filter(where status='delivered'),0),coalesce(sum(payout_paise) filter(where status='reserved'),0) into received,pending from public.order_allocations where farmer_id=u;
  return jsonb_build_object('body','Your farmer summary (test estimates)'||E'\nHarvests: '||num_h||' | Pending review: '||pending_h||E'\nApproved: '||approved_kg||' kg'||E'\nAvailable: '||available_kg||' kg | Reserved: '||reserved_kg||' kg'||E'\nDelivered allocation estimate: '||private.wa_money(received)||E'\nReserved allocation estimate: '||private.wa_money(pending)||E'\nNo actual payout or payment. Send HARVESTS for records.');
 elsif cmd ~ '^report( [1-9][0-9]{0,2})?$' and r='manager' then
  page:=coalesce(nullif(split_part(cmd,' ',2),''),'1')::integer;
  select string_agg(private.wa_clean(z.name,100)||' | Farmers: '||z.farmers||' | Pending harvests: '||z.harvests||' | Open orders: '||z.orders||' | Available kg: '||z.stock||' | Delivered test value: '||private.wa_money(z.revenue),E'\n' order by z.name,z.id) into rows_text from (
   select f.id,f.name,
    (select count(*) from public.memberships m where m.fpo_id=f.id and m.role='farmer' and m.status='active') farmers,
    (select count(*) from public.harvests h where h.fpo_id=f.id and h.status='pending') harvests,
    (select count(*) from public.orders o where o.fpo_id=f.id and o.status in ('confirmed','packed','out_for_delivery')) orders,
    (select coalesce(sum(i.available_kg),0) from public.inventory_lots i where i.fpo_id=f.id) stock,
    (select coalesce(sum(o.total_paise),0) from public.orders o where o.fpo_id=f.id and o.status='delivered') revenue
   from public.fpos f join public.memberships m on m.fpo_id=f.id where m.user_id=u and m.role='manager' and m.status='active' order by f.name,f.id limit 5 offset ((page-1)*5)
  ) z;
  return jsonb_build_object('body','Your FPO report — page '||page||E'\n'||coalesce(rows_text,'No managed FPO on this page.')||E'\nTest data only. REPORT '||(page+1)||' for more; 0 for operations.');
 elsif r='customer' and (cmd='search' or cmd like 'search %') then
  term:=trim(substring(cmd from 7));if length(term)>100 then return jsonb_build_object('body','Search term must be at most 100 characters.');end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.fpo_name,z.crop,z.grade,z.price_paise_per_kg,z.fpo_id),'[]') into v_products from (select * from private.catalogue() q where term='' or strpos(lower(q.crop),term)>0 order by fpo_name,crop,grade,price_paise_per_kg,fpo_id limit 8) z;
  insert into private.wa_advanced_cart(user_id,products,list_expires) values(u,v_products,clock_timestamp()+interval '10 minutes')
  on conflict(user_id) do update set products=excluded.products,list_expires=excluded.list_expires,items=case when wa_advanced_cart.expires_at>clock_timestamp() then wa_advanced_cart.items else '[]'::jsonb end,fpo_id=case when wa_advanced_cart.expires_at>clock_timestamp() then wa_advanced_cart.fpo_id end,expires_at=clock_timestamp()+interval '30 minutes',quote_id=null,quote_expires=null;
  select string_agg(ord||'. '||private.wa_clean(v->>'crop',100)||' | '||(v->>'grade')||' | '||private.wa_clean(v->>'fpo_name',100)||' | '||private.wa_money((v->>'price_paise_per_kg')::bigint)||'/kg | '||(v->>'available_kg')||' kg',E'\n' order by ord) into rows_text from jsonb_array_elements(v_products) with ordinality e(v,ord);
  return jsonb_build_object('body','Search results'||E'\n'||coalesce(rows_text,'No matching produce. Try another crop.')||E'\nADD 1 2 adds item 1, 2 kg. CART to review. Results expire in 10 minutes.');
 elsif r='customer' and cmd ~ '^add [1-8] [0-9]{1,5}(\.[0-9]{1,3})?$' then
  x:=regexp_match(cmd,'^add ([1-8]) ([0-9]{1,5}(\.[0-9]{1,3})?)$');n:=x[1]::integer;qty:=x[2]::numeric;
  if c.user_id is null or c.list_expires<=clock_timestamp() or c.expires_at<=clock_timestamp() or n>jsonb_array_length(c.products) then return jsonb_build_object('body','Search results expired. Send SEARCH again.');end if;
  p:=c.products->(n-1);f:=(p->>'fpo_id')::uuid;
  if c.fpo_id is not null and c.fpo_id<>f then return jsonb_build_object('body','One FPO per cart. Finish this cart or CLEARCART before choosing another FPO.');end if;
  select available_kg into live_qty from private.catalogue() q where q.fpo_id=f and q.crop=p->>'crop' and q.grade=p->>'grade' and q.price_paise_per_kg=(p->>'price_paise_per_kg')::integer;
  select coalesce(sum((v->>'quantity_kg')::numeric),0) into approved_kg from jsonb_array_elements(c.items) v where v->>'crop'=p->>'crop' and v->>'grade'=p->>'grade' and v->>'price_paise_per_kg'=p->>'price_paise_per_kg';
  if qty<0.001 then return jsonb_build_object('body','Enter a positive quantity.');end if;
  qty:=qty+approved_kg;
  if qty<0.001 or qty>10000 or live_qty is null or qty>live_qty or round(qty*(p->>'price_paise_per_kg')::numeric)<1 then return jsonb_build_object('body','Quantity or stock unavailable. Search again and choose a valid quantity.');end if;
  select coalesce(jsonb_agg(v order by ord),'[]') into v_items from jsonb_array_elements(c.items) with ordinality e(v,ord) where not(v->>'crop'=p->>'crop' and v->>'grade'=p->>'grade' and v->>'price_paise_per_kg'=p->>'price_paise_per_kg');
  if jsonb_array_length(v_items)>=10 then return jsonb_build_object('body','Cart limit: 10 distinct products.');end if;
  item:=jsonb_build_object('crop',p->>'crop','grade',p->>'grade','price_paise_per_kg',(p->>'price_paise_per_kg')::integer,'quantity_kg',qty);
  update private.wa_advanced_cart set items=v_items||jsonb_build_array(item),fpo_id=f,quote_id=null,quote_expires=null,expires_at=clock_timestamp()+interval '30 minutes' where user_id=u;
  return jsonb_build_object('body','Added to cart. Send CART or continue SEARCH/ADD. No stock reserved yet.');
 elsif r='customer' and cmd ~ '^remove [1-9][0-9]?$' then
  n:=split_part(cmd,' ',2)::integer;
  if c.user_id is null or c.expires_at<=clock_timestamp() or n>jsonb_array_length(c.items) then return jsonb_build_object('body','No matching cart item. Send CART.');end if;
  v_items:=c.items-(n-1);
  update private.wa_advanced_cart set items=v_items,fpo_id=case when jsonb_array_length(v_items)=0 then null else c.fpo_id end,quote_id=null,quote_expires=null where user_id=u;
  return jsonb_build_object('body','Item removed. Send CART.');
 elsif r='customer' and cmd='clearcart' then
  delete from private.wa_advanced_cart where user_id=u;return jsonb_build_object('body','Cart cleared. Existing orders are unchanged.');
 elsif r='customer' and cmd in ('cart','checkout') then
  if c.user_id is null or c.expires_at<=clock_timestamp() or jsonb_array_length(c.items)=0 then return jsonb_build_object('body','Cart empty or expired. Send SEARCH to browse.');end if;
  select string_agg(ord||'. '||private.wa_clean(v->>'crop',100)||' | '||(v->>'grade')||' | '||(v->>'quantity_kg')||' kg | '||private.wa_money(round((v->>'quantity_kg')::numeric*(v->>'price_paise_per_kg')::numeric)::bigint),E'\n' order by ord),sum(round((v->>'quantity_kg')::numeric*(v->>'price_paise_per_kg')::numeric))::bigint into rows_text,total from jsonb_array_elements(c.items) with ordinality e(v,ord);
  if cmd='cart' then return jsonb_build_object('body','Your test cart'||E'\n'||rows_text||E'\nEstimated total: '||private.wa_money(total)||E'\nREMOVE 1, CHECKOUT or CLEARCART.');end if;
  if exists(select 1 from jsonb_array_elements(c.items) v where not exists(select 1 from private.catalogue() q where q.fpo_id=c.fpo_id and q.crop=v->>'crop' and q.grade=v->>'grade' and q.price_paise_per_kg=(v->>'price_paise_per_kg')::integer and q.available_kg>=(v->>'quantity_kg')::numeric)) then return jsonb_build_object('body','Stock or price changed. Review cart before checkout.');end if;
  token:=gen_random_uuid();
  reply:='Confirm test checkout'||E'\n'||rows_text||E'\nTotal: '||private.wa_money(total)||E'\nNo real payment or delivery. Confirm exact cart.';
  if length(reply)>1024 then return jsonb_build_object('body','Cart preview is too long for a confirmation. Remove an item and retry.');end if;
  update private.wa_advanced_cart set quote_id=token,quote_expires=least(expires_at,clock_timestamp()+interval '5 minutes') where user_id=u;
  return jsonb_build_object('body',reply,'buttons',jsonb_build_array(jsonb_build_object('id','ac_confirm:'||token,'title',private.wa_phrase(lang,'confirm')),jsonb_build_object('id','ac_cancel:'||token,'title',private.wa_phrase(lang,'cancel'))));
 elsif r='customer' and cmd ~ '^history( [1-9][0-9]{0,2})?$' then
  page:=coalesce(nullif(split_part(cmd,' ',2),''),'1')::integer;
  select string_agg(z.id::text||' | '||replace(z.status,'_',' ')||' | '||private.wa_money(z.total_paise)||' | '||z.source||' | '||to_char(z.created_at at time zone 'Asia/Kolkata','DD Mon HH24:MI'),E'\n' order by z.created_at desc,z.id desc) into rows_text from (select * from public.orders where customer_id=u order by created_at desc,id desc limit 5 offset ((page-1)*5)) z;
  return jsonb_build_object('body','Your order history — page '||page||E'\n'||coalesce(rows_text,'No orders on this page.')||E'\nSTATUS <reference> for timeline. HISTORY '||(page+1)||' for more.');
 elsif r='customer' and cmd ~ '^status [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  select * into o from public.orders where id=split_part(cmd,' ',2)::uuid and customer_id=u;
  if not found then return jsonb_build_object('body','No matching order for your account.');end if;
  select string_agg(replace(z.status,'_',' ')||' — '||to_char(z.created_at at time zone 'Asia/Kolkata','DD Mon YYYY HH24:MI'),E'\n' order by z.id) into rows_text from (select * from public.order_events where order_id=o.id order by id desc limit 20) z;
  return jsonb_build_object('body','Order '||o.id||E'\nStatus: '||replace(o.status,'_',' ')||E'\nTotal: '||private.wa_money(o.total_paise)||E'\nPayment: '||replace(o.payment_status,'_',' ')||E'\nTimeline (IST):\n'||coalesce(rows_text,'No events.'));
 end if;
 return private.wa_guide_round01(p_phone,p_text,p_button);
end $$;
create or replace function public.wa_guide(p_phone text,p_text text,p_button boolean) returns jsonb language sql security invoker set search_path='' as $$select private.wa_guide(p_phone,p_text,p_button)$$;
revoke all on function private.wa_money(bigint),private.wa_clean(text,integer),private.wa_intent(text,text),private.wa_guide(text,text,boolean),public.wa_guide(text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function private.wa_guide(text,text,boolean),public.wa_guide(text,text,boolean) to service_role;
-- Opt-in per transaction: migration alone does not switch the live guide.
create function private.wa_advanced_prepare(p_id text,p_phone text,p_route text,p_command text) returns boolean language plpgsql security definer set search_path='' as $$
declare ok boolean;
begin
 perform set_config('app.wa_advanced','on',true);
 ok:=private.wa_relay_prepare(p_id,p_phone,p_route,p_command);
 if ok then
  -- Append the discoverable text fallback only to generated role menus, after list validation.
  update private.wa_relay_outbox q set reply=jsonb_set(q.reply,'{body}',to_jsonb((q.reply->>'body')||E'\nMORE: additional commands. /MORE: leave current input.'))
   where q.message_hash=p_id and q.reply ? 'list' and length(q.reply->>'body')<900
   and exists(select 1 from private.wa_guides g where g.user_id=q.link_user and g.step='menu');
 end if;
 return ok;
end $$;
create function public.wa_advanced_prepare(p_id text,p_phone text,p_route text,p_command text) returns boolean language sql security invoker set search_path='' as $$select private.wa_advanced_prepare(p_id,p_phone,p_route,p_command)$$;
revoke all on function private.wa_advanced_prepare(text,text,text,text),public.wa_advanced_prepare(text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function private.wa_advanced_prepare(text,text,text,text),public.wa_advanced_prepare(text,text,text,text) to service_role;
commit;
