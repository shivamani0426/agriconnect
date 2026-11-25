begin;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade, display_name text not null check(length(trim(display_name)) between 1 and 100));
create table public.fpos(id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 2 and 120), location text not null check(length(trim(location)) between 2 and 150), created_at timestamptz not null default now());
create table public.memberships(fpo_id uuid references public.fpos(id), user_id uuid references public.profiles(id), role text not null check(role in ('manager','farmer')), status text not null check(status in ('pending','active','rejected')), primary key(fpo_id,user_id));
create index memberships_user_idx on public.memberships(user_id);
create table public.harvests(id uuid primary key default gen_random_uuid(), fpo_id uuid not null, farmer_id uuid not null, crop text not null check(length(trim(crop)) between 1 and 100), quantity_kg numeric(12,3) not null check(quantity_kg > 0), harvest_date date not null, photo_path text, status text not null default 'pending' check(status in ('pending','approved','rejected')), grade text check(grade in ('A','B','C')), rejection_reason text, created_at timestamptz not null default now(), foreign key(fpo_id,farmer_id) references public.memberships(fpo_id,user_id));
create index harvests_fpo_idx on public.harvests(fpo_id,status);
create index harvests_farmer_idx on public.harvests(farmer_id);
create table public.inventory_lots(id uuid primary key default gen_random_uuid(), harvest_id uuid unique not null references public.harvests(id), fpo_id uuid not null references public.fpos(id), crop text not null, grade text not null check(grade in ('A','B','C')), available_kg numeric(12,3) not null check(available_kg >= 0), reserved_kg numeric(12,3) not null default 0 check(reserved_kg >= 0), price_paise_per_kg integer not null check(price_paise_per_kg > 0), published boolean not null default true);
create index lots_fpo_idx on public.inventory_lots(fpo_id);
create table private.audit_events(id bigint generated always as identity primary key, actor uuid, fpo_id uuid, action text not null, subject uuid, created_at timestamptz not null default now());
create table private.integration_events(id uuid primary key default gen_random_uuid(), channel text not null check(channel in ('web','whatsapp','ondc')), external_id text not null, event_type text not null, payload jsonb not null, status text not null default 'pending' check(status in ('pending','processed','failed')), created_at timestamptz not null default now(), unique(channel,external_id,event_type));
create function private.is_manager(p_fpo uuid) returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.memberships where fpo_id=p_fpo and user_id=(select auth.uid()) and role='manager' and status='active') $$;
create function private.is_farmer(p_fpo uuid) returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.memberships where fpo_id=p_fpo and user_id=(select auth.uid()) and role='farmer' and status='active') $$;
create function private.can_read_photo(p_name text) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.harvests h where h.photo_path=p_name and (h.farmer_id=(select auth.uid()) or private.is_manager(h.fpo_id))) $$;
create function private.create_fpo(p_name text,p_location text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Profile required'; end if;
insert into public.fpos(name,location) values(trim(p_name),trim(p_location)) returning id into v_id;
insert into public.memberships values(v_id,auth.uid(),'manager','active');
insert into private.audit_events(actor,fpo_id,action,subject) values(auth.uid(),v_id,'fpo_created',v_id);
return v_id;
end $$;
create function private.review_member(p_fpo uuid,p_user uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
if auth.uid() is null or not private.is_manager(p_fpo) then raise exception 'Manager required'; end if;
update public.memberships set status=case when p_approve then 'active' else 'rejected' end where fpo_id=p_fpo and user_id=p_user and role='farmer' and status='pending';
if not found then raise exception 'No pending request'; end if;
insert into private.audit_events(actor,fpo_id,action,subject) values(auth.uid(),p_fpo,'membership_reviewed',p_user);
end $$;
create function private.review_harvest(p_id uuid,p_grade text,p_price integer,p_approve boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare h public.harvests%rowtype;
begin
select * into h from public.harvests where id=p_id for update;
if not found or auth.uid() is null or not private.is_manager(h.fpo_id) then raise exception 'Manager required or harvest missing'; end if;
if h.status <> 'pending' then raise exception 'Already reviewed'; end if;
if p_approve then
if p_grade is null or p_grade not in ('A','B','C') or p_price is null or p_price <= 0 then raise exception 'Grade and positive price required'; end if;
update public.harvests set status='approved',grade=p_grade where id=p_id;
insert into public.inventory_lots(harvest_id,fpo_id,crop,grade,available_kg,price_paise_per_kg) values(h.id,h.fpo_id,h.crop,p_grade,h.quantity_kg,p_price);
else
if nullif(trim(p_reason),'') is null then raise exception 'Rejection reason required'; end if;
update public.harvests set status='rejected',rejection_reason=trim(p_reason) where id=p_id;
end if;
insert into private.audit_events(actor,fpo_id,action,subject) values(auth.uid(),h.fpo_id,'harvest_reviewed',h.id);
end $$;
create function public.create_fpo(p_name text,p_location text) returns uuid language sql security invoker set search_path='' as $$ select private.create_fpo(p_name,p_location) $$;
create function public.review_member(p_fpo uuid,p_user uuid,p_approve boolean) returns void language sql security invoker set search_path='' as $$ select private.review_member(p_fpo,p_user,p_approve) $$;
create function public.review_harvest(p_id uuid,p_grade text,p_price integer,p_approve boolean,p_reason text) returns void language sql security invoker set search_path='' as $$ select private.review_harvest(p_id,p_grade,p_price,p_approve,p_reason) $$;
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on all functions in schema private to authenticated;
revoke all on function public.create_fpo(text,text),public.review_member(uuid,uuid,boolean),public.review_harvest(uuid,text,integer,boolean,text) from public,anon,authenticated;
grant execute on function public.create_fpo(text,text),public.review_member(uuid,uuid,boolean),public.review_harvest(uuid,text,integer,boolean,text) to authenticated;
alter table public.profiles enable row level security;
alter table public.fpos enable row level security;
alter table public.memberships enable row level security;
alter table public.harvests enable row level security;
alter table public.inventory_lots enable row level security;
alter table private.audit_events enable row level security;
alter table private.integration_events enable row level security;
revoke all on public.profiles,public.fpos,public.memberships,public.harvests,public.inventory_lots from anon,authenticated;
grant select,insert on public.profiles to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant select on public.fpos to anon,authenticated;
grant select,insert on public.memberships to authenticated;
grant select,insert on public.harvests to authenticated;
grant select on public.inventory_lots to authenticated;
create policy profile_self on public.profiles for select to authenticated using(id=(select auth.uid()) or exists(select 1 from public.memberships m where m.user_id=profiles.id and private.is_manager(m.fpo_id)));
create policy profile_insert on public.profiles for insert to authenticated with check(id=(select auth.uid()));
create policy profile_update on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy fpo_directory on public.fpos for select to anon,authenticated using(true);
create policy membership_read on public.memberships for select to authenticated using(user_id=(select auth.uid()) or private.is_manager(fpo_id));
create policy membership_request on public.memberships for insert to authenticated with check(user_id=(select auth.uid()) and role='farmer' and status='pending');
create policy harvest_read on public.harvests for select to authenticated using(farmer_id=(select auth.uid()) or private.is_manager(fpo_id));
create policy harvest_submit on public.harvests for insert to authenticated with check(farmer_id=(select auth.uid()) and private.is_farmer(fpo_id) and status='pending' and grade is null and rejection_reason is null and harvest_date<=current_date and (photo_path is null or (split_part(photo_path,'/',1)=(select auth.uid())::text)));
create policy inventory_manager_read on public.inventory_lots for select to authenticated using(private.is_manager(fpo_id) or exists(select 1 from public.harvests h where h.id=harvest_id and h.farmer_id=(select auth.uid())));
-- Public catalogue intentionally exposes aggregate stock only, never farmer identifiers.
create function private.catalogue() returns table(fpo_id uuid,fpo_name text,crop text,grade text,price_paise_per_kg integer,available_kg numeric) language sql stable security definer set search_path='' as $$ select l.fpo_id,f.name,l.crop,l.grade,l.price_paise_per_kg,sum(l.available_kg) from public.inventory_lots l join public.fpos f on f.id=l.fpo_id where l.published and l.available_kg>0 group by l.fpo_id,f.name,l.crop,l.grade,l.price_paise_per_kg $$;
revoke all on function private.catalogue() from public,anon,authenticated;
grant usage on schema private to anon;
grant execute on function private.catalogue() to anon,authenticated;
create function public.catalogue() returns table(fpo_id uuid,fpo_name text,crop text,grade text,price_paise_per_kg integer,available_kg numeric) language sql stable security invoker set search_path='' as $$ select * from private.catalogue() $$;
revoke all on function public.catalogue() from public,anon,authenticated;
grant execute on function public.catalogue() to anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('harvest-photos','harvest-photos',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy photo_upload on storage.objects for insert to authenticated with check(bucket_id='harvest-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy photo_read on storage.objects for select to authenticated using(bucket_id='harvest-photos' and ((storage.foldername(name))[1]=(select auth.uid())::text or private.can_read_photo(name)));
commit;
