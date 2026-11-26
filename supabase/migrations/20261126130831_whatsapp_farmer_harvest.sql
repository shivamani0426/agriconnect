begin;
create table private.wa_harvest_drafts(
 user_id uuid primary key references private.wa_links(user_id) on delete cascade,
 fpos jsonb not null default '[]'::jsonb, list_expires timestamptz not null,
 draft_id uuid unique, draft_fpo uuid, crop text, qty numeric(12,3), harvest_date date, draft_expires timestamptz
);
alter table private.wa_harvest_drafts enable row level security;
revoke all on private.wa_harvest_drafts from public,anon,authenticated,service_role;
create function private.wa_harvest_command(p_phone text,p_command text) returns text language plpgsql security definer set search_path='' as $$
declare u uuid; role_name text; cmd text:=lower(trim(p_command)); s private.wa_harvest_drafts%rowtype; fpos jsonb; f uuid; x text[]; n integer; page_no integer; crop_name text; quantity numeric; hd date; d uuid; reply text; h public.harvests%rowtype; fpo_name text;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_command is null or length(p_command)>512 then return 'Invalid test command.';end if;
 select user_id into u from private.wa_links where phone=p_phone;
 if not found then return 'Link your AgriConnect account in Profile first: https://agriconnect-q7c2.onrender.com/';end if;
 select account_role into role_name from public.profiles where id=u for no key update;
 if not found or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone) then return 'Link your AgriConnect account first.';end if;
 if cmd in ('hi','hello','help','menu') then
  if role_name='customer' then return private.wa_order_command(p_phone,p_command);end if;
  if role_name='manager' then return 'AgriConnect FPO manager: review harvests and manage deliveries on https://agriconnect-q7c2.onrender.com/ . WhatsApp manager notifications are not enabled yet.';end if;
  if role_name='farmer' then return 'AgriConnect farmer menu: FPOS (your approved FPOs), HARVEST 1 | Tomatoes | 25 | YYYY-MM-DD (preview), SUBMIT followed by your confirmation code, HARVESTS (recent status), HARVESTRESET (discard draft). Photos are optional on the website; WhatsApp photo upload is not supported. Manager approval is required.';end if;
 end if;
 if role_name is distinct from 'farmer' then return 'WhatsApp harvest submission requires a Farmer account.';end if;
 select * into s from private.wa_harvest_drafts where user_id=u;
 if cmd ~ '^fpos( [1-9][0-9]{0,2})?$' then
  page_no:=coalesce(nullif(split_part(cmd,' ',2),''),'1')::integer;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.name,z.id),'[]'::jsonb) into fpos from
  (select p.id,p.name from public.memberships m join public.fpos p on p.id=m.fpo_id where m.user_id=u and m.role='farmer' and m.status='active' order by p.name,p.id limit 8 offset ((page_no-1)*8)) z;
  insert into private.wa_harvest_drafts(user_id,fpos,list_expires) values(u,fpos,clock_timestamp()+interval '10 minutes')
  on conflict(user_id) do update set fpos=excluded.fpos,list_expires=excluded.list_expires,draft_id=null,draft_fpo=null,crop=null,qty=null,harvest_date=null,draft_expires=null;
  if jsonb_array_length(fpos)=0 then return 'No approved FPO on this page. Join an FPO on the website and wait for approval, or send FPOS to return to page 1.';end if;
  select string_agg(ord::text||'. '||left(regexp_replace(v->>'name','[[:cntrl:]]',' ','g'),120),E'\n' order by ord) into reply from jsonb_array_elements(fpos) with ordinality e(v,ord);
  return 'Your approved FPOs — page '||page_no||E'\n'||reply||E'\n\nSend HARVEST 1 | Tomatoes | 25 | '||((now() at time zone 'Asia/Kolkata')::date)::text||E'\nUse your actual crop, kg and harvest date. FPOS '||(page_no+1)||' for more. List expires in 10 minutes.';
 elsif cmd ~ '^harvest ' then
  x:=regexp_match(trim(p_command),'^[Hh][Aa][Rr][Vv][Ee][Ss][Tt] ([1-8]) *[|] *([^|]{1,100}) *[|] *([0-9]{1,9}([.][0-9]{1,3})?) *[|] *([0-9]{4}-[0-9]{2}-[0-9]{2})$');
  if x is null then return 'Use HARVEST 1 | Tomatoes | 25 | YYYY-MM-DD (FPO number, crop, kg, date).';end if;
  n:=x[1]::integer;crop_name:=trim(x[2]);quantity:=x[3]::numeric;
  if length(crop_name)<1 or crop_name ~ '[[:cntrl:]]' or quantity<0.001 or quantity>999999999 then return 'Enter a crop name and quantity from 0.001 to 999999999 kg.';end if;
  begin hd:=x[5]::date;exception when datetime_field_overflow or invalid_datetime_format then return 'Enter a valid harvest date in YYYY-MM-DD format.';end;
  if hd> (now() at time zone 'Asia/Kolkata')::date then return 'Harvest date cannot be in the future.';end if;
  if s.user_id is null or s.list_expires<=clock_timestamp() or n>jsonb_array_length(s.fpos) then return 'Send FPOS first and select an approved FPO from the current list.';end if;
  f:=(s.fpos->(n-1)->>'id')::uuid;
  perform 1 from public.memberships where fpo_id=f and user_id=u and role='farmer' and status='active' for share;
  if not found then return 'FPO membership is no longer approved. Send FPOS again.';end if;
  d:=gen_random_uuid();
  update private.wa_harvest_drafts set draft_id=d,draft_fpo=f,crop=crop_name,qty=quantity,harvest_date=hd,draft_expires=clock_timestamp()+interval '10 minutes' where user_id=u;
  return 'Harvest preview: '||crop_name||' | '||quantity||' kg | '||hd::text||E'\nFPO: '||left(regexp_replace(s.fpos->(n-1)->>'name','[[:cntrl:]]',' ','g'),120)||E'\nNo photo attached. To submit for manager verification within 10 minutes, send:\nSUBMIT '||d::text;
 elsif cmd ~ '^submit [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  d:=split_part(cmd,' ',2)::uuid;
  select * into h from public.harvests where id=d and farmer_id=u and exists(select 1 from private.integration_events e where e.channel='whatsapp' and e.event_type='harvest_test_submission' and e.external_id=d::text);
  if found then return 'Harvest already submitted. Reference '||d::text||' | Status: '||h.status||'. No duplicate created.';end if;
  if s.draft_id is distinct from d or s.draft_expires<=clock_timestamp() or s.crop is null then return 'Draft expired or invalid. Send FPOS to start again.';end if;
  perform 1 from public.memberships where fpo_id=s.draft_fpo and user_id=u and role='farmer' and status='active' for share;
  if not found then return 'FPO membership is no longer approved. No harvest submitted.';end if;
  insert into public.harvests(id,fpo_id,farmer_id,crop,quantity_kg,harvest_date,status) values(d,s.draft_fpo,u,s.crop,s.qty,s.harvest_date,'pending');
  insert into private.audit_events(actor,fpo_id,action,subject) values(u,s.draft_fpo,'whatsapp_harvest_submitted',d);
  insert into private.integration_events(channel,external_id,event_type,payload,status) values('whatsapp',d::text,'harvest_test_submission',jsonb_build_object('harvest_id',d,'mode','test'),'processed');
  update private.wa_harvest_drafts set draft_id=null,draft_fpo=null,crop=null,qty=null,harvest_date=null,draft_expires=null where user_id=u;
  return 'Harvest submitted! Reference '||d::text||E'\nStatus: pending FPO manager review. Stock is not published yet. Send HARVESTS for updates.';
 elsif cmd='harvests' or cmd ~ '^harvests [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  if cmd='harvests' then
   select string_agg(left(regexp_replace(z.crop,'[[:cntrl:]]',' ','g'),100)||' | '||z.quantity_kg||' kg | '||z.status||' | '||z.id::text,E'\n' order by z.created_at desc,z.id desc) into reply from
   (select * from public.harvests where farmer_id=u order by created_at desc,id desc limit 5) z;
   return coalesce('Your recent harvests:'||E'\n'||reply||E'\nSend HARVESTS followed by a reference for details.','No harvest submissions yet.');
  end if;
  select * into h from public.harvests where id=split_part(cmd,' ',2)::uuid and farmer_id=u;
  if not found then return 'No matching harvest for your account.';end if;
  select name into fpo_name from public.fpos where id=h.fpo_id;
  return 'Harvest '||h.id::text||E'\n'||left(regexp_replace(h.crop,'[[:cntrl:]]',' ','g'),100)||' | '||h.quantity_kg||' kg | '||h.harvest_date::text||E'\nFPO: '||left(regexp_replace(fpo_name,'[[:cntrl:]]',' ','g'),120)||E'\nStatus: '||h.status||case when h.grade is not null then E'\nGrade: '||h.grade else '' end||case when h.status='rejected' then E'\nReason: '||left(regexp_replace(coalesce(h.rejection_reason,''),'[[:cntrl:]]',' ','g'),500) else '' end;
 elsif cmd='harvestreset' then
  delete from private.wa_harvest_drafts where user_id=u;return 'Draft cleared. Submitted harvests are unchanged. Send FPOS to start again.';
 else return 'Send FPOS, HARVEST, SUBMIT, HARVESTS or HARVESTRESET.';end if;
end $$;
create function public.wa_harvest_command(p_phone text,p_command text) returns text language sql security invoker set search_path='' as $$select private.wa_harvest_command(p_phone,p_command)$$;
revoke all on function private.wa_harvest_command(text,text),public.wa_harvest_command(text,text) from public,anon,authenticated,service_role;
grant execute on function private.wa_harvest_command(text,text),public.wa_harvest_command(text,text) to service_role;
commit;