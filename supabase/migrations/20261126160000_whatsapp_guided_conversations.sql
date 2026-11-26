begin;
create table private.wa_guides(
 user_id uuid primary key references private.wa_links(user_id) on delete cascade,
 lang text check(lang in ('en','kn','te','hi')), step text not null default 'language',
 page_no integer not null default 1, choice integer, crop text, qty text, target uuid,
 snapshot jsonb not null default '[]', expires_at timestamptz not null default (clock_timestamp()+interval '10 minutes')
);
alter table private.wa_guides enable row level security;
revoke all on private.wa_guides from public,anon,authenticated,service_role;
create function private.wa_phrase(l text,k text) returns text language sql immutable set search_path='' as $$
 select coalesce(($dict${"choose":["Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी","Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी","Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी","Choose your language:\n1. English\n2. ಕನ್ನಡ\n3. తెలుగు\n4. हिन्दी"],"link":["First link your account in Profile: ","ಮೊದಲು ಪ್ರೊಫೈಲ್‌ನಲ್ಲಿ ಖಾತೆಯನ್ನು ಲಿಂಕ್ ಮಾಡಿ: ","ముందుగా ప్రొఫైల్‌లో ఖాతాను లింక్ చేయండి: ","पहले प्रोफ़ाइल में खाता लिंक करें: "],"customer":["Welcome! Choose:\n1. Buy produce\n2. Track latest order\n3. Change language","ಸ್ವಾಗತ! ಆಯ್ಕೆ ಮಾಡಿ:\n1. ಬೆಳೆ ಖರೀದಿ\n2. ಕೊನೆಯ ಆರ್ಡರ್ ಸ್ಥಿತಿ\n3. ಭಾಷೆ ಬದಲಿಸಿ","స్వాగతం! ఎంచుకోండి:\n1. పంట కొనండి\n2. చివరి ఆర్డర్ స్థితి\n3. భాష మార్చండి","स्वागत है! चुनें:\n1. उपज खरीदें\n2. अंतिम ऑर्डर की स्थिति\n3. भाषा बदलें"],"farmer":["Welcome! Choose:\n1. Submit harvest\n2. My harvests\n3. Change language","ಸ್ವಾಗತ! ಆಯ್ಕೆ ಮಾಡಿ:\n1. ಬೆಳೆ ಸಲ್ಲಿಸಿ\n2. ನನ್ನ ಬೆಳೆಗಳು\n3. ಭಾಷೆ ಬದಲಿಸಿ","స్వాగతం! ఎంచుకోండి:\n1. పంట సమర్పించండి\n2. నా పంటలు\n3. భాష మార్చండి","स्वागत है! चुनें:\n1. फसल जमा करें\n2. मेरी फसलें\n3. भाषा बदलें"],"manager":["Welcome! Choose:\n1. Notifications\n2. Open dashboard\n3. Change language","ಸ್ವಾಗತ! ಆಯ್ಕೆ ಮಾಡಿ:\n1. ಸೂಚನೆಗಳು\n2. ಡ್ಯಾಶ್‌ಬೋರ್ಡ್ ತೆರೆಯಿರಿ\n3. ಭಾಷೆ ಬದಲಿಸಿ","స్వాగతం! ఎంచుకోండి:\n1. నోటిఫికేషన్లు\n2. డ్యాష్‌బోర్డ్ తెరవండి\n3. భాష మార్చండి","स्वागत है! चुनें:\n1. सूचनाएँ\n2. डैशबोर्ड खोलें\n3. भाषा बदलें"],"hint":["\nSend 0 for menu, or LANGUAGE to change language.","\nಮೆನುಗಾಗಿ 0 ಕಳುಹಿಸಿ.","\nమెనూ కోసం 0 పంపండి.","\nमेनू के लिए 0 भेजें।"],"number":["Reply with a number from the list. 9 = next page; 0 = menu.","ಪಟ್ಟಿಯ ಸಂಖ್ಯೆಯನ್ನು ಕಳುಹಿಸಿ. 9 = ಮುಂದಿನ ಪುಟ; 0 = ಮೆನು.","జాబితా సంఖ్య పంపండి. 9 = తదుపరి పేజీ; 0 = మెనూ.","सूची का नंबर भेजें। 9 = अगला पृष्ठ; 0 = मेनू।"],"produce":["Available produce","ಲಭ್ಯ ಬೆಳೆಗಳು","అందుబాటులో ఉన్న పంటలు","उपलब्ध उपज"],"fpos":["Your approved FPOs","ನಿಮ್ಮ ಅನುಮೋದಿತ FPOಗಳು","మీ ఆమోదిత FPOలు","आपके स्वीकृत FPO"],"empty":["Nothing on this page. Send 0 to return.","ಈ ಪುಟ ಖಾಲಿಯಾಗಿದೆ. ಹಿಂತಿರುಗಲು 0.","ఈ పేజీ ఖాళీ. వెనక్కి వెళ్లేందుకు 0.","इस पृष्ठ पर कुछ नहीं है। वापस जाने के लिए 0।"],"quantity":["How many kilograms? Example: 25.5","ಎಷ್ಟು ಕಿಲೋಗ್ರಾಂ? ಉದಾ: 25.5","ఎన్ని కిలోలు? ఉదా: 25.5","कितने किलो? उदाहरण: 25.5"],"crop":["What crop did you harvest? Type its name.","ಯಾವ ಬೆಳೆ ಕೊಯ್ಲು ಮಾಡಿದ್ದೀರಿ? ಹೆಸರು ಬರೆಯಿರಿ.","ఏ పంట కోశారు? పేరు రాయండి.","कौन सी फसल काटी? नाम लिखें।"],"date":["When did you harvest?\n1. Today\n2. Yesterday\nOr type a date YYYY-MM-DD.","ಯಾವಾಗ ಕೊಯ್ಲು ಮಾಡಿದ್ದೀರಿ?\n1. ಇಂದು\n2. ನಿನ್ನೆ\nಅಥವಾ YYYY-MM-DD ದಿನಾಂಕ.","ఎప్పుడు కోశారు?\n1. ఈరోజు\n2. నిన్న\nలేదా YYYY-MM-DD తేదీ.","कटाई कब हुई?\n1. आज\n2. कल\nया YYYY-MM-DD तारीख लिखें।"],"invalid":["Please enter a valid choice or value.","ಸರಿಯಾದ ಆಯ್ಕೆ ಅಥವಾ ಮೌಲ್ಯ ನಮೂದಿಸಿ.","సరైన ఎంపిక లేదా విలువ ఇవ్వండి.","सही विकल्प या मान दर्ज करें।"],"expired":["This step expired or changed. Send 0 to start again.","ಈ ಹಂತದ ಅವಧಿ ಮುಗಿದಿದೆ ಅಥವಾ ಬದಲಾಗಿದೆ. ಮತ್ತೆ ಆರಂಭಿಸಲು 0.","ఈ దశ గడువు ముగిసింది లేదా మారింది. మళ్లీ ప్రారంభించడానికి 0.","यह चरण समाप्त हो गया या बदल गया। फिर शुरू करने के लिए 0।"],"preview":["Review your details","ವಿವರಗಳನ್ನು ಪರಿಶೀಲಿಸಿ","వివరాలను పరిశీలించండి","विवरण जाँचें"],"total":["Total","ಒಟ್ಟು","మొత్తం","कुल"],"grade":["Grade","ದರ್ಜೆ","గ్రేడ్","ग्रेड"],"demo":["Test only. No actual payment or delivery. Confirm using the button below.","ಪರೀಕ್ಷೆ ಮಾತ್ರ. ನಿಜವಾದ ಪಾವತಿ ಅಥವಾ ವಿತರಣೆ ಇಲ್ಲ. ಕೆಳಗಿನ ಬಟನ್ ಒತ್ತಿ.","పరీక్ష మాత్రమే. నిజమైన చెల్లింపు లేదా డెలివరీ లేదు. కింది బటన్ నొక్కండి.","केवल परीक्षण। वास्तविक भुगतान या डिलीवरी नहीं। नीचे बटन दबाएँ।"],"pending":["No photo attached. FPO manager approval required. Confirm using the button below.","ಫೋಟೋ ಇಲ್ಲ. FPO ವ್ಯವಸ್ಥಾಪಕರ ಅನುಮೋದನೆ ಅಗತ್ಯ. ಕೆಳಗಿನ ಬಟನ್ ಒತ್ತಿ.","ఫోటో లేదు. FPO మేనేజర్ ఆమోదం అవసరం. కింది బటన్ నొక్కండి.","फोटो नहीं है। FPO प्रबंधक की मंजूरी आवश्यक है। नीचे बटन दबाएँ।"],"confirm":["Confirm","ದೃಢೀಕರಿಸಿ","నిర్ధారించండి","पुष्टि करें"],"cancel":["Cancel","ರದ್ದು ಮಾಡಿ","రద్దు చేయండి","रद्द करें"],"cancelled":["Draft cancelled. Existing records unchanged.","ಕರಡು ರದ್ದು. ಹಿಂದಿನ ದಾಖಲೆಗಳು ಬದಲಾಗಿಲ್ಲ.","డ్రాఫ్ట్ రద్దు. పాత రికార్డులు మారలేదు.","ड्राफ्ट रद्द। पुराने रिकॉर्ड नहीं बदले।"],"tap":["Tap the Confirm or Cancel button on your latest preview. Send 0 to start again.","ಇತ್ತೀಚಿನ ಪೂರ್ವವೀಕ್ಷಣೆಯ ಬಟನ್ ಒತ್ತಿ. ಮತ್ತೆ ಆರಂಭಿಸಲು 0.","చివరి ప్రివ్యూ బటన్ నొక్కండి. మళ్లీ ప్రారంభించడానికి 0.","नवीनतम पूर्वावलोकन का बटन दबाएँ। फिर शुरू करने के लिए 0।"],"orderok":["Test order confirmed!","ಪರೀಕ್ಷಾ ಆರ್ಡರ್ ದೃಢಪಟ್ಟಿದೆ!","పరీక్ష ఆర్డర్ నిర్ధారించబడింది!","परीक्षण ऑर्डर की पुष्टि हुई!"],"harvestok":["Harvest submitted for manager review!","ಬೆಳೆ ಪರಿಶೀಲನೆಗೆ ಸಲ್ಲಿಸಲಾಗಿದೆ!","పంట మేనేజర్ సమీక్షకు పంపబడింది!","फसल समीक्षा के लिए जमा हुई!"],"changed":["Could not complete. Stock, price or membership may have changed. Send 0 to try again.","ಪೂರ್ಣಗೊಳಿಸಲಾಗಲಿಲ್ಲ. ಸ್ಟಾಕ್, ಬೆಲೆ ಅಥವಾ ಸದಸ್ಯತ್ವ ಬದಲಾಗಿರಬಹುದು. 0 ಕಳುಹಿಸಿ.","పూర్తి కాలేదు. స్టాక్, ధర లేదా సభ్యత్వం మారి ఉండవచ్చు. 0 పంపండి.","पूरा नहीं हुआ। स्टॉक, मूल्य या सदस्यता बदली हो सकती है। 0 भेजें।"],"noorder":["No WhatsApp test order yet.","ಇನ್ನೂ WhatsApp ಪರೀಕ್ಷಾ ಆರ್ಡರ್ ಇಲ್ಲ.","ఇంకా WhatsApp పరీక్ష ఆర్డర్ లేదు.","अभी कोई WhatsApp परीक्षण ऑर्डर नहीं है।"],"noharvest":["No harvests yet.","ಇನ್ನೂ ಬೆಳೆ ದಾಖಲೆಗಳಿಲ್ಲ.","ఇంకా పంటలు లేవు.","अभी कोई फसल नहीं है।"],"myharvests":["Your recent harvests","ನಿಮ್ಮ ಇತ್ತೀಚಿನ ಬೆಳೆಗಳು","మీ ఇటీవలి పంటలు","आपकी हाल की फसलें"],"alerts":["Your notifications","ನಿಮ್ಮ ಸೂಚನೆಗಳು","మీ నోటిఫికేషన్లు","आपकी सूचनाएँ"],"members":["Pending memberships","ಬಾಕಿ ಸದಸ್ಯತ್ವಗಳು","పెండింగ్ సభ్యత్వాలు","लंबित सदस्यताएँ"],"harvests":["Pending harvests","ಬಾಕಿ ಬೆಳೆಗಳು","పెండింగ్ పంటలు","लंबित फसलें"],"orders":["Open orders","ತೆರೆದ ಆರ್ಡರ್‌ಗಳು","ఓపెన్ ఆర్డర్లు","खुले ऑर्डर"],"unread":["Unread alerts","ಓದದ ಸೂಚನೆಗಳು","చదవని నోటిఫికేషన్లు","अपठित सूचनाएँ"],"readchoice":["Reply with alert number to mark it read. 0 = menu.","ಓದಿದಂತೆ ಗುರುತಿಸಲು ಸೂಚನೆ ಸಂಖ್ಯೆ ಕಳುಹಿಸಿ. 0 = ಮೆನು.","చదివినట్లు గుర్తించడానికి నోటిఫికేషన్ సంఖ్య పంపండి. 0 = మెనూ.","पढ़ा चिह्नित करने के लिए सूचना का नंबर भेजें। 0 = मेनू।"],"readok":["Marked read. Work itself is unchanged.","ಓದಿದಂತೆ ಗುರುತಿಸಲಾಗಿದೆ. ಕೆಲಸ ಬದಲಾಗಿಲ್ಲ.","చదివినట్లు గుర్తించబడింది. పని మారలేదు.","पढ़ा चिह्नित हुआ। काम नहीं बदला।"],"membership_requested":["New membership request","ಹೊಸ ಸದಸ್ಯತ್ವ ವಿನಂತಿ","కొత్త సభ్యత్వ అభ్యర్థన","नई सदस्यता का अनुरोध"],"harvest_submitted":["New harvest","ಹೊಸ ಬೆಳೆ","కొత్త పంట","नई फसल"],"order_confirmed":["New test order","ಹೊಸ ಪರೀಕ್ಷಾ ಆರ್ಡರ್","కొత్త పరీక్ష ఆర్డర్","नया परीक्षण ऑर्डर"],"order_cancelled":["Test order cancelled","ಪರೀಕ್ಷಾ ಆರ್ಡರ್ ರದ್ದು","పరీక్ష ఆర్డర్ రద్దు","परीक्षण ऑर्डर रद्द"],"confirmed":["Confirmed","ದೃಢಪಟ್ಟಿದೆ","నిర్ధారించబడింది","पुष्ट"],"packed":["Packed","ಪ್ಯಾಕ್ ಮಾಡಲಾಗಿದೆ","ప్యాక్ చేయబడింది","पैक हुआ"],"out_for_delivery":["Out for delivery","ವಿತರಣೆಗೆ ಹೊರಟಿದೆ","డెలివరీకి బయలుదేరింది","डिलीवरी के लिए निकला"],"delivered":["Delivered","ವಿತರಿಸಲಾಗಿದೆ","డెలివరీ అయింది","वितरित"],"cancelled_status":["Cancelled","ರದ್ದಾಗಿದೆ","రద్దు","रद्द"],"pending_status":["Pending review","ಪರಿಶೀಲನೆ ಬಾಕಿ","సమీక్ష పెండింగ్","समीक्षा लंबित"],"approved":["Approved","ಅನುಮೋದಿಸಲಾಗಿದೆ","ఆమోదించబడింది","स्वीकृत"],"rejected":["Rejected","ತಿರಸ್ಕರಿಸಲಾಗಿದೆ","తిరస్కరించబడింది","अस्वीकृत"],"test":["Test only","ಪರೀಕ್ಷೆ ಮಾತ್ರ","పరీక్ష మాత్రమే","केवल परीक्षण"]}$dict$::jsonb->k)->>case l when 'kn' then 1 when 'te' then 2 when 'hi' then 3 else 0 end,k)
$$;
create function private.wa_guide(p_phone text,p_text text,p_button boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; r text; g private.wa_guides%rowtype; v text:=trim(p_text); cmd text; l text; body text; list_body text; n integer; today date:=(now() at time zone 'Asia/Kolkata')::date; hd date; s private.wa_shop%rowtype; f private.wa_harvest_drafts%rowtype; p jsonb; a jsonb; o public.orders%rowtype; result_text text; ok boolean; action_id uuid; menu_key text; preview_id uuid; buttons jsonb; x jsonb;
begin
 if p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$' or v is null or length(v) not between 1 and 512 then return jsonb_build_object('body','Send HI to start.');end if;
 v:=translate(v,'೦೧೨೩೪೫೬೭೮೯౦౧౨౩౪౫౬౭౮౯०१२३४५६७८९','012345678901234567890123456789');cmd:=lower(v);
 select user_id into u from private.wa_links where phone=p_phone;
 if not found then return jsonb_build_object('body','First link your account in Profile: https://agriconnect-q7c2.onrender.com/');end if;
 select account_role into r from public.profiles where id=u for no key update;
 if not found or r not in ('farmer','manager','customer') or not exists(select 1 from private.wa_links where user_id=u and phone=p_phone) then return jsonb_build_object('body','Link your account first.');end if;
 insert into private.wa_guides(user_id) values(u) on conflict do nothing;
 select * into g from private.wa_guides where user_id=u;
 l:=coalesce(g.lang,'en');menu_key:=r;
 -- Only actual signed interactive reply IDs can confirm. A stale button never acts on a new draft.
 if p_button then
  if cmd !~ '^ac_(confirm|cancel):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  action_id:=split_part(cmd,':',2)::uuid;
  if g.step not in ('order_confirm','harvest_confirm') or g.target is distinct from action_id or g.expires_at<=clock_timestamp() then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  if cmd like 'ac_cancel:%' then
   if r='customer' then perform private.wa_order_command(p_phone,'reset');elsif r='farmer' then perform private.wa_harvest_command(p_phone,'harvestreset');end if;
   body:=private.wa_phrase(l,'cancelled');
  elsif r='customer' and g.step='order_confirm' then
   result_text:=private.wa_order_command(p_phone,'confirm '||action_id::text);
   body:=case when result_text like 'Test order confirmed!%' or result_text like 'Order already placed%' then private.wa_phrase(l,'orderok') else private.wa_phrase(l,'changed') end;
  elsif r='farmer' and g.step='harvest_confirm' then
   result_text:=private.wa_harvest_command(p_phone,'submit '||action_id::text);
   body:=case when result_text like 'Harvest submitted!%' or result_text like 'Harvest already submitted%' then private.wa_phrase(l,'harvestok') else private.wa_phrase(l,'changed') end;
  else return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  update private.wa_guides set step='menu',target=null,choice=null,crop=null,qty=null,snapshot='[]',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',body||E'\n\n'||private.wa_phrase(l,menu_key));
 end if;
 if cmd in ('language','3 languages') or g.lang is null then
  if g.step='language' and cmd in ('1','2','3','4','english','ಕನ್ನಡ','తెలుగు','हिन्दी','हिंदी') then
   l:=case when cmd in ('1','english') then 'en' when cmd in ('2','ಕನ್ನಡ') then 'kn' when cmd in ('3','తెలుగు') then 'te' else 'hi' end;
   update private.wa_guides set lang=l,step='menu',target=null,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,menu_key));
  end if;
  update private.wa_guides set step='language',target=null,expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'choose'));
 end if;
 if g.step='language' then
  if cmd in ('1','2','3','4','english','ಕನ್ನಡ','తెలుగు','हिन्दी','हिंदी') then
   l:=case when cmd in ('1','english') then 'en' when cmd in ('2','ಕನ್ನಡ') then 'kn' when cmd in ('3','తెలుగు') then 'te' else 'hi' end;
   update private.wa_guides set lang=l,step='menu',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,menu_key));
  end if;
  return jsonb_build_object('body',private.wa_phrase(l,'choose'));
 end if;
 if cmd in ('0','hi','hello','help','menu','ನಮಸ್ಕಾರ','నమస్కారం','नमस्ते') then
  if r='customer' then perform private.wa_order_command(p_phone,'reset');elsif r='farmer' then perform private.wa_harvest_command(p_phone,'harvestreset');end if;
  update private.wa_guides set step='menu',target=null,choice=null,crop=null,qty=null,snapshot='[]',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,menu_key));
 end if;
 if g.expires_at<=clock_timestamp() then
  update private.wa_guides set step='menu',target=null,choice=null,crop=null,qty=null,snapshot='[]',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'expired')||E'\n\n'||private.wa_phrase(l,menu_key));
 end if;
 if g.step='menu' and cmd='3' then
  update private.wa_guides set step='language',target=null where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'choose'));
 elsif g.step='menu' and cmd='2' then
  if r='customer' then
   select * into o from public.orders where customer_id=u and source='whatsapp_test' order by created_at desc,id desc limit 1;
   body:=case when not found then private.wa_phrase(l,'noorder') else private.wa_phrase(l,case when o.status='cancelled' then 'cancelled_status' else o.status end)||' | ₹'||round(o.total_paise::numeric/100,2)::text||' | '||private.wa_phrase(l,'test') end;
  elsif r='farmer' then
   select string_agg(left(regexp_replace(z.crop,'[[:cntrl:]]',' ','g'),100)||' | '||z.quantity_kg||' kg | '||private.wa_phrase(l,case when z.status='pending' then 'pending_status' else z.status end)||coalesce(' | '||z.grade,'')||case when z.status='rejected' then ' | '||left(regexp_replace(coalesce(z.rejection_reason,''),'[[:cntrl:]]',' ','g'),200) else '' end,E'\n' order by z.created_at desc,z.id desc) into list_body from (select * from public.harvests where farmer_id=u order by created_at desc,id desc limit 5) z;
   body:=coalesce(private.wa_phrase(l,'myharvests')||E'\n'||list_body,private.wa_phrase(l,'noharvest'));
  else body:='https://agriconnect-q7c2.onrender.com/';end if;
  return jsonb_build_object('body',body||E'\n\n'||private.wa_phrase(l,menu_key));
 elsif (g.step='menu' and cmd='1' and r in ('customer','farmer')) or (g.step in ('shop_list','fpo_list') and cmd='9') then
  n:=case when g.step='menu' then 1 else least(g.page_no+1,999) end;
  if r='customer' then
   perform private.wa_order_command(p_phone,'shop '||n);
   select * into s from private.wa_shop where user_id=u;
   select string_agg(ord::text||'. '||left(regexp_replace(vv->>'crop','[[:cntrl:]]',' ','g'),100)||' | '||private.wa_phrase(l,'grade')||' '||(vv->>'grade')||' | '||left(regexp_replace(vv->>'fpo_name','[[:cntrl:]]',' ','g'),100)||' | ₹'||round((vv->>'price_paise_per_kg')::numeric/100,2)||'/kg | '||(vv->>'available_kg')||' kg',E'\n' order by ord) into list_body from jsonb_array_elements(s.products) with ordinality e(vv,ord);
   body:=private.wa_phrase(l,'produce');x:=s.products;
   update private.wa_guides set step='shop_list',page_no=n,snapshot=x,target=null,expires_at=s.catalogue_expires where user_id=u;
  else
   perform private.wa_harvest_command(p_phone,'fpos '||n);
   select * into f from private.wa_harvest_drafts where user_id=u;
   select string_agg(ord::text||'. '||left(regexp_replace(vv->>'name','[[:cntrl:]]',' ','g'),120),E'\n' order by ord) into list_body from jsonb_array_elements(f.fpos) with ordinality e(vv,ord);
   body:=private.wa_phrase(l,'fpos');x:=f.fpos;
   update private.wa_guides set step='fpo_list',page_no=n,snapshot=x,target=null,expires_at=f.list_expires where user_id=u;
  end if;
  return jsonb_build_object('body',body||E'\n'||coalesce(list_body,private.wa_phrase(l,'empty'))||E'\n\n'||private.wa_phrase(l,'number'));
 elsif (g.step='menu' and cmd='1' and r='manager') then
  a:=private.manager_inbox_for(u,5);
  select string_agg(ord::text||'. '||private.wa_phrase(l,vv->>'kind')||' | '||left(regexp_replace(vv->>'fpo_name','[[:cntrl:]]',' ','g'),120),E'\n' order by ord) into list_body from jsonb_array_elements(a->'alerts') with ordinality e(vv,ord);
  update private.wa_guides set step='alert_list',snapshot=a->'alerts',expires_at=clock_timestamp()+interval '10 minutes' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'alerts')||E'\n'||private.wa_phrase(l,'members')||': '||(a->>'pending_members')||E'\n'||private.wa_phrase(l,'harvests')||': '||(a->>'pending_harvests')||E'\n'||private.wa_phrase(l,'orders')||': '||(a->>'open_orders')||E'\n'||private.wa_phrase(l,'unread')||': '||(a->>'unread')||E'\n\n'||coalesce(list_body,'')||E'\n'||private.wa_phrase(l,'readchoice'));
 elsif g.step='alert_list' and r='manager' and cmd ~ '^[1-5]$' then
  n:=cmd::integer;
  if n>jsonb_array_length(g.snapshot) then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  ok:=private.manager_read_for(u,(g.snapshot->(n-1)->>'id')::uuid);
  update private.wa_guides set step='menu',snapshot='[]' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,case when ok then 'readok' else 'expired' end)||E'\n\n'||private.wa_phrase(l,menu_key));
 elsif g.step in ('shop_list','fpo_list') and cmd ~ '^[1-8]$' then
  n:=cmd::integer;
  if n>jsonb_array_length(g.snapshot) then return jsonb_build_object('body',private.wa_phrase(l,'invalid'));end if;
  update private.wa_guides set choice=n,step=case when g.step='shop_list' then 'shop_qty' else 'farm_crop' end where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,case when g.step='shop_list' then 'quantity' else 'crop' end)||private.wa_phrase(l,'hint'));
 elsif g.step='farm_crop' and r='farmer' then
  if length(v)>100 or v ~ '[|[:cntrl:]]' then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'crop'));end if;
  update private.wa_guides set crop=v,step='farm_qty' where user_id=u;
  return jsonb_build_object('body',private.wa_phrase(l,'quantity')||private.wa_phrase(l,'hint'));
 elsif g.step in ('shop_qty','farm_qty') then
  if v !~ '^[0-9]{1,9}([.][0-9]{1,3})?$' then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'quantity'));end if;
  if v::numeric<0.001 or v::numeric>case when g.step='shop_qty' then 10000 else 999999999 end then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'quantity'));end if;
  if g.step='farm_qty' then
   update private.wa_guides set qty=v,step='farm_date' where user_id=u;
   return jsonb_build_object('body',private.wa_phrase(l,'date')||private.wa_phrase(l,'hint'));
  end if;
  select * into s from private.wa_shop where user_id=u;
  if r<>'customer' or s.products is distinct from g.snapshot or s.catalogue_expires<=clock_timestamp() then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  result_text:=private.wa_order_command(p_phone,'buy '||g.choice||' '||v);
  if result_text not like 'Demo order preview:%' then return jsonb_build_object('body',private.wa_phrase(l,'changed'));end if;
  select * into s from private.wa_shop where user_id=u;preview_id:=s.quote_id;p:=s.quote_item;
  body:=private.wa_phrase(l,'preview')||E'\n'||(p->>'crop')||' | '||(p->>'quantity_kg')||' kg | '||private.wa_phrase(l,'grade')||' '||(p->>'grade')||E'\n'||(g.snapshot->(g.choice-1)->>'fpo_name')||E'\n'||private.wa_phrase(l,'total')||': ₹'||round((p->>'quantity_kg')::numeric*(p->>'price_paise_per_kg')::numeric/100,2)||E'\n'||private.wa_phrase(l,'demo');
  update private.wa_guides set step='order_confirm',target=preview_id,expires_at=s.quote_expires where user_id=u;
 elsif g.step='farm_date' and r='farmer' then
  if cmd in ('1','today','ಇಂದು','ఈరోజు','आज') then hd:=today;elsif cmd in ('2','yesterday','ನಿನ್ನೆ','నిన్న','कल') then hd:=today-1;
  else
   if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'date'));end if;
   begin hd:=v::date;exception when datetime_field_overflow or invalid_datetime_format then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'date'));end;
  end if;
  if hd>today then return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,'date'));end if;
  select * into f from private.wa_harvest_drafts where user_id=u;
  if f.fpos is distinct from g.snapshot or f.list_expires<=clock_timestamp() then return jsonb_build_object('body',private.wa_phrase(l,'expired'));end if;
  result_text:=private.wa_harvest_command(p_phone,'HARVEST '||g.choice||' | '||g.crop||' | '||g.qty||' | '||hd::text);
  if result_text not like 'Harvest preview:%' then return jsonb_build_object('body',private.wa_phrase(l,'changed'));end if;
  select * into f from private.wa_harvest_drafts where user_id=u;preview_id:=f.draft_id;
  body:=private.wa_phrase(l,'preview')||E'\n'||f.crop||' | '||f.qty||' kg | '||f.harvest_date||E'\n'||(g.snapshot->(g.choice-1)->>'name')||E'\n'||private.wa_phrase(l,'pending');
  update private.wa_guides set step='harvest_confirm',target=preview_id,expires_at=f.draft_expires where user_id=u;
 elsif g.step in ('order_confirm','harvest_confirm') then return jsonb_build_object('body',private.wa_phrase(l,'tap'));
 else return jsonb_build_object('body',private.wa_phrase(l,'invalid')||E'\n'||private.wa_phrase(l,menu_key));end if;
 buttons:=jsonb_build_array(jsonb_build_object('id','ac_confirm:'||preview_id,'title',private.wa_phrase(l,'confirm')),jsonb_build_object('id','ac_cancel:'||preview_id,'title',private.wa_phrase(l,'cancel')));
 return jsonb_build_object('body',body,'buttons',buttons);
end $$;
create function public.wa_guide(p_phone text,p_text text,p_button boolean) returns jsonb language sql security invoker set search_path='' as $$select private.wa_guide(p_phone,p_text,p_button)$$;
revoke all on function private.wa_phrase(text,text),private.wa_guide(text,text,boolean),public.wa_guide(text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function private.wa_guide(text,text,boolean),public.wa_guide(text,text,boolean) to service_role;
commit;