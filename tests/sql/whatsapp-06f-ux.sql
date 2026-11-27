begin;
-- Four-language UX regression test on disposable data. No external messages.
insert into auth.users(id,email) values
('a9900000-0000-4000-8000-000000000001','manager@example.invalid'),
('a9900000-0000-4000-8000-000000000002','farmer@example.invalid'),
('a9900000-0000-4000-8000-000000000003','customer@example.invalid');
insert into public.profiles(id,display_name,account_role) select id,'06F QA',split_part(email,'@',1) from auth.users where id::text like 'a9900000-%';
insert into public.fpos(id,name,location) values('b9900000-0000-4000-8000-000000000001','06F FPO','Test');
insert into public.memberships(fpo_id,user_id,role,status) values
('b9900000-0000-4000-8000-000000000001','a9900000-0000-4000-8000-000000000001','manager','active'),
('b9900000-0000-4000-8000-000000000001','a9900000-0000-4000-8000-000000000002','farmer','active');
insert into private.wa_links(user_id,phone) values
('a9900000-0000-4000-8000-000000000001','919000009901'),
('a9900000-0000-4000-8000-000000000002','919000009902'),
('a9900000-0000-4000-8000-000000000003','919000009903');
set local role service_role;
do $qa$ declare q jsonb; id text; begin
 perform set_config('app.wa_advanced','on',true);
 perform public.wa_guide('919000009902','HI',false);
 perform public.wa_guide('919000009902','2',false);
 perform public.wa_guide('919000009902','1',false);
 perform public.wa_guide('919000009902','1',false);
 perform public.wa_guide('919000009902','QA06F Mangoes',false);
 perform public.wa_guide('919000009902','40',false);
 q:=public.wa_guide('919000009902','1',false);id:=q->'buttons'->0->>'id';
 if id is null then raise exception 'FAIL harvest preview';end if;
 if public.wa_guide('919000009902',id,true)->>'body' not like '%ಬೆಳೆ ಫೋಟೋ ನೇರವಾಗಿ%' then raise exception 'FAIL post-submit Kannada photo hint';end if;
 if public.wa_guide('919000009902','/PHOTOHELP',false)->>'body' not like '%ಶೀರ್ಷಿಕೆ ಬೇಡ%' then raise exception 'FAIL Kannada photo help';end if;
 perform set_config('qa06f.harvest',split_part(id,':',2),true);
end $qa$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','a9900000-0000-4000-8000-000000000001',true);
select public.review_harvest(current_setting('qa06f.harvest')::uuid,'A',4000,true,'');
reset role;
set local role service_role;
do $qa$ declare i int; q jsonb; id text; old_id text; expected text[]:=array['Only 40 kg','ಈಗ 40 ಕೆಜಿ','ప్రస్తుతం 40 కిలోలు','अभी केवल 40 किलो'];photo_terms text[]:=array['no caption is needed','ಶೀರ್ಷಿಕೆ ಬೇಡ','క్యాప్షన్ అవసరం లేదు','कैप्शन जरूरी नहीं']; begin
 perform set_config('app.wa_advanced','on',true);
 for i in 1..4 loop
  perform public.wa_guide('919000009903','HI',false);
  perform public.wa_guide('919000009903','LANGUAGE',false);
  perform public.wa_guide('919000009903',i::text,false);
  q:=public.wa_guide('919000009903','1',false);
  if q->>'body' not like '%ADD%' or q->>'body' not like '%QA06F Mangoes%' then raise exception 'FAIL guided list hint language % %',i,q;end if;
  q:=public.wa_guide('919000009903','garbage',false);
  if q->>'body' not like '%ADD%' or q ? 'buttons' then raise exception 'FAIL invalid choice recovery %',i;end if;
  q:=public.wa_guide('919000009903','ADD 1 50',false);
  if q->>'body' not like '%'||expected[i]||'%' or q ? 'buttons' then raise exception 'FAIL localized oversell % %',i,q;end if;
  q:=public.wa_guide('919000009903','/PHOTOHELP',false);
  if q->>'body' not like '%'||photo_terms[i]||'%' then raise exception 'FAIL localized photohelp % %',i,q;end if;
  q:=public.wa_guide('919000009903','10',false);id:=q->'buttons'->0->>'id';
  if id is null or q->>'body' not like '%₹400.00%' then raise exception 'FAIL correct quantity after error % %',i,q;end if;
  -- Typed IDs never execute; only actual signed button route can confirm.
  if public.wa_guide('919000009903',id,false) ? 'buttons' then raise exception 'FAIL text confirmation %',i;end if;
  perform public.wa_guide('919000009903',replace(id,'ac_confirm:','ac_cancel:'),true);
  if i=1 then old_id:=id;end if;
 end loop;
 perform public.wa_guide('919000009903','LANGUAGE',false);perform public.wa_guide('919000009903','1',false);
 perform public.wa_guide('919000009903','1',false);
 q:=public.wa_guide('919000009903','1',false);
 if q->>'body' not like '%Selected: QA06F Mangoes%' then raise exception 'FAIL selected crop %',q;end if;
 perform public.wa_guide('919000009903','0',false);
 perform public.wa_guide('919000009903','1',false);
 q:=public.wa_guide('919000009903','ADD 1 10',false);id:=q->'buttons'->0->>'id';
 if id is null or q->>'body' not like '%₹400.00%' then raise exception 'FAIL shortcut preview';end if;
 if public.wa_guide('919000009903',old_id,true)->>'body' like '%Test order confirmed%' then raise exception 'FAIL stale preview';end if;
 if public.wa_guide('919000009903',id,true)->>'body' not like '%Test order confirmed%' then raise exception 'FAIL actual confirmation';end if;
 -- The separate multi-item cart remains available, with explicit slash escape.
 perform public.wa_guide('919000009903','1',false);
 if public.wa_guide('919000009903','/SEARCH QA06F Mangoes',false)->>'body' not like '%Search results%' then raise exception 'FAIL explicit cart search';end if;
 if public.wa_guide('919000009903','ADD 1 2',false)->>'body' not like '%Added to cart%' then raise exception 'FAIL advanced cart unchanged';end if;
end $qa$;
reset role;
do $qa$ begin
 if (select count(*) from public.orders)<>1 or not exists(select 1 from public.inventory_lots where harvest_id=current_setting('qa06f.harvest')::uuid and available_kg=30 and reserved_kg=10) then raise exception 'FAIL UX changed transaction invariants';end if;
 if has_function_privilege('anon','private.wa_ux_phrase(text,text)','execute') or has_function_privilege('authenticated','private.wa_guide_base(text,text,boolean)','execute') then raise exception 'FAIL helper privileges';end if;
end $qa$;
select 'PASS 06F: four languages, localized stock limits, guided shortcut, retry without reset, farmer photo hints, stale/text confirmation isolation and cart compatibility' result;
rollback;
