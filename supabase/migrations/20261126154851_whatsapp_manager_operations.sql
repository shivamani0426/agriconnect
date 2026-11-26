begin;
-- Shared actor-aware cores: no JWT impersonation. Explicit actor is only available to private trusted code.
create function private.manager_actor(u uuid,f uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if u is null or not exists(select 1 from public.profiles where id=u and account_role='manager') then return false;end if;
 perform 1 from public.memberships where user_id=u and fpo_id=f and role='manager' and status='active' for share;
 return found;
end $$;
create function private.review_member_for(u uuid,p_fpo uuid,p_user uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
begin
if not private.manager_actor(u,p_fpo) then raise exception 'Manager required'; end if;
update public.memberships set status=case when p_approve then 'active' else 'rejected' end where fpo_id=p_fpo and user_id=p_user and role='farmer' and status='pending';
if not found then raise exception 'No pending request'; end if;
insert into private.audit_events(actor,fpo_id,action,subject) values(u,p_fpo,'membership_reviewed',p_user);
end $$;
create function private.review_harvest_for(u uuid,p_id uuid,p_grade text,p_price integer,p_approve boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare h public.harvests%rowtype;
begin
select * into h from public.harvests where id=p_id for update;
if not found or not private.manager_actor(u,h.fpo_id) then raise exception 'Manager required or harvest missing'; end if;
if h.status <> 'pending' then raise exception 'Already reviewed'; end if;
if p_approve then
if p_grade is null or p_grade not in ('A','B','C') or p_price is null or p_price <= 0 then raise exception 'Grade and positive price required'; end if;
update public.harvests set status='approved',grade=p_grade where id=p_id;
insert into public.inventory_lots(harvest_id,fpo_id,crop,grade,available_kg,price_paise_per_kg) values(h.id,h.fpo_id,h.crop,p_grade,h.quantity_kg,p_price);
else
if nullif(trim(p_reason),'') is null then raise exception 'Rejection reason required'; end if;
update public.harvests set status='rejected',rejection_reason=trim(p_reason) where id=p_id;
end if;
insert into private.audit_events(actor,fpo_id,action,subject) values(u,h.fpo_id,'harvest_reviewed',h.id);
end $$;
create function private.transition_order_for(u uuid,p_id uuid,p_next text) returns void language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; manager boolean; a record;
begin
if u is null then raise exception 'Sign in required'; end if;
select * into o from public.orders where id=p_id for update;
if not found then raise exception 'Order unavailable'; end if;
manager:=private.manager_actor(u,o.fpo_id);
if not manager and (o.customer_id<>u or not exists(select 1 from public.profiles where id=u and account_role='customer')) then raise exception 'Order unavailable'; end if;
if p_next is null then raise exception 'Invalid transition'; end if;
if p_next='cancelled' then
 if not ((o.customer_id=u and o.status='confirmed') or (manager and o.status in ('confirmed','packed'))) then raise exception 'Cancellation not allowed'; end if;
elsif not manager or not ((o.status='confirmed' and p_next='packed') or (o.status='packed' and p_next='out_for_delivery') or (o.status='out_for_delivery' and p_next='delivered')) then raise exception 'Invalid delivery transition'; end if;
perform 1 from public.fpos where id=o.fpo_id for update;
if p_next in ('cancelled','delivered') then
 for a in select * from public.order_allocations where order_id=o.id order by lot_id loop
  if a.status<>'reserved' then raise exception 'Allocation already finalized'; end if;
  update public.inventory_lots set reserved_kg=reserved_kg-a.quantity_kg,available_kg=available_kg+case when p_next='cancelled' then a.quantity_kg else 0 end where id=a.lot_id and reserved_kg>=a.quantity_kg;
  if not found then raise exception 'Reservation inconsistent'; end if;
  update public.order_allocations set status=p_next where id=a.id;
 end loop;
end if;
update public.orders set status=p_next,payment_status=case when p_next='cancelled' then 'simulated_refunded' else payment_status end,updated_at=now() where id=o.id;
insert into public.order_events(order_id,status) values(o.id,p_next);
insert into private.audit_events(actor,fpo_id,action,subject) values(u,o.fpo_id,'order_'||p_next,o.id);
end $$;
revoke all on function private.manager_actor(uuid,uuid),private.review_member_for(uuid,uuid,uuid,boolean),private.review_harvest_for(uuid,uuid,text,integer,boolean,text),private.transition_order_for(uuid,uuid,text) from public,anon,authenticated,service_role;
create or replace function private.review_member(p_fpo uuid,p_user uuid,p_approve boolean) returns void language sql security definer set search_path='' as $$select private.review_member_for(auth.uid(),p_fpo,p_user,p_approve)$$;
create or replace function private.review_harvest(p_id uuid,p_grade text,p_price integer,p_approve boolean,p_reason text) returns void language sql security definer set search_path='' as $$select private.review_harvest_for(auth.uid(),p_id,p_grade,p_price,p_approve,p_reason)$$;
create or replace function private.transition_order(p_id uuid,p_next text) returns void language sql security definer set search_path='' as $$select private.transition_order_for(auth.uid(),p_id,p_next)$$;
create or replace function private.wa_phrase(l text,k text) returns text language sql immutable set search_path='' as $$
 select coalesce(($dict${"choose":["Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी","Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी","Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी","Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी"],"link":["First link your account in Profile: ","ಮೊದಲು ಪ್ರೊಫೈಲ್‌ನಲ್ಲಿ ಖಾತೆಯನ್ನು ಲಿಂಕ್ ಮಾಡಿ: ","ముందుగా ప్రొఫైల్‌లో ఖాతాను లింక్ చేయండి: ","पहले प्रोफ़ाइल में खाता लिंक करें: "],"customer":["Welcome! Choose:\n1. Buy produce\n2. Track latest order\n3. Change language\n4. Cancel an order","ಸ್ವಾಗತ! ಆಯ್ಕೆ ಮಾಡಿ:\n1. ಬೆಳೆ ಖರೀದಿ\n2. ಕೊನೆಯ ಆರ್ಡರ್ ಸ್ಥಿತಿ\n3. ಭಾಷೆ ಬದಲಿಸಿ\n4. ಆರ್ಡರ್ ರದ್ದು ಮಾಡಿ","స్వాగతం! ఎంచుకోండి:\n1. పంట కొనండి\n2. చివరి ఆర్డర్ స్థితి\n3. భాష మార్చండి\n4. ఆర్డర్ రద్దు చేయండి","स्वागत है! चुनें:\n1. उपज खरीदें\n2. अंतिम ऑर्डर की स्थिति\n3. भाषा बदलें\n4. ऑर्डर रद्द करें"],"farmer":["Welcome! Choose:\n1. Submit harvest\n2. My harvests\n3. Change language","ಸ್ವಾಗತ! ಆಯ್ಕೆ ಮಾಡಿ:\n1. ಬೆಳೆ ಸಲ್ಲಿಸಿ\n2. ನನ್ನ ಬೆಳೆಗಳು\n3. ಭಾಷೆ ಬದಲಿಸಿ","స్వాగతం! ఎంచుకోండి:\n1. పంట సమర్పించండి\n2. నా పంటలు\n3. భాష మార్చండి","स्वागत है! चुनें:\n1. फसल जमा करें\n2. मेरी फसलें\n3. भाषा बदलें"],"manager":["Welcome! Choose:\n1. Notifications\n2. Open dashboard\n3. Change language\n4. Review harvests\n5. Manage orders\n6. Farmer memberships\n7. View inventory","ಸ್ವಾಗತ! ಆಯ್ಕೆ ಮಾಡಿ:\n1. ಸೂಚನೆಗಳು\n2. ಡ್ಯಾಶ್‌ಬೋರ್ಡ್\n3. ಭಾಷೆ ಬದಲಿಸಿ\n4. ಬೆಳೆ ಪರಿಶೀಲನೆ\n5. ಆರ್ಡರ್ ನಿರ್ವಹಣೆ\n6. ರೈತರ ಸದಸ್ಯತ್ವ\n7. ದಾಸ್ತಾನು","స్వాగతం! ఎంచుకోండి:\n1. నోటిఫికేషన్లు\n2. డ్యాష్‌బోర్డ్\n3. భాష మార్చండి\n4. పంటల సమీక్ష\n5. ఆర్డర్ల నిర్వహణ\n6. రైతు సభ్యత్వాలు\n7. నిల్వ","स्वागत है! चुनें:\n1. सूचनाएँ\n2. डैशबोर्ड\n3. भाषा बदलें\n4. फसल समीक्षा\n5. ऑर्डर प्रबंधन\n6. किसान सदस्यता\n7. स्टॉक देखें"],"hint":["\nSend 0 for menu, or LANGUAGE to change language.","\nಮೆನುಗಾಗಿ 0 ಕಳುಹಿಸಿ.","\nమెనూ కోసం 0 పంపండి.","\nमेनू के लिए 0 भेजें।"],"number":["Reply with a number from the list. 9 = next page; 0 = menu.","ಪಟ್ಟಿಯ ಸಂಖ್ಯೆಯನ್ನು ಕಳುಹಿಸಿ. 9 = ಮುಂದಿನ ಪುಟ; 0 = ಮೆನು.","జాబితా సంఖ్య పంపండి. 9 = తదుపరి పేజీ; 0 = మెనూ.","सूची का नंबर भेजें। 9 = अगला पृष्ठ; 0 = मेनू।"],"produce":["Available produce","ಲಭ್ಯ ಬೆಳೆಗಳು","అందుబాటులో ఉన్న పంటలు","उपलब्ध उपज"],"fpos":["Your approved FPOs","ನಿಮ್ಮ ಅನುಮೋದಿತ FPOಗಳು","మీ ఆమోదిత FPOలు","आपके स्वीकृत FPO"],"empty":["Nothing on this page. Send 0 to return.","ಈ ಪುಟ ಖಾಲಿಯಾಗಿದೆ. ಹಿಂತಿರುಗಲು 0.","ఈ పేజీ ఖాళీ. వెనక్కి వెళ్లేందుకు 0.","इस पृष्ठ पर कुछ नहीं है। वापस जाने के लिए 0।"],"quantity":["How many kilograms? Example: 25.5","ಎಷ್ಟು ಕಿಲೋಗ್ರಾಂ? ಉದಾ: 25.5","ఎన్ని కిలోలు? ఉదా: 25.5","कितने किलो? उदाहरण: 25.5"],"crop":["What crop did you harvest? Type its name.","ಯಾವ ಬೆಳೆ ಕೊಯ್ಲು ಮಾಡಿದ್ದೀರಿ? ಹೆಸರು ಬರೆಯಿರಿ.","ఏ పంట కోశారు? పేరు రాయండి.","कौन सी फसल काटी? नाम लिखें।"],"date":["When did you harvest?\n1. Today\n2. Yesterday\nOr type a date YYYY-MM-DD.","ಯಾವಾಗ ಕೊಯ್ಲು ಮಾಡಿದ್ದೀರಿ?\n1. ಇಂದು\n2. ನಿನ್ನೆ\nಅಥವಾ YYYY-MM-DD ದಿನಾಂಕ.","ఎప్పుడు కోశారు?\n1. ఈరోజు\n2. నిన్న\nలేదా YYYY-MM-DD తేదీ.","कटाई कब हुई?\n1. आज\n2. कल\nया YYYY-MM-DD तारीख लिखें।"],"invalid":["Please enter a valid choice or value.","ಸರಿಯಾದ ಆಯ್ಕೆ ಅಥವಾ ಮೌಲ್ಯ ನಮೂದಿಸಿ.","సరైన ఎంపిక లేదా విలువ ఇవ్వండి.","सही विकल्प या मान दर्ज करें।"],"expired":["This step expired or changed. Send 0 to start again.","ಈ ಹಂತದ ಅವಧಿ ಮುಗಿದಿದೆ ಅಥವಾ ಬದಲಾಗಿದೆ. ಮತ್ತೆ ಆರಂಭಿಸಲು 0.","ఈ దశ గడువు ముగిసింది లేదా మారింది. మళ్లీ ప్రారంభించడానికి 0.","यह चरण समाप्त हो गया या बदल गया। फिर शुरू करने के लिए 0।"],"preview":["Review your details","ವಿವರಗಳನ್ನು ಪರಿಶೀಲಿಸಿ","వివరాలను పరిశీలించండి","विवरण जाँचें"],"total":["Total","ಒಟ್ಟು","మొత్తం","कुल"],"grade":["Grade","ದರ್ಜೆ","గ్రేడ్","ग्रेड"],"demo":["Test only. No actual payment or delivery. Confirm using the button below.","ಪರೀಕ್ಷೆ ಮಾತ್ರ. ನಿಜವಾದ ಪಾವತಿ ಅಥವಾ ವಿತರಣೆ ಇಲ್ಲ. ಕೆಳಗಿನ ಬಟನ್ ಒತ್ತಿ.","పరీక్ష మాత్రమే. నిజమైన చెల్లింపు లేదా డెలివరీ లేదు. కింది బటన్ నొక్కండి.","केवल परीक्षण। वास्तविक भुगतान या डिलीवरी नहीं। नीचे बटन दबाएँ।"],"pending":["No photo attached. FPO manager approval required. Confirm using the button below.","ಫೋಟೋ ಇಲ್ಲ. FPO ವ್ಯವಸ್ಥಾಪಕರ ಅನುಮೋದನೆ ಅಗತ್ಯ. ಕೆಳಗಿನ ಬಟನ್ ಒತ್ತಿ.","ఫోటో లేదు. FPO మేనేజర్ ఆమోదం అవసరం. కింది బటన్ నొక్కండి.","फोटो नहीं है। FPO प्रबंधक की मंजूरी आवश्यक है। नीचे बटन दबाएँ।"],"confirm":["Confirm","ದೃಢೀಕರಿಸಿ","నిర్ధారించండి","पुष्टि करें"],"cancel":["Cancel","ರದ್ದು ಮಾಡಿ","రద్దు చేయండి","रद्द करें"],"cancelled":["Draft cancelled. Existing records unchanged.","ಕರಡು ರದ್ದು. ಹಿಂದಿನ ದಾಖಲೆಗಳು ಬದಲಾಗಿಲ್ಲ.","డ్రాఫ్ట్ రద్దు. పాత రికార్డులు మారలేదు.","ड्राफ्ट रद्द। पुराने रिकॉर्ड नहीं बदले।"],"tap":["Tap the Confirm or Cancel button on your latest preview. Send 0 to start again.","ಇತ್ತೀಚಿನ ಪೂರ್ವವೀಕ್ಷಣೆಯ ಬಟನ್ ಒತ್ತಿ. ಮತ್ತೆ ಆರಂಭಿಸಲು 0.","చివరి ప్రివ్యూ బటన్ నొక్కండి. మళ్లీ ప్రారంభించడానికి 0.","नवीनतम पूर्वावलोकन का बटन दबाएँ। फिर शुरू करने के लिए 0।"],"orderok":["Test order confirmed!","ಪರೀಕ್ಷಾ ಆರ್ಡರ್ ದೃಢಪಟ್ಟಿದೆ!","పరీక్ష ఆర్డర్ నిర్ధారించబడింది!","परीक्षण ऑर्डर की पुष्टि हुई!"],"harvestok":["Harvest submitted for manager review!","ಬೆಳೆ ಪರಿಶೀಲನೆಗೆ ಸಲ್ಲಿಸಲಾಗಿದೆ!","పంట మేనేజర్ సమీక్షకు పంపబడింది!","फसल समीक्षा के लिए जमा हुई!"],"changed":["Could not complete. Stock, price or membership may have changed. Send 0 to try again.","ಪೂರ್ಣಗೊಳಿಸಲಾಗಲಿಲ್ಲ. ಸ್ಟಾಕ್, ಬೆಲೆ ಅಥವಾ ಸದಸ್ಯತ್ವ ಬದಲಾಗಿರಬಹುದು. 0 ಕಳುಹಿಸಿ.","పూర్తి కాలేదు. స్టాక్, ధర లేదా సభ్యత్వం మారి ఉండవచ్చు. 0 పంపండి.","पूरा नहीं हुआ। स्टॉक, मूल्य या सदस्यता बदली हो सकती है। 0 भेजें।"],"noorder":["No WhatsApp test order yet.","ಇನ್ನೂ WhatsApp ಪರೀಕ್ಷಾ ಆರ್ಡರ್ ಇಲ್ಲ.","ఇంకా WhatsApp పరీక్ష ఆర్డర్ లేదు.","अभी कोई WhatsApp परीक्षण ऑर्डर नहीं है।"],"noharvest":["No harvests yet.","ಇನ್ನೂ ಬೆಳೆ ದಾಖಲೆಗಳಿಲ್ಲ.","ఇంకా పంటలు లేవు.","अभी कोई फसल नहीं है।"],"myharvests":["Your recent harvests","ನಿಮ್ಮ ಇತ್ತೀಚಿನ ಬೆಳೆಗಳು","మీ ఇటీవలి పంటలు","आपकी हाल की फसलें"],"alerts":["Your notifications","ನಿಮ್ಮ ಸೂಚನೆಗಳು","మీ నోటిఫికేషన్లు","आपकी सूचनाएँ"],"members":["Pending memberships","ಬಾಕಿ ಸದಸ್ಯತ್ವಗಳು","పెండింగ్ సభ్యత్వాలు","लंबित सदस्यताएँ"],"harvests":["Pending harvests","ಬಾಕಿ ಬೆಳೆಗಳು","పెండింగ్ పంటలు","लंबित फसलें"],"orders":["Open orders","ತೆರೆದ ಆರ್ಡರ್‌ಗಳು","ఓపెన్ ఆర్డర్లు","खुले ऑर्डर"],"unread":["Unread alerts","ಓದದ ಸೂಚನೆಗಳು","చదవని నోటిఫికేషన్లు","अपठित सूचनाएँ"],"readchoice":["Reply with alert number to mark it read. 0 = menu.","ಓದಿದಂತೆ ಗುರುತಿಸಲು ಸೂಚನೆ ಸಂಖ್ಯೆ ಕಳುಹಿಸಿ. 0 = ಮೆನು.","చదివినట్లు గుర్తించడానికి నోటిఫికేషన్ సంఖ్య పంపండి. 0 = మెనూ.","पढ़ा चिह्नित करने के लिए सूचना का नंबर भेजें। 0 = मेनू।"],"readok":["Marked read. Work itself is unchanged.","ಓದಿದಂತೆ ಗುರುತಿಸಲಾಗಿದೆ. ಕೆಲಸ ಬದಲಾಗಿಲ್ಲ.","చదివినట్లు గుర్తించబడింది. పని మారలేదు.","पढ़ा चिह्नित हुआ। काम नहीं बदला।"],"membership_requested":["New membership request","ಹೊಸ ಸದಸ್ಯತ್ವ ವಿನಂತಿ","కొత్త సభ్యత్వ అభ్యర్థన","नई सदस्यता का अनुरोध"],"harvest_submitted":["New harvest","ಹೊಸ ಬೆಳೆ","కొత్త పంట","नई फसल"],"order_confirmed":["New test order","ಹೊಸ ಪರೀಕ್ಷಾ ಆರ್ಡರ್","కొత్త పరీక్ష ఆర్డర్","नया परीक्षण ऑर्डर"],"order_cancelled":["Test order cancelled","ಪರೀಕ್ಷಾ ಆರ್ಡರ್ ರದ್ದು","పరీక్ష ఆర్డర్ రద్దు","परीक्षण ऑर्डर रद्द"],"confirmed":["Confirmed","ದೃಢಪಟ್ಟಿದೆ","నిర్ధారించబడింది","पुष्ट"],"packed":["Packed","ಪ್ಯಾಕ್ ಮಾಡಲಾಗಿದೆ","ప్యాక్ చేయబడింది","पैक हुआ"],"out_for_delivery":["Out for delivery","ವಿತರಣೆಗೆ ಹೊರಟಿದೆ","డెలివరీకి బయలుదేరింది","डिलीवरी के लिए निकला"],"delivered":["Delivered","ವಿತರಿಸಲಾಗಿದೆ","డెలివరీ అయింది","वितरित"],"cancelled_status":["Cancelled","ರದ್ದಾಗಿದೆ","రద్దు","रद्द"],"pending_status":["Pending review","ಪರಿಶೀಲನೆ ಬಾಕಿ","సమీక్ష పెండింగ్","समीक्षा लंबित"],"approved":["Approved","ಅನುಮೋದಿಸಲಾಗಿದೆ","ఆమోదించబడింది","स्वीकृत"],"rejected":["Rejected","ತಿರಸ್ಕರಿಸಲಾಗಿದೆ","తిరస్కరించబడింది","अस्वीकृत"],"test":["Test only","ಪರೀಕ್ಷೆ ಮಾತ್ರ","పరీక్ష మాత్రమే","केवल परीक्षण"],"review":["Pending harvests","ಬಾಕಿ ಬೆಳೆಗಳು","పెండింగ్ పంటలు","लंबित फसलें"],"manageorders":["Manage open test orders","ತೆರೆದ ಪರೀಕ್ಷಾ ಆರ್ಡರ್‌ಗಳು","ఓపెన్ పరీక్షా ఆర్డర్లు","खुले परीक्षण ऑर्डर"],"cancelorders":["Your cancellable test orders","ರದ್ದು ಮಾಡಬಹುದಾದ ಆರ್ಡರ್‌ಗಳು","రద్దు చేయగల ఆర్డర్లు","रद्द करने योग्य ऑर्डर"],"membershiplist":["Pending farmer memberships","ಬಾಕಿ ರೈತ ಸದಸ್ಯತ್ವಗಳು","పెండింగ్ రైతు సభ్యత్వాలు","लंबित किसान सदस्यताएँ"],"inventory":["Available inventory","ಲಭ್ಯ ದಾಸ್ತಾನು","అందుబాటు నిల్వ","उपलब्ध स्टॉक"],"approve_choice":["1. Approve\n2. Reject","1. ಅನುಮೋದಿಸಿ\n2. ತಿರಸ್ಕರಿಸಿ","1. ఆమోదించండి\n2. తిరస్కరించండి","1. स्वीकार करें\n2. अस्वीकार करें"],"grade_choice":["Select quality grade:\n1. A\n2. B\n3. C","ಗುಣಮಟ್ಟ ಆಯ್ಕೆ:\n1. A\n2. B\n3. C","నాణ్యత ఎంచుకోండి:\n1. A\n2. B\n3. C","गुणवत्ता चुनें:\n1. A\n2. B\n3. C"],"price_choice":["Enter selling price in rupees per kg (e.g. 30.50).","ಪ್ರತಿ ಕೆಜಿಗೆ ರೂಪಾಯಿಯಲ್ಲಿ ಬೆಲೆ ನಮೂದಿಸಿ (ಉದಾ. 30.50).","కిలోకు రూపాయల్లో ధర ఇవ్వండి (ఉదా. 30.50).","प्रति किलो रुपये में कीमत लिखें (जैसे 30.50)।"],"reason_choice":["Enter rejection reason (1–300 characters).","ತಿರಸ್ಕಾರದ ಕಾರಣ ನಮೂದಿಸಿ (1–300 ಅಕ್ಷರ).","తిరస్కరణ కారణం ఇవ్వండి (1–300 అక్షరాలు).","अस्वीकृति का कारण लिखें (1–300 अक्षर)।"],"photo_note":["Photo attached. View it on the website before approving if needed.","ಫೋಟೋ ಇದೆ. ಅಗತ್ಯವಿದ್ದರೆ ಅನುಮೋದನೆ ಮೊದಲು ವೆಬ್‌ಸೈಟ್‌ನಲ್ಲಿ ನೋಡಿ.","ఫోటో ఉంది. అవసరమైతే ఆమోదానికి ముందు వెబ్‌సైట్‌లో చూడండి.","फोटो संलग्न है। जरूरत हो तो मंजूरी से पहले वेबसाइट पर देखें।"],"approve_action":["Approve","ಅನುಮೋದಿಸಿ","ఆమోదించండి","स्वीकार करें"],"reject_action":["Reject","ತಿರಸ್ಕರಿಸಿ","తిరస్కరించండి","अस्वीकार करें"],"pack_action":["Mark packed","ಪ್ಯಾಕ್ ಮಾಡಿ","ప్యాక్ చేయండి","पैक करें"],"dispatch_action":["Dispatch","ವಿತರಣೆಗೆ ಕಳುಹಿಸಿ","డెలివరీకి పంపండి","भेजें"],"deliver_action":["Mark delivered","ವಿತರಿಸಲಾಗಿದೆ","డెలివరీ పూర్తయింది","वितरित करें"],"cancel_action":["Cancel order (simulated refund)","ಆರ್ಡರ್ ರದ್ದು (ಪರೀಕ್ಷಾ ಮರುಪಾವತಿ)","ఆర్డర్ రద్దు (పరీక్ష రీఫండ్)","ऑर्डर रद्द (नकली रिफंड)"],"done_action":["Action completed. Website updated.","ಕಾರ್ಯ ಪೂರ್ಣ. ವೆಬ್‌ಸೈಟ್ ನವೀಕರಿಸಲಾಗಿದೆ.","చర్య పూర్తయింది. వెబ్‌సైట్ నవీకరించబడింది.","कार्रवाई पूरी। वेबसाइट अपडेट हुई।"],"confirm_action":["Confirm this exact action below. Test environment only.","ಈ ಕಾರ್ಯವನ್ನು ಕೆಳಗೆ ದೃಢೀಕರಿಸಿ. ಪರೀಕ್ಷೆ ಮಾತ್ರ.","ఈ చర్యను కింద నిర్ధారించండి. పరీక్ష మాత్రమే.","नीचे इस कार्रवाई की पुष्टि करें। केवल परीक्षण।"],"page_hint":["9 = next page; 0 = menu.","9 = ಮುಂದಿನ ಪುಟ; 0 = ಮೆನು.","9 = తదుపరి పేజీ; 0 = మెనూ.","9 = अगला पृष्ठ; 0 = मेनू।"],"reserved":["Reserved","ಕಾಯ್ದಿರಿಸಿದ","రిజర్వ్","आरक्षित"],"action":["Action","ಕಾರ್ಯ","చర్య","कार्रवाई"]}$dict$::jsonb->k)->>case l when 'kn' then 1 when 'te' then 2 when 'hi' then 3 else 0 end,k)
$$;
-- Keep the tested farmer/customer/notification guide, with expanded role menus.
alter function private.wa_guide(text,text,boolean) rename to wa_guide_base;
revoke all on function private.wa_guide_base(text,text,boolean) from public,anon,authenticated,service_role;
create function private.wa_guide(p_phone text,p_text text,p_button boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; r text; g private.wa_guides%rowtype; v text:=trim(p_text); cmd text; l text; kind text; n integer; pg integer; rows jsonb; item jsonb; body text; listing text; action text; token uuid; f uuid; subject uuid; expected text; actual text; price integer; ok boolean; title_key text;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or v is null or length(v) not between 1 and 512 then return jsonb_build_object('body','Send HI to start.');end if;
 v:=translate(v,'೦೧೨೩೪೫೬೭೮೯౦౧౨౩౪౫౬౭౮౯०१२३४५६७८९','012345678901234567890123456789');cmd:=lower(v);
 select user_id into u from private.wa_links where phone=p_phone;
 if not found then return private.wa_guide_base(p_phone,p_text,p_button);end if;
 select account_role into r from public.profiles where id=u for no key update;
 if not found or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone) then return jsonb_build_object('body','Link your account first.');end if;
 select * into g from private.wa_guides where user_id=u;
 if g.lang is null or r not in ('manager','customer') then return private.wa_guide_base(p_phone,p_text,p_button);end if;
 l:=g.lang;
 if not p_button and cmd in ('0','hi','hello','help','menu','ನಮಸ್ಕಾರ','నమస్కారం','नमस्ते','language','3 languages') then return private.wa_guide_base(p_phone,p_text,false);end if;
 if g.step not like 'ops_%' and not (not p_button and g.step='menu' and ((r='manager' and cmd in ('4','5','6','7')) or (r='customer' and cmd='4'))) then return private.wa_guide_base(p_phone,p_text,p_button);end if;
 if g.expires_at<=clock_timestamp() then
  update private.wa_guides set step='menu',snapshot='[]',target=null,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'expired')||E'\n\n'||private.wa_phrase(l,r));
 end if;
 if p_button then
  if g.step<>'ops_confirm' or cmd !~ '^ac_(confirm|cancel):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  token:=split_part(cmd,':',2)::uuid;
  if token is distinct from g.target then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  item:=g.snapshot;kind:=item->>'kind';action:=item->>'action';f:=(item->>'fpo')::uuid;subject:=(item->>'id')::uuid;
  if cmd like 'ac_cancel:%' then body:=private.wa_phrase(l,'cancelled');
  else
   begin
    if r='manager' and not private.manager_actor(u,f) then raise exception 'Manager required';end if;
    if kind='harvest' and r='manager' and action in ('approve_action','reject_action') then
     if not exists(select 1 from public.harvests where id=subject and fpo_id=f) then raise exception 'Harvest unavailable';end if;
     perform private.review_harvest_for(u,subject,item->>'grade',(item->>'price')::integer,action='approve_action',item->>'reason');
    elsif kind='member' and r='manager' and action in ('approve_action','reject_action') then
     perform private.review_member_for(u,f,subject,action='approve_action');
    elsif kind in ('order','customer_order') and ((kind='order' and r='manager') or (kind='customer_order' and r='customer' and action='cancel_action')) then
     select status into actual from public.orders where id=subject and fpo_id=f and (r='manager' or customer_id=u) for update;
     if not found or actual is distinct from item->>'status' then raise exception 'Order changed';end if;
     expected:=case action when 'pack_action' then 'packed' when 'dispatch_action' then 'out_for_delivery' when 'deliver_action' then 'delivered' when 'cancel_action' then 'cancelled' else null end;
     perform private.transition_order_for(u,subject,expected);
    else raise exception 'Invalid action';end if;
    body:=private.wa_phrase(l,'done_action');
   exception when raise_exception then body:=private.wa_phrase(l,'changed');end;
  end if;
  update private.wa_guides set step='menu',snapshot='[]',target=null,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',body||E'\n\n'||private.wa_phrase(l,r));
 end if;
 if g.step='menu' or (g.step like 'ops_list_%' and cmd='9') then
  pg:=case when g.step='menu' then 1 else least(g.page_no+1,999) end;
  kind:=case when g.step<>'menu' then substring(g.step from 10) when r='customer' then 'customer_order' when cmd='4' then 'harvest' when cmd='5' then 'order' when cmd='6' then 'member' else 'inventory' end;
  if (kind='customer_order' and r<>'customer') or (kind<>'customer_order' and r<>'manager') then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  if kind='harvest' then
   select coalesce(jsonb_agg(to_jsonb(z) order by z.id),'[]') into rows from (select h.id,h.fpo_id as fpo,'harvest' as kind,h.photo_path is not null as photo, left(regexp_replace(h.crop,'[[:cntrl:]]',' ','g'),100)||' | '||h.quantity_kg||' kg | '||h.harvest_date||' | '||left(regexp_replace(p.display_name,'[[:cntrl:]]',' ','g'),100)||' | '||left(regexp_replace(f.name,'[[:cntrl:]]',' ','g'),120) as label from public.harvests h join public.profiles p on p.id=h.farmer_id join public.fpos f on f.id=h.fpo_id join public.memberships m on m.fpo_id=h.fpo_id and m.user_id=u and m.role='manager' and m.status='active' where h.status='pending' order by h.id limit 5 offset ((pg-1)*5)) z;
   title_key:='review';
  elsif kind in ('order','customer_order') then
   select coalesce(jsonb_agg(to_jsonb(z) order by z.id),'[]') into rows from (select o.id,o.fpo_id as fpo,kind as kind,o.status, left(regexp_replace(f.name,'[[:cntrl:]]',' ','g'),120)||' | '||coalesce((select string_agg(left(regexp_replace(x->>'crop','[[:cntrl:]]',' ','g'),60)||' '||(x->>'quantity_kg')||' kg',', ' order by ord) from jsonb_array_elements(o.items) with ordinality e(x,ord) where ord<=3),'')||case when jsonb_array_length(o.items)>3 then ' + …' else '' end||' | ₹'||round(o.total_paise::numeric/100,2)||' | '||private.wa_phrase(l,o.status)||' | #'||right(o.id::text,8)||' | '||to_char(o.created_at at time zone 'Asia/Kolkata','DD Mon HH24:MI') as label from public.orders o join public.fpos f on f.id=o.fpo_id where ((r='manager' and o.status in ('confirmed','packed','out_for_delivery') and exists(select 1 from public.memberships m where m.fpo_id=o.fpo_id and m.user_id=u and m.role='manager' and m.status='active')) or (r='customer' and o.customer_id=u and o.status='confirmed')) order by o.id limit 5 offset ((pg-1)*5)) z;
   title_key:=case when r='customer' then 'cancelorders' else 'manageorders' end;
  elsif kind='member' then
   select coalesce(jsonb_agg(to_jsonb(z) order by z.fpo,z.id),'[]') into rows from (select m.user_id as id,m.fpo_id as fpo,'member' as kind,left(regexp_replace(p.display_name,'[[:cntrl:]]',' ','g'),100)||' | '||left(regexp_replace(f.name,'[[:cntrl:]]',' ','g'),120) as label from public.memberships m join public.profiles p on p.id=m.user_id join public.fpos f on f.id=m.fpo_id where m.role='farmer' and m.status='pending' and exists(select 1 from public.memberships a where a.fpo_id=m.fpo_id and a.user_id=u and a.role='manager' and a.status='active') order by m.fpo_id,m.user_id limit 5 offset ((pg-1)*5)) z;title_key:='membershiplist';
  elsif kind='inventory' then
   select coalesce(jsonb_agg(to_jsonb(z) order by z.id),'[]') into rows from (select a.id,a.fpo_id as fpo,'inventory' as kind,left(regexp_replace(a.crop,'[[:cntrl:]]',' ','g'),100)||' | '||a.grade||' | '||a.available_kg||' kg | '||private.wa_phrase(l,'reserved')||': '||a.reserved_kg||' kg | ₹'||round(a.price_paise_per_kg::numeric/100,2)||'/kg | '||left(regexp_replace(f.name,'[[:cntrl:]]',' ','g'),120) as label from public.inventory_lots a join public.fpos f on f.id=a.fpo_id where exists(select 1 from public.memberships m where m.fpo_id=a.fpo_id and m.user_id=u and m.role='manager' and m.status='active') order by a.id limit 5 offset ((pg-1)*5)) z;title_key:='inventory';
  else return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  select string_agg(ord::text||'. '||(x->>'label'),E'\n' order by ord) into listing from jsonb_array_elements(rows) with ordinality e(x,ord);
  update private.wa_guides set step='ops_list_'||kind,snapshot=rows,page_no=pg,target=null,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,title_key)||E'\n'||coalesce(listing,private.wa_phrase(l,'empty'))||E'\n\n'||private.wa_phrase(l,case when kind='inventory' then 'page_hint' else 'number' end));
 elsif g.step like 'ops_list_%' and cmd ~ '^[1-5]$' then
  kind:=substring(g.step from 10);n:=cmd::integer;
  if kind='inventory' or n>jsonb_array_length(g.snapshot) then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  item:=g.snapshot->(n-1);f:=(item->>'fpo')::uuid;subject:=(item->>'id')::uuid;
  if r='manager' and not private.manager_actor(u,f) then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  if kind='customer_order' then action:='cancel_action';
  elsif kind in ('harvest','member') then
   update private.wa_guides set step='ops_decision',snapshot=item,target=null where user_id=u;
   return jsonb_build_object('body',(item->>'label')||E'\n'||case when item->>'photo'='true' then private.wa_phrase(l,'photo_note')||E'\n' else '' end||private.wa_phrase(l,'approve_choice')||private.wa_phrase(l,'hint'));
  else
   action:=case item->>'status' when 'confirmed' then 'pack_action' when 'packed' then 'dispatch_action' else 'deliver_action' end;
   item:=item||jsonb_build_object('action',action);
   update private.wa_guides set step='ops_decision',snapshot=item,target=null where user_id=u;
   return jsonb_build_object('body',(item->>'label')||E'\n1. '||private.wa_phrase(l,action)||case when item->>'status' in ('confirmed','packed') then E'\n2. '||private.wa_phrase(l,'cancel_action') else '' end||private.wa_phrase(l,'hint'));
  end if;
 elsif g.step='ops_decision' and cmd in ('1','2') and r='manager' then
  item:=g.snapshot;kind:=item->>'kind';
  if kind='harvest' and cmd='1' then
   update private.wa_guides set step='ops_grade',snapshot=item||jsonb_build_object('action','approve_action') where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,'grade_choice'));
  elsif kind='harvest' and cmd='2' then
   update private.wa_guides set step='ops_reason',snapshot=item||jsonb_build_object('action','reject_action') where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,'reason_choice'));
  elsif kind='member' then action:=case cmd when '1' then 'approve_action' else 'reject_action' end;
  elsif kind='order' and (cmd='1' or item->>'status' in ('confirmed','packed')) then action:=case when cmd='1' then item->>'action' else 'cancel_action' end;
  else return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
 elsif g.step='ops_grade' and r='manager' and cmd in ('1','2','3','a','b','c') then
  item:=g.snapshot||jsonb_build_object('grade',case cmd when '1' then 'A' when '2' then 'B' when '3' then 'C' else upper(cmd) end);
  update private.wa_guides set step='ops_price',snapshot=item where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'price_choice'));
 elsif g.step='ops_price' and r='manager' then
  if v !~ '^[0-9]{1,8}([.][0-9]{1,2})?$' then return jsonb_build_object('body',private.wa_phrase(l,'price_choice'));end if;
  if v::numeric<0.01 or v::numeric>21474836.47 then return jsonb_build_object('body',private.wa_phrase(l,'price_choice'));end if;
  price:=(v::numeric*100)::integer;item:=g.snapshot||jsonb_build_object('price',price);action:='approve_action';
 elsif g.step='ops_reason' and r='manager' then
  if length(v)>300 or v ~ '[[:cntrl:]]' then return jsonb_build_object('body',private.wa_phrase(l,'reason_choice'));end if;
  item:=g.snapshot||jsonb_build_object('reason',v);action:='reject_action';
 elsif g.step='ops_confirm' then return jsonb_build_object('body',private.wa_phrase(l,'tap'));
 else return jsonb_build_object('body',private.wa_phrase(l,'invalid')||private.wa_phrase(l,'hint'));end if;
 token:=gen_random_uuid();item:=item||jsonb_build_object('action',action);
 body:=private.wa_phrase(l,'preview')||E'\n'||(item->>'label')||E'\n'||private.wa_phrase(l,'action')||': '||private.wa_phrase(l,action)||case when item ? 'grade' then E'\n'||private.wa_phrase(l,'grade')||': '||(item->>'grade')||' | ₹'||round((item->>'price')::numeric/100,2)||'/kg' else '' end||case when item ? 'reason' then E'\n'||(item->>'reason') else '' end||E'\n'||private.wa_phrase(l,'confirm_action');
 update private.wa_guides set step='ops_confirm',snapshot=item,target=token,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
 return jsonb_build_object('body',body,'buttons',jsonb_build_array(jsonb_build_object('id','ac_confirm:'||token,'title',private.wa_phrase(l,'confirm')),jsonb_build_object('id','ac_cancel:'||token,'title',private.wa_phrase(l,'cancel'))));
end $$;
create or replace function public.wa_guide(p_phone text,p_text text,p_button boolean) returns jsonb language sql security invoker set search_path='' as $$select private.wa_guide(p_phone,p_text,p_button)$$;
revoke all on function private.wa_guide(text,text,boolean),public.wa_guide(text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function private.wa_guide(text,text,boolean),public.wa_guide(text,text,boolean) to service_role;
commit;