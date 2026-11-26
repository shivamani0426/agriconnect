begin;
-- The queue and command mutation commit together. Never replay a business command to recover a reply.
create table private.wa_relay_outbox (
 message_hash text primary key references public.whatsapp_webhook_receipts(message_hash) on delete cascade,
 phone_hash text not null,
 phone text check(phone is null or phone ~ '^[1-9][0-9]{6,14}$'),
 link_user uuid, link_at timestamptz, link_role text,
 reply jsonb,
 state text not null default 'queued' check(state in ('queued','sending','retry','accepted','unknown','rejected','credentials','expired')),
 attempts integer not null default 0 check(attempts between 0 and 3),
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default (clock_timestamp()+interval '10 minutes'),
 due_at timestamptz not null default clock_timestamp(),
 taken_at timestamptz,
 provider_hash text unique,
 delivery text check(delivery in ('sent','delivered','read','failed')),
 latency_ms integer check(latency_ms>=0)
);
create index wa_relay_due_idx on private.wa_relay_outbox(phone_hash,due_at) where state in ('queued','retry');
create table private.wa_relay_menu(
 user_id uuid primary key references private.wa_links(user_id) on delete cascade,
 token uuid not null, step text not null check(step in ('menu','language')),
 max_choice integer not null check(max_choice between 1 and 7),
 expires_at timestamptz not null
);
create table private.wa_relay_events(
 provider_hash text primary key, phone_hash text not null,
 delivery text not null check(delivery in ('sent','delivered','read','failed')),
 updated_at timestamptz not null default clock_timestamp()
);
alter table private.wa_relay_outbox enable row level security;
alter table private.wa_relay_menu enable row level security;
alter table private.wa_relay_events enable row level security;
revoke all on private.wa_relay_outbox,private.wa_relay_menu,private.wa_relay_events from public,anon,authenticated,service_role;
create function private.wa_relay_rank(v text) returns integer language sql immutable set search_path='' as $$
 select case v when 'read' then 4 when 'delivered' then 3 when 'failed' then 2 when 'sent' then 1 else 0 end
$$;
create function private.wa_relay_prepare(p_id text,p_phone text,p_route text,p_command text) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid; linked timestamptz; role_name text; reply jsonb; g private.wa_guides%rowtype; menu private.wa_relay_menu%rowtype; token uuid; choice integer; options jsonb; n integer; cmd text:=trim(p_command);
begin
 if p_id is null or p_id !~ '^[a-f0-9]{64}$' or p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or cmd is null or length(cmd)>512 or p_route is null or p_route not in ('link','guide','order','harvest','manager','button','list') then raise exception 'Invalid relay input';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_phone,0));
 insert into public.whatsapp_webhook_receipts(message_hash) values(p_id) on conflict do nothing;
 if not found then return false;end if;
 select w.user_id,w.linked_at,p.account_role into u,linked,role_name from private.wa_links w join public.profiles p on p.id=w.user_id where w.phone=p_phone;
 if u is not null then select * into menu from private.wa_relay_menu where user_id=u; delete from private.wa_relay_menu where user_id=u;end if;
 if p_route='link' then
  if cmd !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then raise exception 'Invalid link code';end if;
  reply:=jsonb_build_object('body',case when private.wa_redeem(p_phone,cmd::uuid)='linked' then 'WhatsApp linked successfully! Open your AgriConnect profile and refresh linking status. Your account role has not changed.' else 'Link not completed. Check your number and use a fresh code from your own AgriConnect profile.' end);
 elsif p_route='list' then
  if u is not null then select * into g from private.wa_guides where user_id=u;end if;
  if cmd ~ '^ac_menu:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[1-7]$' then token:=split_part(cmd,':',2)::uuid;choice:=split_part(cmd,':',3)::integer;end if;
  if token is null or menu.token is distinct from token or menu.expires_at<=clock_timestamp() or g.step is distinct from menu.step or g.expires_at<=clock_timestamp() or choice>menu.max_choice then
   reply:=jsonb_build_object('body',private.wa_phrase(coalesce(g.lang,'en'),'expired'));
  else reply:=private.wa_guide(p_phone,choice::text,false);end if;
 elsif p_route='guide' or p_route='button' then reply:=private.wa_guide(p_phone,cmd,p_route='button');
 elsif p_route='order' then reply:=jsonb_build_object('body',private.wa_order_command(p_phone,lower(cmd)));
 elsif p_route='harvest' then reply:=jsonb_build_object('body',private.wa_harvest_command(p_phone,cmd));
 else reply:=jsonb_build_object('body',private.wa_manager_command(p_phone,lower(cmd)));end if;
 -- Bind recoverable payloads to the link instance, not just the telephone number.
 select w.user_id,w.linked_at,p.account_role into u,linked,role_name from private.wa_links w join public.profiles p on p.id=w.user_id where w.phone=p_phone;
 if u is not null and not (reply ? 'buttons') then
  select * into g from private.wa_guides where user_id=u;
  if g.step='language' and reply->>'body'=private.wa_phrase(coalesce(g.lang,'en'),'choose') then n:=4;
  elsif g.step='menu' and role_name in ('farmer','customer','manager') and reply->>'body'=private.wa_phrase(coalesce(g.lang,'en'),role_name) then
   n:=case role_name when 'farmer' then 3 when 'customer' then 4 else 7 end;
  end if;
  if n is not null then
   token:=gen_random_uuid();
   select jsonb_agg(jsonb_build_object('id','ac_menu:'||token||':'||i,'title',left(substring(split_part(reply->>'body',E'\n',i+1) from 4),24)) order by i) into options from generate_series(1,n) i;
   insert into private.wa_relay_menu(user_id,token,step,max_choice,expires_at) values(u,token,g.step,n,least(g.expires_at,clock_timestamp()+interval '5 minutes')) on conflict(user_id) do update set token=excluded.token,step=excluded.step,max_choice=excluded.max_choice,expires_at=excluded.expires_at;
   reply:=reply||jsonb_build_object('list',options,'list_label',case coalesce(g.lang,'en') when 'kn' then 'ಆಯ್ಕೆ ಮಾಡಿ' when 'te' then 'ఎంచుకోండి' when 'hi' then 'चुनें' else 'Choose' end);
  end if;
 end if;
 if jsonb_typeof(reply->'body') is distinct from 'string' or length(reply->>'body') not between 1 and 4096 then raise exception 'Invalid reply';end if;
 insert into private.wa_relay_outbox(message_hash,phone_hash,phone,link_user,link_at,link_role,reply)
 values(p_id,encode(sha256(convert_to(p_phone,'UTF8')),'hex'),p_phone,u,linked,role_name,reply);
 return true;
end $$;
create function private.wa_relay_take(p_phone text,p_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare q private.wa_relay_outbox%rowtype; ph text; u uuid; linked timestamptz; role_name text;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or (p_id is not null and p_id !~ '^[a-f0-9]{64}$') then raise exception 'Invalid relay recipient';end if;
 ph:=encode(sha256(convert_to(p_phone,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_phone,0));
 -- A crashed sender might have submitted the message; never retry an unknown outcome.
 update private.wa_relay_outbox set state=case when state='sending' then 'unknown' else 'expired' end,phone=null,reply=null,link_user=null,link_at=null,link_role=null
 where phone_hash=ph and ((state in ('queued','retry') and expires_at<=clock_timestamp()) or (state='sending' and taken_at<clock_timestamp()-interval '60 seconds'));
 select w.user_id,w.linked_at,p.account_role into u,linked,role_name from private.wa_links w join public.profiles p on p.id=w.user_id where w.phone=p_phone;
 -- Do not send saved sensitive replies to a number whose account link/role changed.
 update private.wa_relay_outbox set state='expired',phone=null,reply=null,link_user=null,link_at=null,link_role=null
 where phone_hash=ph and state in ('queued','retry') and (link_user is distinct from u or link_at is distinct from linked or link_role is distinct from role_name);
 -- Later interactions supersede older failed interactive prompts; do not resurrect them.
 update private.wa_relay_outbox a set state='expired',phone=null,reply=null,link_user=null,link_at=null,link_role=null
 where a.phone_hash=ph and a.state='retry' and (a.reply ? 'buttons' or a.reply ? 'list') and exists(select 1 from private.wa_relay_outbox b where b.phone_hash=ph and b.created_at>a.created_at);
 select * into q from private.wa_relay_outbox
 where phone_hash=ph and (p_id is null or message_hash=p_id) and state in ('queued','retry') and attempts<3 and expires_at>clock_timestamp() and due_at<=clock_timestamp()
 order by created_at,message_hash limit 1 for update skip locked;
 if not found then return null;end if;
 update private.wa_relay_outbox set state='sending',attempts=attempts+1,taken_at=clock_timestamp() where message_hash=q.message_hash;
 return jsonb_build_object('id',q.message_hash,'attempt',q.attempts+1,'reply',q.reply);
end $$;
create function private.wa_relay_finish(p_id text,p_attempt integer,p_state text,p_provider text default null,p_latency integer default null) returns boolean language plpgsql security definer set search_path='' as $$
declare q private.wa_relay_outbox%rowtype; next_state text; provider text; delivered text;
begin
 if p_state is null or p_state not in ('accepted','retryable','credentials','rejected','unknown') or p_attempt not between 1 and 3 or p_latency is null or p_latency not between 0 and 120000 then raise exception 'Invalid relay result';end if;
 select * into q from private.wa_relay_outbox where message_hash=p_id and state='sending' and attempts=p_attempt for update;
 if not found then return false;end if;
 if p_state='accepted' then
  if p_provider is null or p_provider !~ '^wamid\.' or length(p_provider)>512 then p_state:='unknown';
  else provider:=encode(sha256(convert_to(p_provider,'UTF8')),'hex');
   select delivery into delivered from private.wa_relay_events where provider_hash=provider and phone_hash=q.phone_hash;
  end if;
 end if;
 next_state:=case when p_state='retryable' and p_attempt<3 and q.expires_at>clock_timestamp()+interval '60 seconds' then 'retry' when p_state='retryable' then 'rejected' else p_state end;
 update private.wa_relay_outbox set state=next_state,provider_hash=provider,delivery=delivered,latency_ms=p_latency,
 due_at=clock_timestamp()+make_interval(secs=>30*p_attempt),
 phone=case when next_state='retry' then phone end,reply=case when next_state='retry' then reply end,
 link_user=case when next_state='retry' then link_user end,link_at=case when next_state='retry' then link_at end,link_role=case when next_state='retry' then link_role end
 where message_hash=p_id;
 update public.whatsapp_webhook_receipts set status=case when next_state='accepted' then 'sent' when next_state='retry' then 'claimed' else 'failed' end where message_hash=p_id;
 return true;
end $$;
create function private.wa_relay_delivery(p_phone text,p_provider text,p_delivery text) returns void language plpgsql security definer set search_path='' as $$
declare ph text; h text;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_provider is null or p_provider !~ '^wamid\.' or length(p_provider)>512 or p_delivery is null or p_delivery not in ('sent','delivered','read','failed') then return;end if;
 ph:=encode(sha256(convert_to(p_phone,'UTF8')),'hex');h:=encode(sha256(convert_to(p_provider,'UTF8')),'hex');
 insert into private.wa_relay_events(provider_hash,phone_hash,delivery) values(h,ph,p_delivery)
 on conflict(provider_hash) do update set delivery=excluded.delivery,updated_at=clock_timestamp() where wa_relay_events.phone_hash=excluded.phone_hash and private.wa_relay_rank(excluded.delivery)>private.wa_relay_rank(wa_relay_events.delivery);
 update private.wa_relay_outbox set delivery=p_delivery where provider_hash=h and phone_hash=ph and private.wa_relay_rank(p_delivery)>private.wa_relay_rank(delivery);
end $$;
create function private.wa_relay_health() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update private.wa_relay_outbox set state=case when state='sending' then 'unknown' else 'expired' end,phone=null,reply=null,link_user=null,link_at=null,link_role=null
 where (state in ('queued','retry') and expires_at<=clock_timestamp()) or (state='sending' and taken_at<clock_timestamp()-interval '60 seconds');
 delete from private.wa_relay_events where updated_at<clock_timestamp()-interval '7 days';
 delete from private.wa_relay_outbox where created_at<clock_timestamp()-interval '7 days';
 delete from private.wa_relay_menu where expires_at<=clock_timestamp();
 select jsonb_build_object('states',coalesce((select jsonb_object_agg(state,n) from (select state,count(*) n from private.wa_relay_outbox group by state) a),'{}'::jsonb),
 'delivery',coalesce((select jsonb_object_agg(delivery,n) from (select delivery,count(*) n from private.wa_relay_outbox where delivery is not null group by delivery) b),'{}'::jsonb),
 'average_attempt_ms',round(avg(latency_ms)),'oldest_pending_seconds',extract(epoch from (clock_timestamp()-min(created_at) filter(where state in ('queued','retry'))))::integer)
 into result from private.wa_relay_outbox;
 return result;
end $$;
-- Exposed invoker wrappers are intentionally service-role-only.
create function public.wa_relay_prepare(p_id text,p_phone text,p_route text,p_command text) returns boolean language sql security invoker set search_path='' as $$select private.wa_relay_prepare(p_id,p_phone,p_route,p_command)$$;
create function public.wa_relay_take(p_phone text,p_id text default null) returns jsonb language sql security invoker set search_path='' as $$select private.wa_relay_take(p_phone,p_id)$$;
create function public.wa_relay_finish(p_id text,p_attempt integer,p_state text,p_provider text default null,p_latency integer default null) returns boolean language sql security invoker set search_path='' as $$select private.wa_relay_finish(p_id,p_attempt,p_state,p_provider,p_latency)$$;
create function public.wa_relay_delivery(p_phone text,p_provider text,p_delivery text) returns void language sql security invoker set search_path='' as $$select private.wa_relay_delivery(p_phone,p_provider,p_delivery)$$;
create function public.wa_relay_health() returns jsonb language sql security invoker set search_path='' as $$select private.wa_relay_health()$$;
revoke all on function private.wa_relay_rank(text),private.wa_relay_prepare(text,text,text,text),private.wa_relay_take(text,text),private.wa_relay_finish(text,integer,text,text,integer),private.wa_relay_delivery(text,text,text),private.wa_relay_health(),public.wa_relay_prepare(text,text,text,text),public.wa_relay_take(text,text),public.wa_relay_finish(text,integer,text,text,integer),public.wa_relay_delivery(text,text,text),public.wa_relay_health() from public,anon,authenticated,service_role;
grant execute on function private.wa_relay_prepare(text,text,text,text),private.wa_relay_take(text,text),private.wa_relay_finish(text,integer,text,text,integer),private.wa_relay_delivery(text,text,text),private.wa_relay_health(),public.wa_relay_prepare(text,text,text,text),public.wa_relay_take(text,text),public.wa_relay_finish(text,integer,text,text,integer),public.wa_relay_delivery(text,text,text),public.wa_relay_health() to service_role;
commit;
