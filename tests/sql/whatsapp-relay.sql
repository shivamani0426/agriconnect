begin;
insert into auth.users(id,email) values('a9500000-0000-4000-8000-000000000001','farmer@example.invalid'),('a9500000-0000-4000-8000-000000000002','customer@example.invalid');
insert into public.profiles(id,display_name,account_role) values('a9500000-0000-4000-8000-000000000001','Relay Farmer','farmer'),('a9500000-0000-4000-8000-000000000002','Relay Customer','customer');
insert into private.wa_links(user_id,phone) values('a9500000-0000-4000-8000-000000000001','919000009501'),('a9500000-0000-4000-8000-000000000002','919000009502');
do $qa$ begin
 if has_table_privilege('anon','private.wa_relay_outbox','select') or has_table_privilege('authenticated','private.wa_relay_outbox','select') or has_function_privilege('authenticated','public.wa_relay_prepare(text,text,text,text)','execute') or has_function_privilege('anon','public.wa_relay_health()','execute') or has_function_privilege('authenticated','public.wa_relay_take(text,text)','execute') then raise exception 'FAIL queue ACL';end if;
end $qa$;
set local role service_role;
do $qa$ declare q jsonb; list_id text; begin
 if not public.wa_relay_prepare(repeat('a',64),'919000009501','guide','HI') then raise exception 'FAIL prepare';end if;
 if public.wa_relay_prepare(repeat('a',64),'919000009501','guide','HI') then raise exception 'FAIL replay';end if;
 if public.wa_relay_take('919000009502',repeat('a',64)) is not null then raise exception 'FAIL cross recipient';end if;
 q:=public.wa_relay_take('919000009501',repeat('a',64));
 if q->>'attempt'<>'1' or jsonb_array_length(q->'reply'->'list')<>4 then raise exception 'FAIL language list: %',q;end if;
 list_id:=q->'reply'->'list'->0->>'id';
 perform set_config('qa.list_id',list_id,true);
 if public.wa_relay_take('919000009501',repeat('a',64)) is not null then raise exception 'FAIL double claim';end if;
 if not public.wa_relay_finish(repeat('a',64),1,'retryable',null,25) then raise exception 'FAIL retry';end if;
 if public.wa_relay_take('919000009501',repeat('a',64)) is not null then raise exception 'FAIL backoff';end if;
end $qa$;
reset role;
update private.wa_relay_outbox set due_at=clock_timestamp()-interval '1 second' where message_hash=repeat('a',64);
set local role service_role;
do $qa$ declare q jsonb; begin
 q:=public.wa_relay_take('919000009501',repeat('a',64));
 if q->>'attempt'<>'2' or q->'reply'->'list'->0->>'id' is distinct from current_setting('qa.list_id') then raise exception 'FAIL stored reply';end if;
 if public.wa_relay_finish(repeat('a',64),1,'accepted','wamid.old',12) then raise exception 'FAIL stale worker';end if;
 -- Provider callback can precede the HTTP acknowledgement.
 perform public.wa_relay_delivery('919000009501','wamid.test','delivered');
 if not public.wa_relay_finish(repeat('a',64),2,'accepted','wamid.test',20) then raise exception 'FAIL accept';end if;
 perform public.wa_relay_delivery('919000009501','wamid.test','read');
 perform public.wa_relay_delivery('919000009501','wamid.test','sent');
 perform public.wa_relay_delivery('919000009502','wamid.test','failed');
 if not public.wa_relay_prepare(repeat('b',64),'919000009501','list',current_setting('qa.list_id')) then raise exception 'FAIL list selection';end if;
 q:=public.wa_relay_take('919000009501',repeat('b',64));
 if q->'reply'->>'body' not like '%Submit harvest%' or jsonb_array_length(q->'reply'->'list')<>3 then raise exception 'FAIL role menu: %',q;end if;
 perform public.wa_relay_finish(repeat('b',64),1,'accepted','wamid.menu',10);
 perform public.wa_relay_prepare(repeat('c',64),'919000009501','list',current_setting('qa.list_id'));
 q:=public.wa_relay_take('919000009501',repeat('c',64));
 if q->'reply'->>'body' not like '%expired%' then raise exception 'FAIL stale menu: %',q;end if;
 perform public.wa_relay_finish(repeat('c',64),1,'unknown',null,20);
 if public.wa_relay_take('919000009501',repeat('c',64)) is not null then raise exception 'FAIL unknown resend';end if;
 perform public.wa_relay_prepare(repeat('d',64),'919000009501','guide','HI');
end $qa$;
reset role;
do $qa$ begin
 if not exists(select 1 from private.wa_relay_outbox where message_hash=repeat('a',64) and state='accepted' and delivery='read' and reply is null and phone is null) then raise exception 'FAIL accepted state/delivery/privacy';end if;
end $qa$;
-- Re-link changes must invalidate previously generated payloads.
delete from private.wa_links where user_id='a9500000-0000-4000-8000-000000000001';
insert into private.wa_links(user_id,phone,linked_at) values('a9500000-0000-4000-8000-000000000001','919000009501',clock_timestamp()+interval '1 second');
set local role service_role;
do $qa$ declare h jsonb; begin
 if public.wa_relay_take('919000009501',repeat('d',64)) is not null then raise exception 'FAIL link-instance binding';end if;
 h:=public.wa_relay_health();
 if h->'states'->>'expired' is null or h->'delivery'->>'read' is null then raise exception 'FAIL diagnostics %',h;end if;
end $qa$;
reset role;
select 'PASS: atomic receipt, menu token, isolation, retry delay, lease, delivery order, privacy, link revocation and diagnostics' result;
rollback;
