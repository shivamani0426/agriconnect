begin;
alter table public.profiles add column account_role text check(account_role in ('farmer','manager','customer'));
do $$ begin
if exists(select 1 from public.profiles p where (select count(distinct m.role) from public.memberships m where m.user_id=p.id)>1 or (exists(select 1 from public.memberships m where m.user_id=p.id) and exists(select 1 from public.orders o where o.customer_id=p.id))) then raise exception 'Conflicting historical account roles require manual review';end if;
end $$;
update public.profiles p set account_role=case when exists(select 1 from public.memberships m where m.user_id=p.id and m.role='manager') then 'manager' when exists(select 1 from public.memberships m where m.user_id=p.id and m.role='farmer') then 'farmer' when exists(select 1 from public.orders o where o.customer_id=p.id) then 'customer' else null end;
create function private.account_role() returns text language sql stable security definer set search_path='' as $$ select account_role from public.profiles where id=(select auth.uid()) $$;
revoke all on function private.account_role() from public,anon,authenticated;
grant execute on function private.account_role() to authenticated;
create function private.lock_account_role() returns trigger language plpgsql set search_path='' as $$
begin
if new.account_role is null then raise exception 'Choose one account role';end if;
if tg_op='UPDATE' and old.account_role is not null and new.account_role is distinct from old.account_role then raise exception 'Account role is permanent';end if;
return new;
end $$;
create trigger profiles_lock_role before insert or update of account_role on public.profiles for each row execute function private.lock_account_role();
revoke all on function private.lock_account_role() from public,anon,authenticated;
grant update(account_role) on public.profiles to authenticated;
create or replace function private.is_manager(p_fpo uuid) returns boolean language sql stable security definer set search_path='' as $$ select coalesce(private.account_role()='manager',false) and exists(select 1 from public.memberships where fpo_id=p_fpo and user_id=(select auth.uid()) and role='manager' and status='active') $$;
create or replace function private.is_farmer(p_fpo uuid) returns boolean language sql stable security definer set search_path='' as $$ select coalesce(private.account_role()='farmer',false) and exists(select 1 from public.memberships where fpo_id=p_fpo and user_id=(select auth.uid()) and role='farmer' and status='active') $$;
create function private.enforce_membership_role() returns trigger language plpgsql set search_path='' as $$
begin
if not exists(select 1 from public.profiles p where p.id=new.user_id and p.account_role=new.role) then raise exception 'Membership must match permanent account role';end if;
return new;
end $$;
create trigger membership_account_role before insert or update of role,user_id on public.memberships for each row execute function private.enforce_membership_role();
revoke all on function private.enforce_membership_role() from public,anon,authenticated;
drop policy membership_request on public.memberships;
create policy membership_request on public.memberships for insert to authenticated with check(user_id=(select auth.uid()) and role='farmer' and status='pending' and (select private.account_role())='farmer');
create or replace function private.create_fpo(p_name text,p_location text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
if auth.uid() is null or private.account_role() is distinct from 'manager' then raise exception 'FPO manager account required';end if;
insert into public.fpos(name,location) values(trim(p_name),trim(p_location)) returning id into v_id;
insert into public.memberships values(v_id,auth.uid(),'manager','active');
insert into private.audit_events(actor,fpo_id,action,subject) values(auth.uid(),v_id,'fpo_created',v_id);
return v_id;
end $$;
create function private.enforce_order_role() returns trigger language plpgsql set search_path='' as $$
begin
if not exists(select 1 from public.profiles p where p.id=new.customer_id and p.account_role='customer') then raise exception 'Customer account required';end if;
return new;
end $$;
create trigger orders_customer_role before insert or update of customer_id on public.orders for each row execute function private.enforce_order_role();
revoke all on function private.enforce_order_role() from public,anon,authenticated;
create or replace function public.checkout_order(p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language plpgsql security invoker set search_path='' as $$
begin
if private.account_role() is distinct from 'customer' then raise exception 'Customer account required';end if;
return private.checkout_order(p_fpo,p_items,p_address,p_request);
end $$;
create or replace function public.checkout_demo_channel(p_channel text,p_fpo uuid,p_items jsonb,p_address text,p_request uuid) returns uuid language plpgsql security invoker set search_path='' as $$
begin
if private.account_role() is distinct from 'customer' then raise exception 'Customer account required';end if;
return private.checkout_demo_channel(p_channel,p_fpo,p_items,p_address,p_request);
end $$;
drop policy orders_read on public.orders;
create policy orders_read on public.orders for select to authenticated using((customer_id=(select auth.uid()) and (select private.account_role())='customer') or private.is_manager(fpo_id));
drop policy allocation_read on public.order_allocations;
create policy allocation_read on public.order_allocations for select to authenticated using((farmer_id=(select auth.uid()) and (select private.account_role())='farmer') or private.is_manager(fpo_id));
drop policy photo_upload on storage.objects;
create policy photo_upload on storage.objects for insert to authenticated with check(bucket_id='harvest-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.account_role())='farmer');
commit;