begin;
create table private.wa_links (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 phone text not null unique check(phone ~ '^[1-9][0-9]{6,14}$'),
 linked_at timestamptz not null default now()
);
create table private.wa_link_requests (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 phone text not null check(phone ~ '^[1-9][0-9]{6,14}$'),
 code_hash bytea not null unique,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null
);
alter table private.wa_links enable row level security;
alter table private.wa_link_requests enable row level security;
revoke all on private.wa_links,private.wa_link_requests from public,anon,authenticated,service_role;
create function private.wa_begin(p_phone text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); code uuid:=gen_random_uuid(); expiry timestamptz:=clock_timestamp()+interval '10 minutes';
begin
 if u is null or p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' then raise exception 'Enter a valid phone number with country code';end if;
 perform 1 from public.profiles where id=u and account_role is not null for update;
 if not found then raise exception 'Complete your profile first';end if;
 if exists(select 1 from private.wa_links where user_id=u) then raise exception 'Unlink your existing WhatsApp number first';end if;
 if exists(select 1 from private.wa_link_requests where user_id=u and created_at>clock_timestamp()-interval '10 seconds') then raise exception 'Please wait 10 seconds before generating a new code';end if;
 insert into private.wa_link_requests(user_id,phone,code_hash,created_at,expires_at) values(u,p_phone,sha256(convert_to(code::text,'UTF8')),clock_timestamp(),expiry)
 on conflict(user_id) do update set phone=excluded.phone,code_hash=excluded.code_hash,created_at=excluded.created_at,expires_at=excluded.expires_at;
 return jsonb_build_object('code',code::text,'expires_at',expiry);
end $$;
create function private.wa_status() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); l private.wa_links%rowtype; r private.wa_link_requests%rowtype;
begin
 if u is null then raise exception 'Sign in required';end if;
 select * into l from private.wa_links where user_id=u;
 if found then return jsonb_build_object('status','linked','last4',right(l.phone,4),'linked_at',l.linked_at);end if;
 select * into r from private.wa_link_requests where user_id=u and expires_at>now();
 if found then return jsonb_build_object('status','pending','last4',right(r.phone,4),'expires_at',r.expires_at);end if;
 return jsonb_build_object('status','unlinked');
end $$;
create function private.wa_unlink() returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null then raise exception 'Sign in required';end if;
 perform 1 from public.profiles where id=u for update;
 delete from private.wa_link_requests where user_id=u;
 delete from private.wa_links where user_id=u;
end $$;
-- Only the signed webhook's server credential may redeem. Caller-supplied phone never grants a role.
create function private.wa_redeem(p_phone text,p_code uuid) returns text language plpgsql security definer set search_path='' as $$
declare u uuid; r private.wa_link_requests%rowtype;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or p_code is null then return 'invalid';end if;
 select user_id into u from private.wa_link_requests where code_hash=sha256(convert_to(p_code::text,'UTF8')) and phone=p_phone and expires_at>clock_timestamp();
 if not found then return 'invalid';end if;
 perform 1 from public.profiles where id=u and account_role is not null for update;
 if not found then return 'invalid';end if;
 select * into r from private.wa_link_requests where user_id=u and code_hash=sha256(convert_to(p_code::text,'UTF8')) and phone=p_phone and expires_at>clock_timestamp() for update;
 if not found then return 'invalid';end if;
 insert into private.wa_links(user_id,phone) values(u,p_phone) on conflict do nothing;
 if not found then return 'unavailable';end if;
 delete from private.wa_link_requests where user_id=u;
 return 'linked';
end $$;
create function public.wa_begin(p_phone text) returns jsonb language sql security invoker set search_path='' as $$select private.wa_begin(p_phone)$$;
create function public.wa_status() returns jsonb language sql stable security invoker set search_path='' as $$select private.wa_status()$$;
create function public.wa_unlink() returns void language sql security invoker set search_path='' as $$select private.wa_unlink()$$;
create function public.wa_redeem(p_phone text,p_code uuid) returns text language sql security invoker set search_path='' as $$select private.wa_redeem(p_phone,p_code)$$;
revoke all on function private.wa_begin(text),private.wa_status(),private.wa_unlink(),private.wa_redeem(text,uuid),public.wa_begin(text),public.wa_status(),public.wa_unlink(),public.wa_redeem(text,uuid) from public,anon,authenticated,service_role;
grant execute on function private.wa_begin(text),private.wa_status(),private.wa_unlink(),public.wa_begin(text),public.wa_status(),public.wa_unlink() to authenticated;
grant usage on schema private to service_role;
grant execute on function private.wa_redeem(text,uuid),public.wa_redeem(text,uuid) to service_role;
commit;