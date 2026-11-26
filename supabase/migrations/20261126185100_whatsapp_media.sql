begin;
create table private.wa_media_jobs(
 message_hash text primary key check(message_hash ~ '^[a-f0-9]{64}$'),
 phone_hash text not null, link_user uuid not null, link_at timestamptz not null,
 kind text not null check(kind in ('audio','image')),
 target uuid, path text unique,
 state text not null default 'processing' check(state in ('processing','attached','finished','failed','cleaning','cleaned')),
 expires_at timestamptz not null default (clock_timestamp()+interval '3 minutes'),
 created_at timestamptz not null default clock_timestamp(),
 check((kind='image' and target is not null and path is not null) or (kind='audio' and target is null and path is null))
);
alter table private.wa_media_jobs enable row level security;
revoke all on private.wa_media_jobs from public,anon,authenticated,service_role;
create function private.wa_media_claim(p_id text,p_phone text,p_kind text,p_target uuid default null,p_ext text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; linked timestamptz; r text; object_path text;
begin
 if p_id is null or p_id !~ '^[a-f0-9]{64}$' or p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_kind is null or p_kind not in ('audio','image') then return jsonb_build_object('state','denied');end if;
 perform pg_advisory_xact_lock(hashtextextended(p_phone,0));
 if exists(select 1 from public.whatsapp_webhook_receipts where message_hash=p_id) then return jsonb_build_object('state','duplicate');end if;
 if exists(select 1 from private.wa_media_jobs where message_hash=p_id) then return jsonb_build_object('state','busy');end if;
 select w.user_id,w.linked_at,p.account_role into u,linked,r from private.wa_links w join public.profiles p on p.id=w.user_id where w.phone=p_phone;
 if u is null then return jsonb_build_object('state','denied');end if;
 if p_kind='audio' then
  if not exists(select 1 from private.wa_voice_permission where user_id=u and expires_at>clock_timestamp()) then return jsonb_build_object('state','denied');end if;
  p_target:=null;
 else
  if r is distinct from 'farmer' or p_target is null or p_ext is null or p_ext not in ('jpg','png','webp') or not exists(select 1 from public.harvests h join public.memberships m on m.fpo_id=h.fpo_id and m.user_id=u and m.role='farmer' and m.status='active' where h.id=p_target and h.farmer_id=u and h.status='pending' and h.photo_path is null) then return jsonb_build_object('state','denied');end if;
  object_path:=u::text||'/wa-'||gen_random_uuid()::text||'.'||p_ext;
 end if;
 -- Bound concurrent media work per account, independent of arbitrary provider media IDs.
 if exists(select 1 from private.wa_media_jobs where link_user=u and state='processing' and expires_at>clock_timestamp()) then return jsonb_build_object('state','busy');end if;
 insert into private.wa_media_jobs(message_hash,phone_hash,link_user,link_at,kind,target,path) values(p_id,encode(sha256(convert_to(p_phone,'UTF8')),'hex'),u,linked,p_kind,p_target,object_path);
 return jsonb_build_object('state','claimed','path',object_path);
end $$;
create function private.wa_media_finish(p_id text,p_phone text,p_ok boolean,p_transcript text default null) returns boolean language plpgsql security definer set search_path='' as $$
declare j private.wa_media_jobs%rowtype; u uuid; linked timestamptz; r text; body text; final_state text:='failed'; f uuid;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_id is null or p_id !~ '^[a-f0-9]{64}$' then return false;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_phone,0));
 select * into j from private.wa_media_jobs where message_hash=p_id and phone_hash=encode(sha256(convert_to(p_phone,'UTF8')),'hex') and state='processing' and expires_at>clock_timestamp() for update;
 if not found then return false;end if;
 select w.user_id,w.linked_at,p.account_role into u,linked,r from private.wa_links w join public.profiles p on p.id=w.user_id where w.phone=p_phone;
 if u is distinct from j.link_user or linked is distinct from j.link_at then
  update private.wa_media_jobs set state='failed' where message_hash=p_id;return false;
 end if;
 -- The same profile lock as the existing review/checkout logic serializes role/link changes.
 perform 1 from public.profiles where id=u and account_role=r for no key update;
 if not found or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone and linked_at=linked) then update private.wa_media_jobs set state='failed' where message_hash=p_id;return false;end if;
 if j.kind='image' then
  if p_ok and r='farmer' and exists(select 1 from storage.objects where bucket_id='harvest-photos' and name=j.path) then
   update public.harvests h set photo_path=j.path where h.id=j.target and h.farmer_id=u and h.status='pending' and h.photo_path is null
   and exists(select 1 from public.memberships m where m.fpo_id=h.fpo_id and m.user_id=u and m.role='farmer' and m.status='active') returning h.fpo_id into f;
   if found then
    final_state:='attached';body:='Photo attached to your pending harvest '||j.target::text||'. FPO manager review is still required.';
    insert into private.audit_events(actor,fpo_id,action,subject) values(u,f,'whatsapp_harvest_photo_attached',j.target);
   end if;
  end if;
  body:=coalesce(body,'Photo could not be attached. Check that the harvest is yours, pending, and has no photo. Send a new photo with caption PHOTO <harvest reference>.');
 else
  if p_ok and p_transcript is not null and length(trim(p_transcript)) between 1 and 512 and exists(select 1 from private.wa_voice_permission where user_id=u and expires_at>clock_timestamp()) then
   body:='Voice transcript (not executed):'||E'\n'||private.wa_clean(trim(p_transcript),512)||E'\nReview it, then send a text command yourself. No action was performed.';
   final_state:='finished';
  else body:='Voice could not be transcribed. Check voice permission and send a new short voice note, or type your command.';end if;
 end if;
 insert into public.whatsapp_webhook_receipts(message_hash) values(p_id) on conflict do nothing;
 if not found then raise exception 'Media receipt conflict';end if;
 insert into private.wa_relay_outbox(message_hash,phone_hash,phone,link_user,link_at,link_role,reply)
 values(p_id,j.phone_hash,p_phone,u,linked,r,jsonb_build_object('body',body));
 update private.wa_media_jobs set state=final_state where message_hash=p_id;
 return true;
end $$;
-- A cleanup lease cannot overlap a successful attach; expired uploads can never be attached.
create function private.wa_media_cleanup() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update private.wa_media_jobs set state='failed' where state='processing' and expires_at<=clock_timestamp();
 with candidates as (
  select message_hash from private.wa_media_jobs j where path is not null and state in ('failed','cleaning') and not exists(select 1 from public.harvests h where h.photo_path=j.path)
  and (state='failed' or expires_at<=clock_timestamp()) order by created_at limit 10 for update skip locked
 ), claimed as (
  update private.wa_media_jobs j set state='cleaning',expires_at=clock_timestamp()+interval '2 minutes' from candidates c where j.message_hash=c.message_hash returning j.message_hash,j.path
 )
 select coalesce(jsonb_agg(to_jsonb(claimed)),'[]') into result from claimed;
 delete from private.wa_media_jobs where created_at<clock_timestamp()-interval '7 days' and (state in ('attached','finished','cleaned') or (state='failed' and path is null));
 delete from private.wa_voice_permission where expires_at<=clock_timestamp();
 delete from private.wa_advanced_cart where expires_at<=clock_timestamp();
 return result;
end $$;
create function private.wa_media_cleaned(p_id text) returns void language sql security definer set search_path='' as $$update private.wa_media_jobs set state='cleaned' where message_hash=p_id and state='cleaning'$$;
create function public.wa_media_claim(p_id text,p_phone text,p_kind text,p_target uuid default null,p_ext text default null) returns jsonb language sql security invoker set search_path='' as $$select private.wa_media_claim(p_id,p_phone,p_kind,p_target,p_ext)$$;
create function public.wa_media_finish(p_id text,p_phone text,p_ok boolean,p_transcript text default null) returns boolean language sql security invoker set search_path='' as $$select private.wa_media_finish(p_id,p_phone,p_ok,p_transcript)$$;
create function public.wa_media_cleanup() returns jsonb language sql security invoker set search_path='' as $$select private.wa_media_cleanup()$$;
create function public.wa_media_cleaned(p_id text) returns void language sql security invoker set search_path='' as $$select private.wa_media_cleaned(p_id)$$;
revoke all on function private.wa_media_claim(text,text,text,uuid,text),private.wa_media_finish(text,text,boolean,text),private.wa_media_cleanup(),private.wa_media_cleaned(text),public.wa_media_claim(text,text,text,uuid,text),public.wa_media_finish(text,text,boolean,text),public.wa_media_cleanup(),public.wa_media_cleaned(text) from public,anon,authenticated,service_role;
grant execute on function private.wa_media_claim(text,text,text,uuid,text),private.wa_media_finish(text,text,boolean,text),private.wa_media_cleanup(),private.wa_media_cleaned(text),public.wa_media_claim(text,text,text,uuid,text),public.wa_media_finish(text,text,boolean,text),public.wa_media_cleanup(),public.wa_media_cleaned(text) to service_role;
commit;
