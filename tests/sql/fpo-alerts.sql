begin;
insert into auth.users(id,email) values
('e7000000-0000-4000-8000-000000000001','manager@example.invalid'),('e7000000-0000-4000-8000-000000000002','manager@example.invalid'),('e7000000-0000-4000-8000-000000000003','manager@example.invalid'),('e7000000-0000-4000-8000-000000000004','farmer@example.invalid'),('e7000000-0000-4000-8000-000000000005','farmer@example.invalid'),('e7000000-0000-4000-8000-000000000006','customer@example.invalid');
insert into public.profiles(id,display_name,account_role) select id,'Alert QA',split_part(email,'@',1) from auth.users;
insert into public.fpos(id,name,location) values('f7000000-0000-4000-8000-000000000001','QA Farm','Test'),('f7000000-0000-4000-8000-000000000002','Other FPO','Test');
insert into public.memberships(fpo_id,user_id,role,status) values
('f7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000001','manager','active'),
('f7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000002','manager','active'),
('f7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000003','manager','active'),
('f7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000004','farmer','active'),
('f7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000005','farmer','pending'),
('f7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000004','farmer','pending');
insert into private.wa_links(user_id,phone) values
('e7000000-0000-4000-8000-000000000001','919000007001'),('e7000000-0000-4000-8000-000000000002','919000007002'),('e7000000-0000-4000-8000-000000000003','919000007003'),('e7000000-0000-4000-8000-000000000004','919000007004'),('e7000000-0000-4000-8000-000000000006','919000007006');
set local role service_role;
select public.wa_harvest_command('919000007004','FPOS');
select set_config('qa.h',substring(public.wa_harvest_command('919000007004','HARVEST 1 | QA tomatoes | 10 | 2026-01-01') from 'SUBMIT ([0-9a-f-]{36})'),true);
select public.wa_harvest_command('919000007004','SUBMIT '||current_setting('qa.h'));
select public.wa_harvest_command('919000007004','SUBMIT '||current_setting('qa.h'));
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','e7000000-0000-4000-8000-000000000001',true);
do $qa$ begin
 if public.manager_inbox()->>'unread'<>'2' or public.manager_inbox()->>'pending_members'<>'1' or public.manager_inbox()->>'pending_harvests'<>'1' then raise exception 'FAIL inbox before approval';end if;
end $qa$;
select public.review_harvest(current_setting('qa.h')::uuid,'A',1000,true,'');
reset role;
set local role service_role;
select public.wa_order_command('919000007006','SHOP');
select set_config('qa.quote',substring(public.wa_order_command('919000007006','BUY 1 2') from 'CONFIRM ([0-9a-f-]{36})'),true);
select set_config('qa.order',substring(public.wa_order_command('919000007006','CONFIRM '||current_setting('qa.quote')) from 'Order ([0-9a-f-]{36})'),true);
select public.wa_order_command('919000007006','CONFIRM '||current_setting('qa.quote'));
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','e7000000-0000-4000-8000-000000000006',true);
select public.transition_order(current_setting('qa.order')::uuid,'cancelled');
do $qa$ begin
 begin perform public.manager_inbox();raise exception 'FAIL customer access';exception when raise_exception then if sqlerrm<>'FPO manager account required' then raise;end if;end;
 begin perform public.checkout_order('f7000000-0000-4000-8000-000000000001','[{"crop":"QA tomatoes","grade":"A","price_paise_per_kg":1000,"quantity_kg":11}]','Test address',gen_random_uuid());raise exception 'FAIL oversell';exception when raise_exception then if sqlerrm not like 'Stock or price changed%' then raise;end if;end;
end $qa$;
reset role;
do $qa$ begin
 if (select count(*) from private.fpo_alerts where fpo_id='f7000000-0000-4000-8000-000000000001')<>4 then raise exception 'FAIL duplicate or rollback event';end if;
 if has_function_privilege('anon','public.manager_inbox()','execute') or has_function_privilege('authenticated','public.wa_manager_command(text,text)','execute') or has_function_privilege('authenticated','private.manager_inbox_for(uuid,integer)','execute') or has_table_privilege('authenticated','private.fpo_alerts','select') then raise exception 'FAIL grants';end if;
end $qa$;
select set_config('qa.alert',(select id::text from private.fpo_alerts where kind='harvest_submitted' and subject_id=current_setting('qa.h')::uuid),true);
set local role service_role;
do $qa$ declare r text; begin
 r:=public.wa_manager_command('919000007001','ALERTS');
 if r not like '%Unread alerts: 4%' or r like '%Other FPO%' or r not like '%New test order%' or r not like '%Test order cancelled%' then raise exception 'FAIL WA inbox %',r;end if;
 if public.wa_manager_command('919000007003','READ '||current_setting('qa.alert')) not like 'No matching%' then raise exception 'FAIL cross FPO ack';end if;
 if public.wa_manager_command('919000007004','ALERTS') not like '%manager account%' then raise exception 'FAIL farmer access';end if;
 if public.wa_manager_command('919000007009','ALERTS') not like 'Link your%' then raise exception 'FAIL unlinked';end if;
 if public.wa_manager_command('919000007006','HI') not like '%SHOP%' or public.wa_manager_command('919000007004','HI') not like '%FPOS%' then raise exception 'FAIL role greeting';end if;
 if public.wa_manager_command('919000007001','READ '||current_setting('qa.alert')) not like 'Alert marked read%' then raise exception 'FAIL WA ack';end if;
end $qa$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','e7000000-0000-4000-8000-000000000001',true);
do $qa$ begin
 if public.manager_inbox()->>'unread'<>'3' or public.manager_inbox()->>'pending_members'<>'1' or public.manager_inbox()->>'pending_harvests'<>'0' or public.manager_inbox()->>'open_orders'<>'0' then raise exception 'FAIL shared read/work status';end if;
 if not public.manager_read(current_setting('qa.alert')::uuid) then raise exception 'FAIL repeat ack';end if;
end $qa$;
select set_config('request.jwt.claim.sub','e7000000-0000-4000-8000-000000000002',true);
do $qa$ begin if public.manager_inbox()->>'unread'<>'4' then raise exception 'FAIL independent read status';end if;if not public.manager_read(current_setting('qa.alert')::uuid) then raise exception 'FAIL website ack';end if;end $qa$;
reset role;
update public.memberships set status='rejected' where user_id='e7000000-0000-4000-8000-000000000002' and fpo_id='f7000000-0000-4000-8000-000000000001';
set local role service_role;
do $qa$ begin if public.wa_manager_command('919000007002','ALERTS') not like '%Unread alerts: 0%' or public.wa_manager_command('919000007002','READ '||current_setting('qa.alert')) not like 'No matching%' then raise exception 'FAIL revoked membership';end if;end $qa$;
reset role;
select 'PASS: transactional alerts, no duplicates on replay or rollback, manager FPO isolation, role restrictions, per-manager read state, cross-channel acknowledgement and live work counts' result;
rollback;