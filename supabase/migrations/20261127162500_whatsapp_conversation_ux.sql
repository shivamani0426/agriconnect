begin;
-- Localized UX messages; no new permissions.
create function private.wa_ux_phrase(l text,k text) returns text language sql immutable set search_path='' as $$
select coalesce(($dict${"stock":["Only {kg} kg is available now. Enter a smaller quantity, or send 0 for menu.","ಈಗ {kg} ಕೆಜಿ ಮಾತ್ರ ಲಭ್ಯವಿದೆ. ಕಡಿಮೆ ಪ್ರಮಾಣ ನಮೂದಿಸಿ ಅಥವಾ ಮೆನುಗಾಗಿ 0 ಕಳುಹಿಸಿ.","ప్రస్తుతం {kg} కిలోలు మాత్రమే అందుబాటులో ఉన్నాయి. తక్కువ పరిమాణం నమోదు చేయండి లేదా మెనూ కోసం 0 పంపండి.","अभी केवल {kg} किलो उपलब्ध है। कम मात्रा लिखें या मेनू के लिए 0 भेजें।"],"soldout":["This product is no longer available at the listed price. Send 0 and browse again.","ಈ ಬೆಲೆ ಅಥವಾ ಉತ್ಪನ್ನ ಈಗ ಲಭ್ಯವಿಲ್ಲ. 0 ಕಳುಹಿಸಿ ಮತ್ತೆ ನೋಡಿ.","ఈ ధరకు ఉత్పత్తి ఇప్పుడు అందుబాటులో లేదు. 0 పంపి మళ్లీ చూడండి.","यह उत्पाद अब इस कीमत पर उपलब्ध नहीं है। 0 भेजकर दोबारा देखें।"],"selected":["Selected: {crop} • {kg} kg available. Enter the quantity in kg.","ಆಯ್ಕೆ: {crop} • {kg} ಕೆಜಿ ಲಭ್ಯ. ಬೇಕಾದ ಕೆಜಿ ನಮೂದಿಸಿ.","ఎంచుకున్నది: {crop} • {kg} కిలోలు అందుబాటులో ఉన్నాయి. కావలసిన పరిమాణం నమోదు చేయండి.","चुना गया: {crop} • {kg} किलो उपलब्ध। मात्रा किलो में लिखें।"],"shop_hint":["Send the product number, then kg. Or send ADD number kg for a single-item preview. For a multi-item cart, send /SEARCH crop. No order until confirmation.","ಉತ್ಪನ್ನದ ಸಂಖ್ಯೆ, ನಂತರ ಕೆಜಿ ಕಳುಹಿಸಿ. ಒಂದೇ ಉತ್ಪನ್ನದ ಪೂರ್ವವೀಕ್ಷಣೆಗೆ ADD ಸಂಖ್ಯೆ ಕೆಜಿ ಕಳುಹಿಸಿ. ಹಲವು ಉತ್ಪನ್ನಗಳಿಗೆ /SEARCH crop. ದೃಢೀಕರಣದ ಮೊದಲು ಆರ್ಡರ್ ಆಗುವುದಿಲ್ಲ.","ఉత్పత్తి సంఖ్య, తర్వాత కిలోలు పంపండి. ఒక ఉత్పత్తి ప్రివ్యూ కోసం ADD సంఖ్య కిలోలు పంపండి. బహుళ ఉత్పత్తులకు /SEARCH crop. నిర్ధారణ ముందు ఆర్డర్ కాదు.","उत्पाद का नंबर, फिर किलो भेजें। एक उत्पाद के पूर्वावलोकन के लिए ADD नंबर किलो भेजें। कई उत्पादों के लिए /SEARCH crop भेजें। पुष्टि से पहले ऑर्डर नहीं होगा।"],"photo_next":["You may now send a crop photo directly. If several harvests are pending, use PHOTO followed by the crop name. Optional: /PHOTOHELP.","ಈಗ ಬೆಳೆ ಫೋಟೋ ನೇರವಾಗಿ ಕಳುಹಿಸಬಹುದು. ಹಲವು ಬೆಳೆಗಳು ಬಾಕಿ ಇದ್ದರೆ PHOTO ನಂತರ ಬೆಳೆಯ ಹೆಸರು ನೀಡಿ. /PHOTOHELP ಐಚ್ಛಿಕ.","ఇప్పుడు పంట ఫోటో నేరుగా పంపవచ్చు. అనేక పంటలు పెండింగ్‌లో ఉంటే PHOTO తర్వాత పంట పేరు ఇవ్వండి. /PHOTOHELP ఐచ్ఛికం.","अब फसल की फोटो सीधे भेज सकते हैं। कई फसलें लंबित हों तो PHOTO के बाद फसल का नाम लिखें। /PHOTOHELP वैकल्पिक है।"],"photohelp":["Send a crop photo (JPEG, PNG or WebP, up to 5 MB). With one pending harvest, no caption is needed. With several, use PHOTO and the exact crop name. If the name matches multiple records, use the website. Existing photos cannot be replaced.","ಬೆಳೆ ಫೋಟೋ ಕಳುಹಿಸಿ (JPEG, PNG ಅಥವಾ WebP, 5 MB ವರೆಗೆ). ಒಂದು ಬಾಕಿ ಬೆಳೆ ಇದ್ದರೆ ಶೀರ್ಷಿಕೆ ಬೇಡ. ಹಲವು ಇದ್ದರೆ PHOTO ಮತ್ತು ನಿಖರ ಬೆಳೆ ಹೆಸರು ನೀಡಿ. ಒಂದೇ ಹೆಸರಿನ ಹಲವು ದಾಖಲೆಗಳಿಗೆ ವೆಬ್‌ಸೈಟ್ ಬಳಸಿ. ಈಗಿನ ಫೋಟೋ ಬದಲಾಯಿಸಲಾಗದು.","పంట ఫోటో పంపండి (JPEG, PNG లేదా WebP, 5 MB వరకు). ఒక పెండింగ్ పంట ఉంటే క్యాప్షన్ అవసరం లేదు. అనేక ఉంటే PHOTO మరియు ఖచ్చితమైన పంట పేరు ఇవ్వండి. ఒకే పేరుతో అనేక రికార్డులు ఉంటే వెబ్‌సైట్ ఉపయోగించండి. ఉన్న ఫోటో మార్చలేరు.","फसल की फोटो भेजें (JPEG, PNG या WebP, 5 MB तक)। एक लंबित फसल हो तो कैप्शन जरूरी नहीं। कई हों तो PHOTO और फसल का सही नाम लिखें। समान नाम के कई रिकॉर्ड हों तो वेबसाइट का उपयोग करें। मौजूदा फोटो बदली नहीं जा सकती।"]}$dict$::jsonb->k->>case l when 'kn' then 1 when 'te' then 2 when 'hi' then 3 else 0 end),k)
$$;
revoke all on function private.wa_ux_phrase(text,text) from public,anon,authenticated,service_role;

create or replace function private.wa_guide_base(p_phone text,p_text text,p_button boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; r text; g private.wa_guides%rowtype; v text:=trim(p_text); cmd text; l text; body text; list_body text; n integer; today date:=(now() at time zone 'Asia/Kolkata')::date; hd date; s private.wa_shop%rowtype; f private.wa_harvest_drafts%rowtype; p jsonb; a jsonb; o public.orders%rowtype; result_text text; ok boolean; action_id uuid; menu_key text; preview_id uuid; buttons jsonb; x jsonb; live_stock numeric; short_input text[]; ux boolean:=current_setting('app.wa_advanced',true)='on';
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or v is null or length(v) not between 1 and 512 then return jsonb_build_object('body','Send HI to start.');end if;
 v:=translate(v,'೦೧೨೩೪೫೬೭೮೯౦౧౨౩౪౫౬౭౮౯०१२३४५६७८९','012345678901234567890123456789');cmd:=lower(v);
 select user_id into u from private.wa_links where phone=p_phone;
 if not found then return jsonb_build_object('body','First link your account in Profile: https://agriconnect-q7c2.onrender.com/');end if;
 select account_role into r from public.profiles where id=u for no key update;
 if not found or r not in ('farmer','manager','customer') or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone) then return jsonb_build_object('body','Link your account first.');end if;
 insert into private.wa_guides(user_id) values(u) on conflict do nothing;
 select * into g from private.wa_guides where user_id=u;
 l:=coalesce(g.lang,'en');menu_key:=r;
 -- Only actual signed interactive reply IDs can confirm. A stale button never acts on a new draft.
 if p_button then
  if cmd !~ '^ac_(confirm|cancel):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  action_id:=split_part(cmd,':',2)::uuid;
  if g.step not in ('order_confirm','harvest_confirm') or g.target is distinct from action_id or g.expires_at<=clock_timestamp() then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  if (g.step='order_confirm' and not exists(select 1 from private.wa_shop where user_id=u and quote_id=action_id and quote_expires>clock_timestamp())) or (g.step='harvest_confirm' and not exists(select 1 from private.wa_harvest_drafts where user_id=u and draft_id=action_id and draft_expires>clock_timestamp())) then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  if cmd like 'ac_cancel:%' then
   if r='customer' then perform private.wa_order_command(p_phone,'reset');elsif r='farmer' then perform private.wa_harvest_command(p_phone,'harvestreset');end if;
   body:=private.wa_phrase(l,'cancelled');
  elsif r='customer' and g.step='order_confirm' then
   result_text:=private.wa_order_command(p_phone,'confirm '||action_id::text);
   body:=case when result_text like 'Test order confirmed!%' or result_text like 'Order already placed%' then private.wa_phrase(l,'orderok') else private.wa_phrase(l,'changed') end;
  elsif r='farmer' and g.step='harvest_confirm' then
   result_text:=private.wa_harvest_command(p_phone,'submit '||action_id::text);
   body:=case when result_text like 'Harvest submitted!%' or result_text like 'Harvest already submitted%' then private.wa_phrase(l,'harvestok')||case when ux then E'\n'||private.wa_ux_phrase(l,'photo_next') else '' end else private.wa_phrase(l,'changed') end;
  else return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  update private.wa_guides set step='menu',target=null,choice=null,crop=null,qty=null,snapshot='[]',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',body||E'\n\n'||private.wa_phrase(l,menu_key));
 end if;
 if cmd in ('language','3 languages') or g.lang is null then
  if g.step='language' and cmd in ('1','2','3','4','english','ಕನ್ನಡ','తెలుగు','हिन्दी','हिंदी') then
   l:=case when cmd in ('1','english') then 'en' when cmd in ('2','ಕನ್ನಡ') then 'kn' when cmd in ('3','తెలుగు') then 'te' else 'hi' end;
   update private.wa_guides set lang=l,step='menu',target=null,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,menu_key));
  end if;
  update private.wa_guides set step='language',target=null,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'choose'));
 end if;
 if g.step='language' then
  if cmd in ('1','2','3','4','english','ಕನ್ನಡ','తెలుగు','हिन्दी','हिंदी') then
   l:=case when cmd in ('1','english') then 'en' when cmd in ('2','ಕನ್ನಡ') then 'kn' when cmd in ('3','తెలుగు') then 'te' else 'hi' end;
   update private.wa_guides set lang=l,step='menu',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,menu_key));
  end if;
  return jsonb_build_object('body',private.wa_phrase(l,'choose'));
 end if;
 if cmd in ('0','hi','hello','help','menu','ನಮಸ್ಕಾರ','నమస్కారం','नमस्ते') then
  if r='customer' then perform private.wa_order_command(p_phone,'reset');elsif r='farmer' then perform private.wa_harvest_command(p_phone,'harvestreset');end if;
  update private.wa_guides set step='menu',target=null,choice=null,crop=null,qty=null,snapshot='[]',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,menu_key));
 end if;
 if g.expires_at<=clock_timestamp() then
  update private.wa_guides set step='menu',target=null,choice=null,crop=null,qty=null,snapshot='[]',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'expired')||E'\n\n'||private.wa_phrase(l,menu_key));
 end if;
 if g.step='menu' and cmd='3' then
  update private.wa_guides set step='language',target=null where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'choose'));
 elsif g.step='menu' and cmd='2' then
  if r='customer' then
   select * into o from public.orders where customer_id=u and source='whatsapp_test' order by created_at desc,id desc limit 1;
   body:=case when not found then private.wa_phrase(l,'noorder') else private.wa_phrase(l,case when o.status='cancelled' then 'cancelled_status' else o.status end)||' | ₹'||round(o.total_paise::numeric/100,2)::text||' | '||private.wa_phrase(l,'test') end;
  elsif r='farmer' then
   select string_agg(left(regexp_replace(z.crop,'[[:cntrl:]]',' ','g'),100)||' | '||z.quantity_kg||' kg | '||private.wa_phrase(l,case when z.status='pending' then 'pending_status' else z.status end)||coalesce(' | '||z.grade,'')||case when z.status='rejected' then ' | '||left(regexp_replace(coalesce(z.rejection_reason,''),'[[:cntrl:]]',' ','g'),200) else '' end,E'\n' order by z.created_at desc,z.id desc) into list_body from (select * from public.harvests where farmer_id=u order by created_at desc,id desc limit 5) z;
   body:=coalesce(private.wa_phrase(l,'myharvests')||E'\n'||list_body,private.wa_phrase(l,'noharvest'));
  else body:='https://agriconnect-q7c2.onrender.com/';end if;
  return jsonb_build_object('body',body||E'\n\n'||private.wa_phrase(l,menu_key));
 elsif (g.step='menu' and cmd='1' and r in ('customer','farmer')) or (g.step in ('shop_list','fpo_list') and cmd='9') then
  n:=case when g.step='menu' then 1 else least(g.page_no+1,999) end;
  if r='customer' then
   perform private.wa_order_command(p_phone,'shop '||n);
   select * into s from private.wa_shop where user_id=u;
   select string_agg(ord::text||'. '||left(regexp_replace(vv->>'crop','[[:cntrl:]]',' ','g'),100)||' | '||private.wa_phrase(l,'grade')||' '||(vv->>'grade')||' | '||left(regexp_replace(vv->>'fpo_name','[[:cntrl:]]',' ','g'),100)||' | ₹'||round((vv->>'price_paise_per_kg')::numeric/100,2)||'/kg | '||(vv->>'available_kg')||' kg',E'\n' order by ord) into list_body from jsonb_array_elements(s.products) with ordinality e(vv,ord);
   body:=private.wa_phrase(l,'produce');x:=s.products;
   update private.wa_guides set step='shop_list',page_no=n,snapshot=x,target=null,expires_at=s.catalogue_expires where user_id=u;
  else
   perform private.wa_harvest_command(p_phone,'fpos '||n);
   select * into f from private.wa_harvest_drafts where user_id=u;
   select string_agg(ord::text||'. '||left(regexp_replace(vv->>'name','[[:cntrl:]]',' ','g'),120),E'\n' order by ord) into list_body from jsonb_array_elements(f.fpos) with ordinality e(vv,ord);
   body:=private.wa_phrase(l,'fpos');x:=f.fpos;
   update private.wa_guides set step='fpo_list',page_no=n,snapshot=x,target=null,expires_at=f.list_expires where user_id=u;
  end if;
  return jsonb_build_object('body',body||E'\n'||coalesce(list_body,private.wa_phrase(l,'empty'))||E'\n\n'||private.wa_phrase(l,'number')||case when ux and r='customer' and jsonb_array_length(x)>0 then E'\n'||private.wa_ux_phrase(l,'shop_hint') else '' end);
 elsif (g.step='menu' and cmd='1' and r='manager') then
  a:=private.manager_inbox_for(u,5);
  select string_agg(ord::text||'. '||private.wa_phrase(l,vv->>'kind')||' | '||left(regexp_replace(vv->>'fpo_name','[[:cntrl:]]',' ','g'),120),E'\n' order by ord) into list_body from jsonb_array_elements(a->'alerts') with ordinality e(vv,ord);
  update private.wa_guides set step='alert_list',snapshot=a->'alerts',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'alerts')||E'\n'||private.wa_phrase(l,'members')||': '||(a->>'pending_members')||E'\n'||private.wa_phrase(l,'harvests')||': '||(a->>'pending_harvests')||E'\n'||private.wa_phrase(l,'orders')||': '||(a->>'open_orders')||E'\n'||private.wa_phrase(l,'unread')||': '||(a->>'unread')||E'\n\n'||coalesce(list_body,'')||E'\n'||private.wa_phrase(l,'readchoice'));
 elsif g.step='alert_list' and r='manager' and cmd ~ '^[1-5]$' then
  n:=cmd::integer;
  if n>jsonb_array_length(g.snapshot) then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  ok:=private.manager_read_for(u,(g.snapshot->(n-1)->>'id')::uuid);
  update private.wa_guides set step='menu',snapshot='[]' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,case when ok then 'readok' else 'expired' end)||E'\n\n'||private.wa_phrase(l,menu_key));
 elsif ux and g.step='shop_list' and r='customer' and cmd ~ '^add [1-8] [0-9]{1,5}([.][0-9]{1,3})?$' then
  short_input:=regexp_match(cmd,'^add ([1-8]) ([0-9]{1,5}([.][0-9]{1,3})?)$');
  n:=short_input[1]::integer;
  if n>jsonb_array_length(g.snapshot) then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'number'));end if;
  update private.wa_guides set choice=n,step='shop_qty' where user_id=u;
  return private.wa_guide_base(p_phone,short_input[2],false);
 elsif g.step in ('shop_list','fpo_list') and cmd ~ '^[1-8]$' then
  n:=cmd::integer;
  if n>jsonb_array_length(g.snapshot) then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  update private.wa_guides set choice=n,step=case when g.step='shop_list' then 'shop_qty' else 'farm_crop' end where user_id=u;
  if ux and g.step='shop_list' then
   p:=g.snapshot->(n-1);
   return jsonb_build_object('body',replace(replace(private.wa_ux_phrase(l,'selected'),'{kg}',p->>'available_kg'),'{crop}',private.wa_clean(p->>'crop',100))||private.wa_phrase(l,'hint'));
  end if;
  return jsonb_build_object('body',private.wa_phrase(l,case when g.step='shop_list' then 'quantity' else 'crop' end)||private.wa_phrase(l,'hint'));
 elsif g.step='farm_crop' and r='farmer' then
  if length(v)>100 or v ~ '[|[:cntrl:]]' then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'crop'));end if;
  update private.wa_guides set crop=v,step='farm_qty' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'quantity')||private.wa_phrase(l,'hint'));
 elsif g.step in ('shop_qty','farm_qty') then
  if v !~ '^[0-9]{1,9}([.][0-9]{1,3})?$' then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'quantity'));end if;
  if v::numeric<0.001 or v::numeric>(case when g.step='shop_qty' then 10000 else 999999999 end) then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'quantity'));end if;
  if g.step='farm_qty' then
   update private.wa_guides set qty=v,step='farm_date' where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,'date')||private.wa_phrase(l,'hint'));
  end if;
  select * into s from private.wa_shop where user_id=u;
  if r<>'customer' or s.products is distinct from g.snapshot or s.catalogue_expires<=clock_timestamp() then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  if ux then
   p:=g.snapshot->(g.choice-1);
   select q.available_kg into live_stock from private.catalogue() q where q.fpo_id=(p->>'fpo_id')::uuid and q.crop=p->>'crop' and q.grade=p->>'grade' and q.price_paise_per_kg=(p->>'price_paise_per_kg')::integer;
   if live_stock is null or live_stock<=0 then return jsonb_build_object('body',private.wa_ux_phrase(l,'soldout'));end if;
   if v::numeric>live_stock then return jsonb_build_object('body',replace(private.wa_ux_phrase(l,'stock'),'{kg}',trim_scale(live_stock)::text));end if;
  end if;
  result_text:=private.wa_order_command(p_phone,'buy '||g.choice||' '||v);
  if result_text not like 'Demo order preview:%' then return jsonb_build_object('body',private.wa_phrase(l,'changed'));end if;
  select * into s from private.wa_shop where user_id=u;preview_id:=s.quote_id;p:=s.quote_item;
  body:=private.wa_phrase(l,'preview')||E'\n'||(p->>'crop')||' | '||(p->>'quantity_kg')||' kg | '||private.wa_phrase(l,'grade')||' '||(p->>'grade')||E'\n'||(g.snapshot->(g.choice-1)->>'fpo_name')||E'\n'||private.wa_phrase(l,'total')||': ₹'||round((p->>'quantity_kg')::numeric*(p->>'price_paise_per_kg')::numeric/100,2)||E'\n'||private.wa_phrase(l,'demo');
  update private.wa_guides set step='order_confirm',target=preview_id,expires_at=s.quote_expires where user_id=u;
 elsif g.step='farm_date' and r='farmer' then
  if cmd in ('1','today','ಇಂದು','ఈరోజు','आज') then hd:=today;elsif cmd in ('2','yesterday','ನಿನ್ನೆ','నిన్న','कल') then hd:=today-1;
  else
   if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'date'));end if;
   begin hd:=v::date;exception when datetime_field_overflow or invalid_datetime_format then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'date'));end;
  end if;
  if hd>today then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'date'));end if;
  select * into f from private.wa_harvest_drafts where user_id=u;
  if f.fpos is distinct from g.snapshot or f.list_expires<=clock_timestamp() then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  result_text:=private.wa_harvest_command(p_phone,'HARVEST '||g.choice||' | '||g.crop||' | '||g.qty||' | '||hd::text);
  if result_text not like 'Harvest preview:%' then return jsonb_build_object('body',private.wa_phrase(l,'changed'));end if;
  select * into f from private.wa_harvest_drafts where user_id=u;preview_id:=f.draft_id;
  body:=private.wa_phrase(l,'preview')||E'\n'||f.crop||' | '||f.qty||' kg | '||f.harvest_date||E'\n'||(g.snapshot->(g.choice-1)->>'name')||E'\n'||private.wa_phrase(l,'pending');
  update private.wa_guides set step='harvest_confirm',target=preview_id,expires_at=f.draft_expires where user_id=u;
 elsif g.step in ('order_confirm','harvest_confirm') then return jsonb_build_object('body',private.wa_phrase(l,'tap'));
 elsif ux and g.step in ('shop_list','fpo_list') then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'number')||case when g.step='shop_list' then E'\n'||private.wa_ux_phrase(l,'shop_hint') else '' end);
 else return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,menu_key));end if;
 buttons:=jsonb_build_array(jsonb_build_object('id','ac_confirm:'||preview_id,'title',private.wa_phrase(l,'confirm')),jsonb_build_object('id','ac_cancel:'||preview_id,'title',private.wa_phrase(l,'cancel')));
 return jsonb_build_object('body',body,'buttons',buttons);
end $$;

create or replace function private.wa_guide(p_phone text,p_text text,p_button boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if not p_button and cmd in ('/photohelp','photohelp') then return jsonb_build_object('body',private.wa_ux_phrase(lang,'photohelp'));end if;
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
  return jsonb_build_object('body',case r when 'farmer' then 'Farmer commands: SUMMARY (harvest, stock, estimated earnings), HARVESTS (references). To attach a crop photo, submit a harvest and send the photo directly. If you have several pending harvests, use a caption like PHOTO Tomatoes. Send /PHOTOHELP for details.'
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
    (select count(*) from public.orders ord_r where ord_r.fpo_id=f.id and ord_r.status in ('confirmed','packed','out_for_delivery')) orders,
    (select coalesce(sum(i.available_kg),0) from public.inventory_lots i where i.fpo_id=f.id) stock,
    (select coalesce(sum(ord_r.total_paise),0) from public.orders ord_r where ord_r.fpo_id=f.id and ord_r.status='delivered') revenue
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
  select q.available_kg into live_qty from private.catalogue() q where q.fpo_id=f and q.crop=p->>'crop' and q.grade=p->>'grade' and q.price_paise_per_kg=(p->>'price_paise_per_kg')::integer;
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


commit;
