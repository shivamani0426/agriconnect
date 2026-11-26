begin;
-- Record events transactionally, without contacting WhatsApp or storing message text.
create table private.fpo_alerts(
 id uuid primary key default gen_random_uuid(), fpo_id uuid not null references public.fpos(id) on delete cascade,
 kind text not null check(kind in ('membership_requested','harvest_submitted','order_confirmed','order_cancelled')),
 subject_id uuid not null, created_at timestamptz not null default clock_timestamp(),
 unique(fpo_id,kind,subject_id)
);
create index fpo_alerts_fpo_date on private.fpo_alerts(fpo_id,created_at desc,id);
create table private.fpo_alert_reads(
 alert_id uuid references private.fpo_alerts(id) on delete cascade, manager_id uuid references public.profiles(id) on delete cascade,
 read_at timestamptz not null default now(), primary key(alert_id,manager_id)
);
alter table private.fpo_alerts enable row level security;
alter table private.fpo_alert_reads enable row level security;
revoke all on private.fpo_alerts,private.fpo_alert_reads from public,anon,authenticated,service_role;
create function private.capture_fpo_alert() returns trigger language plpgsql security definer set search_path='' as $$
declare k text; subject uuid;
begin
 if tg_table_name='memberships' then
  if new.role='farmer' and new.status='pending' then k:='membership_requested';subject:=new.user_id;end if;
 elsif tg_table_name='harvests' then
  if new.status='pending' then k:='harvest_submitted';subject:=new.id;end if;
 elsif tg_table_name='orders' then
  if tg_op='INSERT' then
   if new.status='confirmed' then k:='order_confirmed';subject:=new.id;end if;
  elsif new.status='cancelled' and old.status is distinct from new.status then k:='order_cancelled';subject:=new.id;end if;
 end if;
 if k is not null then insert into private.fpo_alerts(fpo_id,kind,subject_id) values(new.fpo_id,k,subject) on conflict(fpo_id,kind,subject_id) do nothing;end if;
 return new;
end $$;
revoke all on function private.capture_fpo_alert() from public,anon,authenticated,service_role;
create trigger fpo_alert_membership after insert on public.memberships for each row execute function private.capture_fpo_alert();
create trigger fpo_alert_harvest after insert on public.harvests for each row execute function private.capture_fpo_alert();
create trigger fpo_alert_order after insert or update of status on public.orders for each row execute function private.capture_fpo_alert();
-- Every read is scoped to the manager's current active FPO memberships. Read state is per manager.
create function private.manager_inbox_for(u uuid,p_limit integer) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare answer jsonb;
begin
 if u is null or not exists(select 1 from public.profiles where id=u and account_role='manager') then raise exception 'FPO manager account required';end if;
 with managed as (select fpo_id from public.memberships where user_id=u and role='manager' and status='active'),
 unread as (select a.id,a.kind,a.fpo_id,f.name as fpo_name,a.created_at from private.fpo_alerts a join managed m on m.fpo_id=a.fpo_id join public.fpos f on f.id=a.fpo_id where not exists(select 1 from private.fpo_alert_reads r where r.alert_id=a.id and r.manager_id=u))
 select jsonb_build_object(
 'unread',(select count(*) from unread),
 'pending_members',(select count(*) from public.memberships m join managed x on x.fpo_id=m.fpo_id where m.role='farmer' and m.status='pending'),
 'pending_harvests',(select count(*) from public.harvests h join managed x on x.fpo_id=h.fpo_id where h.status='pending'),
 'open_orders',(select count(*) from public.orders o join managed x on x.fpo_id=o.fpo_id where o.status in ('confirmed','packed','out_for_delivery')),
 'alerts',(select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at desc,z.id),'[]'::jsonb) from (select * from unread order by created_at desc,id limit least(greatest(coalesce(p_limit,5),1),30)) z)
 ) into answer;
 return answer;
end $$;
create function private.manager_read_for(u uuid,p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if u is null or not exists(select 1 from public.profiles where id=u and account_role='manager') then raise exception 'FPO manager account required';end if;
 if not exists(select 1 from private.fpo_alerts a join public.memberships m on m.fpo_id=a.fpo_id where a.id=p_id and m.user_id=u and m.role='manager' and m.status='active') then return false;end if;
 insert into private.fpo_alert_reads(alert_id,manager_id) values(p_id,u) on conflict do nothing;
 return true;
end $$;
revoke all on function private.manager_inbox_for(uuid,integer),private.manager_read_for(uuid,uuid) from public,anon,authenticated,service_role;
create function private.manager_inbox() returns jsonb language sql stable security definer set search_path='' as $$select private.manager_inbox_for(auth.uid(),30)$$;
create function private.manager_read(p_id uuid) returns boolean language sql security definer set search_path='' as $$select private.manager_read_for(auth.uid(),p_id)$$;
create function public.manager_inbox() returns jsonb language sql stable security invoker set search_path='' as $$select private.manager_inbox()$$;
create function public.manager_read(p_id uuid) returns boolean language sql security invoker set search_path='' as $$select private.manager_read(p_id)$$;
revoke all on function private.manager_inbox(),private.manager_read(uuid),public.manager_inbox(),public.manager_read(uuid) from public,anon,authenticated,service_role;
grant execute on function private.manager_inbox(),private.manager_read(uuid),public.manager_inbox(),public.manager_read(uuid) to authenticated;
create function private.wa_manager_command(p_phone text,p_command text) returns text language plpgsql security definer set search_path='' as $$
declare u uuid; r text; cmd text:=lower(trim(p_command)); inbox jsonb; lines text;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_command is null or length(p_command)>512 then return 'Invalid test command.';end if;
 select user_id into u from private.wa_links where phone=p_phone;
 if not found then return 'Link your AgriConnect account in Profile first: https://agriconnect-q7c2.onrender.com/';end if;
 select account_role into r from public.profiles where id=u for no key update;
 if not found or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone) then return 'Link your AgriConnect account first.';end if;
 if r is distinct from 'manager' then
  if cmd in ('hi','hello','help','menu') then return private.wa_harvest_command(p_phone,p_command);end if;
  return 'FPO alerts require an FPO manager account.';
 end if;
 if cmd ~ '^read [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  if private.manager_read_for(u,split_part(cmd,' ',2)::uuid) then return 'Alert marked read. The underlying request, harvest or order is unchanged. Send ALERTS for your inbox.';end if;
  return 'No matching alert for your managed FPOs.';
 end if;
 if cmd not in ('hi','hello','help','menu','alerts') then return 'Send ALERTS to view your inbox or READ followed by an alert reference.';end if;
 inbox:=private.manager_inbox_for(u,5);
 select string_agg(case v->>'kind' when 'membership_requested' then 'New membership request' when 'harvest_submitted' then 'New harvest submitted' when 'order_confirmed' then 'New test order' else 'Test order cancelled' end||' | '||left(regexp_replace(v->>'fpo_name','[[:cntrl:]]',' ','g'),120)||E'\nREAD '||(v->>'id'),E'\n\n' order by ord) into lines from jsonb_array_elements(inbox->'alerts') with ordinality a(v,ord);
 return 'AgriConnect FPO manager inbox'||E'\nPending membership requests: '||(inbox->>'pending_members')||E'\nPending harvests: '||(inbox->>'pending_harvests')||E'\nOpen test orders: '||(inbox->>'open_orders')||E'\nUnread alerts: '||(inbox->>'unread')||E'\n\n'||coalesce(lines,'No unread alerts.')||E'\n\nShowing up to 5 unread alerts. Send READ plus its reference to dismiss an alert, then ALERTS to refresh. Review and manage work on https://agriconnect-q7c2.onrender.com/ . Reading does not approve, reject or modify anything.';
end $$;
create function public.wa_manager_command(p_phone text,p_command text) returns text language sql security invoker set search_path='' as $$select private.wa_manager_command(p_phone,p_command)$$;
revoke all on function private.wa_manager_command(text,text),public.wa_manager_command(text,text) from public,anon,authenticated,service_role;
grant execute on function private.wa_manager_command(text,text),public.wa_manager_command(text,text) to service_role;
commit;