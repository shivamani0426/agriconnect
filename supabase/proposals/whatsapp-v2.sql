-- Candidate schema: run on disposable CI only until migration and release approved.
begin;
create table private.wa_v2_outbox(
 message_hash text primary key references public.whatsapp_webhook_receipts(message_hash) on delete cascade,
 sender_hash text not null check(sender_hash ~ '^[a-f0-9]{64}$'),
 user_id uuid references private.wa_links(user_id) on delete cascade, linked_at timestamptz,
 reply jsonb, state text not null default 'queued' check(state in ('queued','sending','retry','accepted','uncertain','failed','expired')),
 attempts integer not null default 0 check(attempts between 0 and 3),
 created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 next_at timestamptz not null default clock_timestamp(), attempt_token uuid,
 provider_hash text unique check(provider_hash is null or provider_hash ~ '^[a-f0-9]{64}$'),
 delivery text check(delivery in ('sent','delivered','read','failed')), error_code integer, latency_ms integer check(latency_ms between 0 and 60000)
);
create index wa_v2_sender_idx on private.wa_v2_outbox(sender_hash,created_at desc);
create index wa_v2_expiry_idx on private.wa_v2_outbox(expires_at) where reply is not null;
alter table private.wa_v2_outbox enable row level security;
revoke all on private.wa_v2_outbox from public,anon,authenticated,service_role;
create table private.wa_v2_nav(user_id uuid primary key references private.wa_links(user_id) on delete cascade, token uuid not null, actions text[] not null, expires_at timestamptz not null);
create table private.wa_v2_cart(user_id uuid primary key references private.wa_links(user_id) on delete cascade, fpo_id uuid, items jsonb not null default '[]', quote_id uuid, expires_at timestamptz not null);
alter table private.wa_v2_nav enable row level security;
alter table private.wa_v2_cart enable row level security;
revoke all on private.wa_v2_nav,private.wa_v2_cart from public,anon,authenticated,service_role;
create function private.wa_v2_text(t text) returns jsonb language sql immutable set search_path='' as $$select jsonb_build_object('body',left(t,4096))$$;
-- All new commands require a verified linked account. The old commands retain their own checks.
create function private.wa_v2_action(p_phone text,p_text text,p_mode text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; r text; cmd text:=lower(trim(p_text)); v text:=trim(p_text); g private.wa_guides%rowtype; nav private.wa_v2_nav%rowtype; cart private.wa_v2_cart%rowtype; shop private.wa_shop%rowtype; actions text[]; titles text[]; token uuid; x text[]; result text; p jsonb; products jsonb; it jsonb; f uuid; qty numeric; total bigint; oid uuid; n integer; i integer; n_fpo integer; l text;
begin
 if p_mode='link' then
  return private.wa_v2_text(case when private.wa_redeem(p_phone,p_text::uuid)='linked' then 'WhatsApp linked successfully. Send HI to start.' else 'Link not completed. Use a fresh code from your own profile.' end);
 end if;
 select user_id into u from private.wa_links where phone=p_phone;
 if not found then return private.wa_v2_text('Link your AgriConnect account in Profile first: https://agriconnect-q7c2.onrender.com/');end if;
 select account_role into r from public.profiles where id=u for no key update;
 if not found or not exists(select 1 from private.wa_links where phone=p_phone and user_id=u) then return private.wa_v2_text('Link your account first.');end if;
 select * into g from private.wa_guides where user_id=u;
 l:=coalesce(g.lang,'en');
 if p_mode='audio' then return private.wa_v2_text('Voice transcription is not enabled. Please type your message or use your keyboard microphone to dictate.');end if;
 if p_mode='image' then return private.wa_v2_text('Photo upload through WhatsApp is not enabled. Use the secure harvest form on https://agriconnect-q7c2.onrender.com/ . No image was downloaded.');end if;
 if p_mode='button' then return private.wa_guide(p_phone,v,true);end if;
 if p_mode='list' then
  x:=regexp_match(cmd,'^ac_nav:([0-9a-f-]{36}):([1-6])$');
  select * into nav from private.wa_v2_nav where user_id=u;
  if x is null or nav.token::text is distinct from x[1] or nav.expires_at<=clock_timestamp() or x[2]::int>cardinality(nav.actions) then return private.wa_v2_text('Menu expired. Send QUICK for a fresh menu.');end if;
  delete from private.wa_v2_nav where user_id=u;
  cmd:=nav.actions[x[2]::int];v:=cmd;
 elsif p_mode<>'text' then return private.wa_v2_text('Send HI for help.');end if;
 -- Only unambiguous native greetings choose an initial language; never override a saved preference.
 if g.lang is null and cmd in ('ನಮಸ್ಕಾರ','నమస్కారం','नमस्ते') then
  perform private.wa_guide(p_phone,'hi',false);
  return private.wa_guide(p_phone,case cmd when 'ನಮಸ್ಕಾರ' then '2' when 'నమస్కారం' then '3' else '4' end,false);
 end if;
 if cmd in ('quick','quick menu') then
  if r='farmer' then actions:=array['fpos','harvests','earnings','farm summary','menu'];titles:=array['Submit harvest','My harvests','Earnings','Farm summary','Main menu'];
  elsif r='customer' then actions:=array['shop','orders','cart','track','menu'];titles:=array['Browse produce','My orders','Shopping cart','Latest WA order','Main menu'];
  elsif r='manager' then actions:=array['manager report','alerts','menu'];titles:=array['FPO report','Notifications','Operations menu'];
  else return private.wa_v2_text('Complete your profile first.');end if;
  if l='kn' then
   if r='farmer' then titles:=array['ಬೆಳೆ ಸಲ್ಲಿಸಿ','ನನ್ನ ಬೆಳೆಗಳು','ಆದಾಯ','ಬೆಳೆ ಸಾರಾಂಶ','ಮುಖ್ಯ ಮೆನು'];
   elsif r='customer' then titles:=array['ಉತ್ಪನ್ನಗಳು','ನನ್ನ ಆದೇಶಗಳು','ಕಾರ್ಟ್','ಆದೇಶ ಸ್ಥಿತಿ','ಮುಖ್ಯ ಮೆನು'];
   else titles:=array['FPO ವರದಿ','ಸೂಚನೆಗಳು','ಮುಖ್ಯ ಮೆನು'];end if;
  elsif l='te' then
   if r='farmer' then titles:=array['పంట నమోదు','నా పంటలు','ఆదాయం','పంట సారాంశం','ప్రధాన మెనూ'];
   elsif r='customer' then titles:=array['ఉత్పత్తులు','నా ఆర్డర్లు','కార్ట్','ఆర్డర్ స్థితి','ప్రధాన మెనూ'];
   else titles:=array['FPO నివేదిక','సూచనలు','ప్రధాన మెనూ'];end if;
  elsif l='hi' then
   if r='farmer' then titles:=array['फसल जमा करें','मेरी फसलें','कमाई','फसल सारांश','मुख्य मेनू'];
   elsif r='customer' then titles:=array['उत्पाद देखें','मेरे ऑर्डर','कार्ट','ऑर्डर स्थिति','मुख्य मेनू'];
   else titles:=array['FPO रिपोर्ट','सूचनाएँ','मुख्य मेनू'];end if;
  end if;
  token:=gen_random_uuid();insert into private.wa_v2_nav values(u,token,actions,clock_timestamp()+interval '10 minutes') on conflict(user_id) do update set token=excluded.token,actions=excluded.actions,expires_at=excluded.expires_at;
  select jsonb_agg(jsonb_build_object('id','ac_nav:'||token||':'||j,'title',titles[j]) order by j) into p from generate_subscripts(actions,1) j;
  return jsonb_build_object('body',case l when 'kn' then 'AgriConnect: ಒಂದು ಆಯ್ಕೆ ಆರಿಸಿ (ಪರೀಕ್ಷೆ).' when 'te' then 'AgriConnect: ఒక ఎంపికను ఎంచుకోండి (పరీక్ష).' when 'hi' then 'AgriConnect: एक विकल्प चुनें (परीक्षण)।' else 'AgriConnect quick actions (test). Choose an option.' end,'list',p);
 end if;
 -- Explicit, limited aliases. No fuzzy matching of destructive commands.
 if cmd in ('my earnings','how much did i earn','ನನ್ನ ಆದಾಯ','నా ఆదాయం','मेरी कमाई') then cmd:='earnings';
 elsif cmd in ('my orders','show my orders','ನನ್ನ ಆದೇಶಗಳು','నా ఆర్డర్లు','मेरे ऑर्डर') then cmd:='orders';
 elsif cmd in ('my harvests','show my harvests','ನನ್ನ ಬೆಳೆಗಳು','నా పంటలు','मेरी फसलें') then cmd:='harvests';v:=cmd;
 elsif cmd in ('show inventory','fpo report') then cmd:='manager report';end if;
 if cmd='earnings' and r='farmer' then
  select 'Simulated earnings (not paid): delivered ₹'||round(coalesce(sum(payout_paise) filter(where status='delivered'),0)::numeric/100,2)||'; reserved estimate ₹'||round(coalesce(sum(payout_paise) filter(where status='reserved'),0)::numeric/100,2) into result from public.order_allocations where farmer_id=u;
  return private.wa_v2_text(result);
 elsif cmd='farm summary' and r='farmer' then
  select 'Your harvests: '||count(*)||'; pending '||count(*) filter(where status='pending')||'; approved '||count(*) filter(where status='approved')||'; rejected '||count(*) filter(where status='rejected') into result from public.harvests where farmer_id=u;
  return private.wa_v2_text(result);
 elsif cmd='manager report' and r='manager' then
  select 'Your active FPOs: '||count(*) into result from public.memberships where user_id=u and role='manager' and status='active';
  result:=result||E'\nPending harvests: '||(select count(*) from public.harvests h where h.status='pending' and exists(select 1 from public.memberships m where m.fpo_id=h.fpo_id and m.user_id=u and m.role='manager' and m.status='active'))||E'\nOpen orders: '||(select count(*) from public.orders o where o.status in ('confirmed','packed','out_for_delivery') and exists(select 1 from public.memberships m where m.fpo_id=o.fpo_id and m.user_id=u and m.role='manager' and m.status='active'))||E'\nPublished stock: '||(select coalesce(sum(a.available_kg),0) from public.inventory_lots a where a.published and exists(select 1 from public.memberships m where m.fpo_id=a.fpo_id and m.user_id=u and m.role='manager' and m.status='active'))||' kg';
  return private.wa_v2_text(result);
 elsif r='customer' and (cmd='orders' or cmd ~ '^orders [1-9][0-9]{0,2}$') then
  n:=coalesce(nullif(split_part(cmd,' ',2),''),'1')::int;
  select string_agg(z.id||' | '||z.status||' | ₹'||round(z.total_paise::numeric/100,2)||' | '||z.source,E'\n' order by z.created_at desc,z.id desc) into result from (select * from public.orders where customer_id=u order by created_at desc,id desc limit 8 offset (n-1)*8) z;
  return private.wa_v2_text(coalesce('Your orders — page '||n||E'\n'||result||E'\nSend ORDER <reference> for details or ORDERS '||(n+1)||' for next page.','No orders on this page.'));
 elsif r='customer' and cmd ~ '^order [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  select 'Order '||id||E'\nStatus: '||status||E'\nPayment: '||payment_status||E'\nTotal ₹'||round(total_paise::numeric/100,2)||E'\nChannel: '||source into result from public.orders where customer_id=u and id=split_part(cmd,' ',2)::uuid;
  return private.wa_v2_text(coalesce(result,'No matching order for your account.'));
 elsif r='farmer' and cmd ~ '^i harvested ' then
  x:=regexp_match(v,'^I harvested ([0-9]{1,9}([.][0-9]{1,3})?) kg ([^|[:cntrl:]]{1,100}) today$','i');
  if x is null then return private.wa_v2_text('Try: I harvested 25 kg Tomatoes today. No harvest is submitted until you confirm.');end if;
  select count(*) into n_fpo from public.memberships where user_id=u and role='farmer' and status='active';
  if n_fpo<>1 then return private.wa_v2_text('Choose your FPO first: send FPOS, then use the harvest instructions.');end if;
  perform private.wa_harvest_command(p_phone,'FPOS');
  return private.wa_v2_text(private.wa_harvest_command(p_phone,'HARVEST 1 | '||x[3]||' | '||x[1]||' | '||((now() at time zone 'Asia/Kolkata')::date)::text));
 elsif r='customer' and cmd ~ '^search .{1,100}$' then
  select coalesce(jsonb_agg(to_jsonb(z) order by z.fpo_name,z.crop,z.grade,z.price_paise_per_kg,z.fpo_id),'[]') into products from (select * from private.catalogue() where strpos(lower(crop),lower(trim(substr(v,8))))>0 order by fpo_name,crop,grade,price_paise_per_kg,fpo_id limit 8) z;
  insert into private.wa_shop(user_id,products,catalogue_expires) values(u,products,clock_timestamp()+interval '10 minutes') on conflict(user_id) do update set products=excluded.products,catalogue_expires=excluded.catalogue_expires,quote_id=null,quote_item=null,quote_fpo=null,quote_expires=null;
  select string_agg(ord||'. '||left(regexp_replace(z->>'crop','[[:cntrl:]]',' ','g'),100)||' | '||left(regexp_replace(z->>'fpo_name','[[:cntrl:]]',' ','g'),100)||' | Grade '||(z->>'grade')||' | ₹'||round((z->>'price_paise_per_kg')::numeric/100,2)||'/kg | '||(z->>'available_kg')||' kg',E'\n' order by ord) into result from jsonb_array_elements(products) with ordinality a(z,ord);
  return private.wa_v2_text(coalesce('Matching produce (first 8):'||E'\n'||result||E'\nSend ADD 1 2 to add 2 kg of item 1. Send CART to review.','No matching produce.'));
 elsif r='customer' and (cmd='cart' or cmd='clear cart' or cmd='checkout cart' or cmd ~ '^add ' or cmd ~ '^cart confirm ') then
  select * into cart from private.wa_v2_cart where user_id=u;
  if cmd='clear cart' then delete from private.wa_v2_cart where user_id=u;return private.wa_v2_text('Cart cleared. Existing orders are unchanged.');end if;
  if cmd ~ '^cart confirm [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} is null or cart.quote_id::text<>split_part(cmd,' ',3) or cart.expires_at<=clock_timestamp() then return private.wa_v2_text('Cart quote expired or invalid. Send CHECKOUT CART again.');end if;
   begin
    oid:=private.checkout_order_for(u,cart.fpo_id,cart.items,'WhatsApp test delivery - no real delivery',cart.quote_id);
    update public.orders set source='whatsapp_test' where id=oid and customer_id=u and source='web';
    if not found then raise exception 'Invalid order channel';end if;
    insert into private.integration_events(channel,external_id,event_type,payload,status) values('whatsapp','test:'||cart.quote_id::text,'whatsapp_test_checkout',jsonb_build_object('order_id',oid,'mode','test'),'processed');
   exception when raise_exception then return private.wa_v2_text('Order not placed. Stock or price may have changed. Search again and rebuild cart.');end;
   delete from private.wa_v2_cart where user_id=u;
   return private.wa_v2_text('Test order confirmed: '||oid||'. No actual payment or delivery. Send ORDERS.');
  end if;
  if cmd ~ '^add ' then
   x:=regexp_match(cmd,'^add ([1-8]) ([0-9]{1,5}([.][0-9]{1,3})?)$');
   if x is null then return private.wa_v2_text('Use ADD 1 2 for item 1, 2 kg.');end if;
   select * into shop from private.wa_shop where user_id=u;
   n:=x[1]::int;qty:=x[2]::numeric;
   if shop.catalogue_expires is null or shop.catalogue_expires<=clock_timestamp() or n>jsonb_array_length(shop.products) or qty<0.001 or qty>10000 then return private.wa_v2_text('Search again and choose valid quantity.');end if;
   p:=shop.products->(n-1);f:=(p->>'fpo_id')::uuid;
   if cart.expires_at is null or cart.expires_at<=clock_timestamp() then cart.items:='[]';cart.fpo_id:=f;end if;
   if cart.fpo_id<>f then return private.wa_v2_text('One FPO per cart. Clear cart before switching FPO.');end if;
   if exists(select 1 from jsonb_array_elements(cart.items) j where j->>'crop'=p->>'crop' and j->>'grade'=p->>'grade' and (j->>'price_paise_per_kg')::int=(p->>'price_paise_per_kg')::int) then return private.wa_v2_text('Item already in cart. Clear cart to change quantities.');end if;
   if jsonb_array_length(cart.items)>=8 or not exists(select 1 from private.catalogue() c where c.fpo_id=f and c.crop=p->>'crop' and c.grade=p->>'grade' and c.price_paise_per_kg=(p->>'price_paise_per_kg')::int and c.available_kg>=qty) then return private.wa_v2_text('Cart limit or stock/price changed.');end if;
   it:=jsonb_build_object('crop',p->>'crop','grade',p->>'grade','price_paise_per_kg',(p->>'price_paise_per_kg')::int,'quantity_kg',qty);
   cart.items:=cart.items||jsonb_build_array(it);
   insert into private.wa_v2_cart(user_id,fpo_id,items,expires_at) values(u,f,cart.items,clock_timestamp()+interval '10 minutes') on conflict(user_id) do update set fpo_id=excluded.fpo_id,items=excluded.items,expires_at=excluded.expires_at,quote_id=null;
  end if;
  if cart.items is null or jsonb_array_length(cart.items)=0 or (cmd not like 'add %' and cart.expires_at<=clock_timestamp()) then return private.wa_v2_text('Cart empty or expired. Send SEARCH Tomatoes or SHOP.');end if;
  select sum(round((j->>'quantity_kg')::numeric*(j->>'price_paise_per_kg')::int))::bigint,string_agg(left(regexp_replace(j->>'crop','[[:cntrl:]]',' ','g'),100)||' | '||(j->>'grade')||' | '||(j->>'quantity_kg')||' kg | ₹'||round((j->>'quantity_kg')::numeric*(j->>'price_paise_per_kg')::int/100,2),E'\n' order by ord) into total,result from jsonb_array_elements(cart.items) with ordinality a(j,ord);
  if cmd='checkout cart' then
   if total<1 or exists(select 1 from jsonb_array_elements(cart.items) j where not exists(select 1 from private.catalogue() c where c.fpo_id=cart.fpo_id and c.crop=j->>'crop' and c.grade=j->>'grade' and c.price_paise_per_kg=(j->>'price_paise_per_kg')::int and c.available_kg>=(j->>'quantity_kg')::numeric)) then return private.wa_v2_text('Stock or price changed. Clear cart and search again.');end if;
   token:=gen_random_uuid();update private.wa_v2_cart set quote_id=token,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
   return private.wa_v2_text('Test checkout preview:'||E'\n'||result||E'\nTotal ₹'||round(total::numeric/100,2)||E'\nNo real payment. Send CART CONFIRM '||token||' within 10 minutes.');
  end if;
  return private.wa_v2_text('Cart:'||E'\n'||result||E'\nTotal ₹'||round(total::numeric/100,2)||E'\nCHECKOUT CART or CLEAR CART. No stock reserved yet.');
 end if;
 if cmd in ('earnings','farm summary','manager report','orders','cart','clear cart','checkout cart') or cmd ~ '^(search|add|order|cart confirm|i harvested) ' then return private.wa_v2_text('This action is not available for your role or format. Send QUICK.');end if;
 if cmd ~ '^(shop|buy|confirm|track|reset)( |$)' then return private.wa_v2_text(private.wa_order_command(p_phone,cmd));end if;
 if cmd ~ '^(fpos|harvest|submit|harvests|harvestreset)( |$)' then return private.wa_v2_text(private.wa_harvest_command(p_phone,v));end if;
 if cmd ~ '^(alerts|read)( |$)' then return private.wa_v2_text(private.wa_manager_command(p_phone,cmd));end if;
 -- New explicit shortcut to recover context without replaying a mutation.
 if cmd='recover' then
  if r='farmer' then return private.wa_v2_text(private.wa_harvest_command(p_phone,'HARVESTS'));
  elsif r='customer' then return private.wa_v2_text(private.wa_order_command(p_phone,'TRACK'));
  else return private.wa_guide(p_phone,'menu',false);end if;
 end if;
 return private.wa_guide(p_phone,v,false);
end $$;
-- Atomically commit operation and its reply; old receipts remain deduplication tombstones.
create function private.wa_v2_prepare(p_hash text,p_phone text,p_text text,p_mode text) returns text language plpgsql security definer set search_path='' as $$
declare h text; u uuid; linked timestamptz; q jsonb;
begin
 if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' or p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_text is null or length(p_text)>512 or p_mode is null or p_mode not in ('text','button','list','link','audio','image') then raise exception 'Invalid signed input';end if;
 h:=encode(sha256(convert_to(p_phone,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended(h,0));
 -- Bounded opportunistic global cleanup. No cron/billing; no expired content is eligible for delivery.
 update private.wa_v2_outbox set reply=null,state=case when state='sending' then 'uncertain' else 'expired' end
 where message_hash in (select message_hash from private.wa_v2_outbox where reply is not null and expires_at<=clock_timestamp() order by expires_at limit 100 for update skip locked);
 insert into public.whatsapp_webhook_receipts(message_hash) values(p_hash) on conflict do nothing;
 if not found then return 'duplicate';end if;
 q:=private.wa_v2_action(p_phone,p_text,p_mode);
 if jsonb_typeof(q)<>'object' or coalesce(length(q->>'body'),0) not between 1 and 4096 or pg_column_size(q)>16384 then raise exception 'Invalid reply';end if;
 select user_id,linked_at into u,linked from private.wa_links where phone=p_phone;
 insert into private.wa_v2_outbox(message_hash,sender_hash,user_id,linked_at,reply,expires_at) values(p_hash,h,u,linked,q,clock_timestamp()+interval '2 minutes');
 return 'queued';
end $$;
create function private.wa_v2_take(p_hash text,p_phone text) returns jsonb language plpgsql security definer set search_path='' as $$
declare h text; q private.wa_v2_outbox%rowtype; u uuid; linked timestamptz; tok uuid;
begin
 h:=encode(sha256(convert_to(p_phone,'UTF8')),'hex');perform pg_advisory_xact_lock(hashtextextended(h,0));
 select * into q from private.wa_v2_outbox where message_hash=p_hash and sender_hash=h for update;
 if not found then return jsonb_build_object('state','ignored');end if;
 select user_id,linked_at into u,linked from private.wa_links where phone=p_phone;
 if q.state not in ('queued','retry') then return jsonb_build_object('state',q.state);end if;
 if q.expires_at<=clock_timestamp() or q.user_id is distinct from u or q.linked_at is distinct from linked or exists(select 1 from private.wa_v2_outbox a where a.sender_hash=h and a.created_at>q.created_at) then
  update private.wa_v2_outbox set state='expired',reply=null where message_hash=p_hash;return jsonb_build_object('state','expired');
 end if;
 if q.next_at>clock_timestamp() then return jsonb_build_object('state','retry');end if;
 tok:=gen_random_uuid();
 update private.wa_v2_outbox set state='sending',attempts=attempts+1,attempt_token=tok where message_hash=p_hash;
 return jsonb_build_object('state','sending','token',tok,'reply',q.reply);
end $$;
create function private.wa_v2_finish(p_hash text,p_token uuid,p_outcome text,p_provider_hash text,p_error integer,p_latency integer) returns text language plpgsql security definer set search_path='' as $$
declare q private.wa_v2_outbox%rowtype; s text;
begin
 select * into q from private.wa_v2_outbox where message_hash=p_hash and attempt_token=p_token and state='sending' for update;
 if not found then return 'ignored';end if;
 if p_outcome not in ('accepted','retry','failed','uncertain') or p_outcome is null then raise exception 'Invalid outcome';end if;
 s:=case when p_outcome='retry' and q.attempts<3 and q.expires_at>clock_timestamp()+interval '5 seconds' then 'retry' when p_outcome='retry' then 'failed' else p_outcome end;
 if s='accepted' and (p_provider_hash is null or p_provider_hash !~ '^[a-f0-9]{64}$') then s:='uncertain';end if;
 update private.wa_v2_outbox set state=s,reply=case when s='retry' then reply else null end,provider_hash=case when s='accepted' then p_provider_hash else null end,error_code=p_error,latency_ms=greatest(0,least(60000,p_latency)),next_at=clock_timestamp()+interval '5 seconds',attempt_token=null where message_hash=p_hash;
 update public.whatsapp_webhook_receipts set status=case when s='accepted' then 'sent' when s='retry' then 'claimed' else 'failed' end where message_hash=p_hash;
 return s;
end $$;
create function private.wa_v2_delivery(p_provider_hash text,p_phone text,p_status text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_status not in ('sent','delivered','read','failed') then return;end if;
 update private.wa_v2_outbox set delivery=p_status where provider_hash=p_provider_hash and sender_hash=encode(sha256(convert_to(p_phone,'UTF8')),'hex') and state='accepted' and (delivery is null or (case delivery when 'sent' then 1 when 'failed' then 2 when 'delivered' then 3 when 'read' then 4 end)<(case p_status when 'sent' then 1 when 'failed' then 2 when 'delivered' then 3 when 'read' then 4 end));
end $$;
create function private.wa_v2_diagnostics() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('window','last 24 hours','total',count(*),'accepted',count(*) filter(where state='accepted'),'delivered_or_read',count(*) filter(where delivery in ('delivered','read')),'uncertain',count(*) filter(where state='uncertain' or state='sending' and expires_at<=clock_timestamp()),'failed',count(*) filter(where state='failed' or delivery='failed'),'retry_pending',count(*) filter(where state='retry' and expires_at>clock_timestamp()),'token_error_190',count(*) filter(where error_code=190),'average_send_ms',round(avg(latency_ms))) from private.wa_v2_outbox where created_at>clock_timestamp()-interval '24 hours'
$$;
-- Invoker-only API wrappers, exclusively for trusted server role.
create function public.wa_v2_prepare(p_hash text,p_phone text,p_text text,p_mode text) returns text language sql security invoker set search_path='' as $$select private.wa_v2_prepare(p_hash,p_phone,p_text,p_mode)$$;
create function public.wa_v2_take(p_hash text,p_phone text) returns jsonb language sql security invoker set search_path='' as $$select private.wa_v2_take(p_hash,p_phone)$$;
create function public.wa_v2_finish(p_hash text,p_token uuid,p_outcome text,p_provider_hash text,p_error integer,p_latency integer) returns text language sql security invoker set search_path='' as $$select private.wa_v2_finish(p_hash,p_token,p_outcome,p_provider_hash,p_error,p_latency)$$;
create function public.wa_v2_delivery(p_provider_hash text,p_phone text,p_status text) returns void language sql security invoker set search_path='' as $$select private.wa_v2_delivery(p_provider_hash,p_phone,p_status)$$;
create function public.wa_v2_diagnostics() returns jsonb language sql security invoker set search_path='' as $$select private.wa_v2_diagnostics()$$;
revoke all on function private.wa_v2_text(text),private.wa_v2_action(text,text,text) from public,anon,authenticated,service_role;
revoke all on function private.wa_v2_prepare(text,text,text,text),private.wa_v2_take(text,text),private.wa_v2_finish(text,uuid,text,text,integer,integer),private.wa_v2_delivery(text,text,text),private.wa_v2_diagnostics(),public.wa_v2_prepare(text,text,text,text),public.wa_v2_take(text,text),public.wa_v2_finish(text,uuid,text,text,integer,integer),public.wa_v2_delivery(text,text,text),public.wa_v2_diagnostics() from public,anon,authenticated,service_role;
grant execute on function private.wa_v2_prepare(text,text,text,text),private.wa_v2_take(text,text),private.wa_v2_finish(text,uuid,text,text,integer,integer),private.wa_v2_delivery(text,text,text),private.wa_v2_diagnostics(),public.wa_v2_prepare(text,text,text,text),public.wa_v2_take(text,text),public.wa_v2_finish(text,uuid,text,text,integer,integer),public.wa_v2_delivery(text,text,text),public.wa_v2_diagnostics() to service_role;
commit;
 then
   select id into oid from public.orders where customer_id=u and request_key=split_part(cmd,' ',3)::uuid and source='whatsapp_test';
   if found then return private.wa_v2_text('Test order already placed: '||oid||'. No duplicate order created. Send ORDERS.');end if;
   if cart.quote_id is null or cart.quote_id::text<>split_part(cmd,' ',3) or cart.expires_at<=clock_timestamp() then return private.wa_v2_text('Cart quote expired or invalid. Send CHECKOUT CART again.');end if;
   begin
    oid:=private.checkout_order_for(u,cart.fpo_id,cart.items,'WhatsApp test delivery - no real delivery',cart.quote_id);
    update public.orders set source='whatsapp_test' where id=oid and customer_id=u and source='web';
    if not found then raise exception 'Invalid order channel';end if;
    insert into private.integration_events(channel,external_id,event_type,payload,status) values('whatsapp','test:'||cart.quote_id::text,'whatsapp_test_checkout',jsonb_build_object('order_id',oid,'mode','test'),'processed');
   exception when raise_exception then return private.wa_v2_text('Order not placed. Stock or price may have changed. Search again and rebuild cart.');end;
   delete from private.wa_v2_cart where user_id=u;
   return private.wa_v2_text('Test order confirmed: '||oid||'. No actual payment or delivery. Send ORDERS.');
  end if;
  if cmd ~ '^add ' then
   x:=regexp_match(cmd,'^add ([1-8]) ([0-9]{1,5}([.][0-9]{1,3})?)$');
   if x is null then return private.wa_v2_text('Use ADD 1 2 for item 1, 2 kg.');end if;
   select * into shop from private.wa_shop where user_id=u;
   n:=x[1]::int;qty:=x[2]::numeric;
   if shop.catalogue_expires is null or shop.catalogue_expires<=clock_timestamp() or n>jsonb_array_length(shop.products) or qty<0.001 or qty>10000 then return private.wa_v2_text('Search again and choose valid quantity.');end if;
   p:=shop.products->(n-1);f:=(p->>'fpo_id')::uuid;
   if cart.expires_at is null or cart.expires_at<=clock_timestamp() then cart.items:='[]';cart.fpo_id:=f;end if;
   if cart.fpo_id<>f then return private.wa_v2_text('One FPO per cart. Clear cart before switching FPO.');end if;
   if exists(select 1 from jsonb_array_elements(cart.items) j where j->>'crop'=p->>'crop' and j->>'grade'=p->>'grade' and (j->>'price_paise_per_kg')::int=(p->>'price_paise_per_kg')::int) then return private.wa_v2_text('Item already in cart. Clear cart to change quantities.');end if;
   if jsonb_array_length(cart.items)>=8 or not exists(select 1 from private.catalogue() c where c.fpo_id=f and c.crop=p->>'crop' and c.grade=p->>'grade' and c.price_paise_per_kg=(p->>'price_paise_per_kg')::int and c.available_kg>=qty) then return private.wa_v2_text('Cart limit or stock/price changed.');end if;
   it:=jsonb_build_object('crop',p->>'crop','grade',p->>'grade','price_paise_per_kg',(p->>'price_paise_per_kg')::int,'quantity_kg',qty);
   cart.items:=cart.items||jsonb_build_array(it);
   insert into private.wa_v2_cart(user_id,fpo_id,items,expires_at) values(u,f,cart.items,clock_timestamp()+interval '10 minutes') on conflict(user_id) do update set fpo_id=excluded.fpo_id,items=excluded.items,expires_at=excluded.expires_at,quote_id=null;
  end if;
  if cart.items is null or jsonb_array_length(cart.items)=0 or (cmd not like 'add %' and cart.expires_at<=clock_timestamp()) then return private.wa_v2_text('Cart empty or expired. Send SEARCH Tomatoes or SHOP.');end if;
  select sum(round((j->>'quantity_kg')::numeric*(j->>'price_paise_per_kg')::int))::bigint,string_agg(left(regexp_replace(j->>'crop','[[:cntrl:]]',' ','g'),100)||' | '||(j->>'grade')||' | '||(j->>'quantity_kg')||' kg | ₹'||round((j->>'quantity_kg')::numeric*(j->>'price_paise_per_kg')::int/100,2),E'\n' order by ord) into total,result from jsonb_array_elements(cart.items) with ordinality a(j,ord);
  if cmd='checkout cart' then
   if total<1 or exists(select 1 from jsonb_array_elements(cart.items) j where not exists(select 1 from private.catalogue() c where c.fpo_id=cart.fpo_id and c.crop=j->>'crop' and c.grade=j->>'grade' and c.price_paise_per_kg=(j->>'price_paise_per_kg')::int and c.available_kg>=(j->>'quantity_kg')::numeric)) then return private.wa_v2_text('Stock or price changed. Clear cart and search again.');end if;
   token:=gen_random_uuid();update private.wa_v2_cart set quote_id=token,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
   return private.wa_v2_text('Test checkout preview:'||E'\n'||result||E'\nTotal ₹'||round(total::numeric/100,2)||E'\nNo real payment. Send CART CONFIRM '||token||' within 10 minutes.');
  end if;
  return private.wa_v2_text('Cart:'||E'\n'||result||E'\nTotal ₹'||round(total::numeric/100,2)||E'\nCHECKOUT CART or CLEAR CART. No stock reserved yet.');
 end if;
 if cmd in ('earnings','farm summary','manager report','orders','cart','clear cart','checkout cart') or cmd ~ '^(search|add|order|cart confirm|i harvested) ' then return private.wa_v2_text('This action is not available for your role or format. Send QUICK.');end if;
 if cmd ~ '^(shop|buy|confirm|track|reset)( |$)' then return private.wa_v2_text(private.wa_order_command(p_phone,cmd));end if;
 if cmd ~ '^(fpos|harvest|submit|harvests|harvestreset)( |$)' then return private.wa_v2_text(private.wa_harvest_command(p_phone,v));end if;
 if cmd ~ '^(alerts|read)( |$)' then return private.wa_v2_text(private.wa_manager_command(p_phone,cmd));end if;
 -- New explicit shortcut to recover context without replaying a mutation.
 if cmd='recover' then
  if r='farmer' then return private.wa_v2_text(private.wa_harvest_command(p_phone,'HARVESTS'));
  elsif r='customer' then return private.wa_v2_text(private.wa_order_command(p_phone,'TRACK'));
  else return private.wa_guide(p_phone,'menu',false);end if;
 end if;
 return private.wa_guide(p_phone,v,false);
end $$;
-- Atomically commit operation and its reply; old receipts remain deduplication tombstones.
create function private.wa_v2_prepare(p_hash text,p_phone text,p_text text,p_mode text) returns text language plpgsql security definer set search_path='' as $$
declare h text; u uuid; linked timestamptz; q jsonb;
begin
 if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' or p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_text is null or length(p_text)>512 or p_mode is null or p_mode not in ('text','button','list','link','audio','image') then raise exception 'Invalid signed input';end if;
 h:=encode(sha256(convert_to(p_phone,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended(h,0));
 update private.wa_v2_outbox set reply=null,state=case when state='sending' then 'uncertain' else 'expired' end where sender_hash=h and reply is not null and expires_at<=clock_timestamp();
 insert into public.whatsapp_webhook_receipts(message_hash) values(p_hash) on conflict do nothing;
 if not found then return 'duplicate';end if;
 q:=private.wa_v2_action(p_phone,p_text,p_mode);
 if jsonb_typeof(q)<>'object' or coalesce(length(q->>'body'),0) not between 1 and 4096 or pg_column_size(q)>16384 then raise exception 'Invalid reply';end if;
 select user_id,linked_at into u,linked from private.wa_links where phone=p_phone;
 insert into private.wa_v2_outbox(message_hash,sender_hash,user_id,linked_at,reply,expires_at) values(p_hash,h,u,linked,q,clock_timestamp()+interval '2 minutes');
 return 'queued';
end $$;
create function private.wa_v2_take(p_hash text,p_phone text) returns jsonb language plpgsql security definer set search_path='' as $$
declare h text; q private.wa_v2_outbox%rowtype; u uuid; linked timestamptz; tok uuid;
begin
 h:=encode(sha256(convert_to(p_phone,'UTF8')),'hex');perform pg_advisory_xact_lock(hashtextextended(h,0));
 select * into q from private.wa_v2_outbox where message_hash=p_hash and sender_hash=h for update;
 if not found then return jsonb_build_object('state','ignored');end if;
 select user_id,linked_at into u,linked from private.wa_links where phone=p_phone;
 if q.state not in ('queued','retry') then return jsonb_build_object('state',q.state);end if;
 if q.expires_at<=clock_timestamp() or q.user_id is distinct from u or q.linked_at is distinct from linked or exists(select 1 from private.wa_v2_outbox a where a.sender_hash=h and a.created_at>q.created_at) then
  update private.wa_v2_outbox set state='expired',reply=null where message_hash=p_hash;return jsonb_build_object('state','expired');
 end if;
 if q.next_at>clock_timestamp() then return jsonb_build_object('state','retry');end if;
 tok:=gen_random_uuid();
 update private.wa_v2_outbox set state='sending',attempts=attempts+1,attempt_token=tok where message_hash=p_hash;
 return jsonb_build_object('state','sending','token',tok,'reply',q.reply);
end $$;
create function private.wa_v2_finish(p_hash text,p_token uuid,p_outcome text,p_provider_hash text,p_error integer,p_latency integer) returns text language plpgsql security definer set search_path='' as $$
declare q private.wa_v2_outbox%rowtype; s text;
begin
 select * into q from private.wa_v2_outbox where message_hash=p_hash and attempt_token=p_token and state='sending' for update;
 if not found then return 'ignored';end if;
 if p_outcome not in ('accepted','retry','failed','uncertain') or p_outcome is null then raise exception 'Invalid outcome';end if;
 s:=case when p_outcome='retry' and q.attempts<3 and q.expires_at>clock_timestamp()+interval '5 seconds' then 'retry' when p_outcome='retry' then 'failed' else p_outcome end;
 if s='accepted' and (p_provider_hash is null or p_provider_hash !~ '^[a-f0-9]{64}$') then s:='uncertain';end if;
 update private.wa_v2_outbox set state=s,reply=case when s='retry' then reply else null end,provider_hash=case when s='accepted' then p_provider_hash else null end,error_code=p_error,latency_ms=greatest(0,least(60000,p_latency)),next_at=clock_timestamp()+interval '5 seconds',attempt_token=null where message_hash=p_hash;
 update public.whatsapp_webhook_receipts set status=case when s='accepted' then 'sent' when s='retry' then 'claimed' else 'failed' end where message_hash=p_hash;
 return s;
end $$;
create function private.wa_v2_delivery(p_provider_hash text,p_phone text,p_status text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_status not in ('sent','delivered','read','failed') then return;end if;
 update private.wa_v2_outbox set delivery=p_status where provider_hash=p_provider_hash and sender_hash=encode(sha256(convert_to(p_phone,'UTF8')),'hex') and state='accepted' and (delivery is null or (case delivery when 'sent' then 1 when 'failed' then 2 when 'delivered' then 3 when 'read' then 4 end)<(case p_status when 'sent' then 1 when 'failed' then 2 when 'delivered' then 3 when 'read' then 4 end));
end $$;
create function private.wa_v2_diagnostics() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('window','last 24 hours','total',count(*),'accepted',count(*) filter(where state='accepted'),'delivered_or_read',count(*) filter(where delivery in ('delivered','read')),'uncertain',count(*) filter(where state='uncertain' or state='sending' and expires_at<=clock_timestamp()),'failed',count(*) filter(where state='failed' or delivery='failed'),'retry_pending',count(*) filter(where state='retry' and expires_at>clock_timestamp()),'token_error_190',count(*) filter(where error_code=190),'average_send_ms',round(avg(latency_ms))) from private.wa_v2_outbox where created_at>clock_timestamp()-interval '24 hours'
$$;
-- Invoker-only API wrappers, exclusively for trusted server role.
create function public.wa_v2_prepare(p_hash text,p_phone text,p_text text,p_mode text) returns text language sql security invoker set search_path='' as $$select private.wa_v2_prepare(p_hash,p_phone,p_text,p_mode)$$;
create function public.wa_v2_take(p_hash text,p_phone text) returns jsonb language sql security invoker set search_path='' as $$select private.wa_v2_take(p_hash,p_phone)$$;
create function public.wa_v2_finish(p_hash text,p_token uuid,p_outcome text,p_provider_hash text,p_error integer,p_latency integer) returns text language sql security invoker set search_path='' as $$select private.wa_v2_finish(p_hash,p_token,p_outcome,p_provider_hash,p_error,p_latency)$$;
create function public.wa_v2_delivery(p_provider_hash text,p_phone text,p_status text) returns void language sql security invoker set search_path='' as $$select private.wa_v2_delivery(p_provider_hash,p_phone,p_status)$$;
create function public.wa_v2_diagnostics() returns jsonb language sql security invoker set search_path='' as $$select private.wa_v2_diagnostics()$$;
revoke all on function private.wa_v2_text(text),private.wa_v2_action(text,text,text) from public,anon,authenticated,service_role;
revoke all on function private.wa_v2_prepare(text,text,text,text),private.wa_v2_take(text,text),private.wa_v2_finish(text,uuid,text,text,integer,integer),private.wa_v2_delivery(text,text,text),private.wa_v2_diagnostics(),public.wa_v2_prepare(text,text,text,text),public.wa_v2_take(text,text),public.wa_v2_finish(text,uuid,text,text,integer,integer),public.wa_v2_delivery(text,text,text),public.wa_v2_diagnostics() from public,anon,authenticated,service_role;
grant execute on function private.wa_v2_prepare(text,text,text,text),private.wa_v2_take(text,text),private.wa_v2_finish(text,uuid,text,text,integer,integer),private.wa_v2_delivery(text,text,text),private.wa_v2_diagnostics(),public.wa_v2_prepare(text,text,text,text),public.wa_v2_take(text,text),public.wa_v2_finish(text,uuid,text,text,integer,integer),public.wa_v2_delivery(text,text,text),public.wa_v2_diagnostics() to service_role;
commit;
