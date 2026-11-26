// Test-only WhatsApp transport. Test checkout and text harvest submission; no real payment, delivery or media. Linking is restricted to signed, allowlisted senders.
export const PHONE_ID='1456298224232496';
export const WABA_ID='2111995459517329';
const enc=new TextEncoder();
const response=(body,status=200)=>new Response(body,{status,headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store'}});
const hex=bytes=>Array.from(new Uint8Array(bytes),x=>x.toString(16).padStart(2,'0')).join('');
const equal=(a,b)=>{if(typeof a!=='string'||typeof b!=='string'||a.length!==b.length)return false;let n=0;for(let i=0;i<a.length;i++)n|=a.charCodeAt(i)^b.charCodeAt(i);return n===0;};
export async function signature(secret,body){
 const key=await crypto.subtle.importKey('raw',enc.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return 'sha256='+hex(await crypto.subtle.sign('HMAC',key,body));
}
const hash=async s=>hex(await crypto.subtle.digest('SHA-256',enc.encode(s)));
export function createHandler({env,claim,finish,send,redeem=async()=> 'invalid',orderCommand,harvestCommand,managerCommand,guide,prepare,dispatch,statusCallback,now=()=>Date.now(),report=()=>{}}){
 return async req=>{
  try{
   if(req.method==='GET'){
    const token=env('WA_VERIFY_TOKEN');if(!token||token.length<32)return response('Not configured',503);
    const p=new URL(req.url).searchParams,challenge=p.get('hub.challenge');
    if(p.get('hub.mode')!=='subscribe'||!equal(p.get('hub.verify_token'),token)||!challenge||!/^\d{1,128}$/.test(challenge))return response('Forbidden',403);
    return response(challenge);
   }
   if(req.method!=='POST')return response('Method not allowed',405);
   const secret=env('WA_APP_SECRET');if(!secret)return response('Not configured',503);
   const supplied=req.headers.get('x-hub-signature-256');
   if(!supplied||!/^sha256=[a-f0-9]{64}$/.test(supplied))return response('Forbidden',403);
   const reader=req.body?.getReader();if(!reader)return response('Bad request',400);
   const parts=[];let size=0;
   while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>262144){await reader.cancel();return response('Too large',413);}parts.push(value);}
   const body=new Uint8Array(size);let offset=0;for(const p of parts){body.set(p,offset);offset+=p.byteLength;}
   if(!equal(supplied,await signature(secret,body)))return response('Forbidden',403);
   let event;try{event=JSON.parse(new TextDecoder().decode(body));}catch{return response('Bad request',400);}
   if(event?.object!=='whatsapp_business_account'||!Array.isArray(event.entry))return response('OK');
   if(env('WA_TEST_REPLIES_ENABLED')!=='true')return response('OK');
   const allowed=new Set((env('WA_TEST_RECIPIENTS')??'').split(',').map(n=>n.trim()).filter(n=>/^\d{7,15}$/.test(n)));
   if(!allowed.size||(!prepare&&!env('WA_ACCESS_TOKEN')))return response('Not configured',503);
   for(const entry of event.entry){
    if(entry?.id!==WABA_ID||!Array.isArray(entry.changes))continue;
    for(const change of entry.changes){
     const v=change?.value;if(change?.field!=='messages'||v?.metadata?.phone_number_id!==PHONE_ID )continue;
     if(statusCallback&&Array.isArray(v.statuses))for(const s of v.statuses){
      if(typeof s?.id==='string'&&s.id.startsWith('wamid.')&&s.id.length<=512&&allowed.has(s.recipient_id)&&['sent','delivered','read','failed'].includes(s.status)){
       await statusCallback(s.recipient_id,s.id,s.status);
      }
     }
     for(const m of Array.isArray(v.messages)?v.messages:[]){
      if(typeof m?.id!=='string'||!m.id.startsWith('wamid.')||m.id.length>512||!allowed.has(m.from) )continue;
      const button=m.type==='interactive'&&m.interactive?.type==='button_reply'&&typeof m.interactive?.button_reply?.id==='string';
      const list=!!prepare&&m.type==='interactive'&&m.interactive?.type==='list_reply'&&typeof m.interactive?.list_reply?.id==='string';
      if(!button&&!list&&(m.type!=='text'||typeof m.text?.body!=='string'))continue;
      if(button&&!guide&&!prepare)continue;
      const original=(button?m.interactive.button_reply.id:list?m.interactive.list_reply.id:m.text.body).trim();
      const command=original.toLowerCase();
      if(command.length>512)continue;
      const link=/^link ([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/.exec(command);
      const greeting=['hi','hello','help','menu'].includes(command);
      const shopping=/^(shop|buy|confirm|track|reset)( |$)/.test(command);
      const farming=/^(fpos|harvest|submit|harvests|harvestreset)( |$)/.test(command);
      const managing=/^(alerts|read)( |$)/.test(command);
      if(!link&&!greeting&&!shopping&&!farming&&!managing&&!guide&&!prepare)continue;
      if(button&&!/^ac_(confirm|cancel):[0-9a-f-]{36}$/.test(command))continue;
      if(list&&!/^ac_menu:[0-9a-f-]{36}:[1-7]$/.test(command))continue;
      const age=now()-Number(m.timestamp)*1000;if(!Number.isFinite(age)||age>600000||age< -60000)continue;
      const id=await hash(PHONE_ID+':'+m.id);
      if(prepare){
       const route=list?'list':button?'button':link?'link':greeting?'guide':shopping?'order':farming?'harvest':managing?'manager':'guide';
       await prepare({id,phone:m.from,route,command:link&&!button&&!list?link[1]:shopping||managing?command:original});
       await dispatch(m.from,id);
       continue;
      }
      if(!await claim(id))continue;
      let ok=false;try{
       let reply='Welcome to AgriConnect! 🌱 To link your account, sign in at https://agriconnect-q7c2.onrender.com/ and open Profile → WhatsApp account. Send SHOP after linking a Customer account. All orders are tests.';
       if(link&&!button){const outcome=await redeem(m.from,link[1]);reply=outcome==='linked'?'WhatsApp linked successfully! Open your AgriConnect profile and refresh linking status. Your account role has not changed.':'Link not completed. Check your number and use a fresh code from your own AgriConnect profile. If this number is already linked, unlink it from that account first.';}
       else if(guide&&(button||greeting||(!shopping&&!farming&&!managing)))reply=await guide(m.from,original,button);
       else if(managerCommand&&(greeting||managing))reply=await managerCommand(m.from,command);
       else if(harvestCommand&&(greeting||farming))reply=await harvestCommand(m.from,original);
       else if(orderCommand&&(greeting||shopping))reply=await orderCommand(m.from,command);
       ok=await send(m.from,reply);
      }catch{report('send_failed');}
      try{await finish(id,ok?'sent':'failed');}catch{report('receipt_update_failed');}
      if(!ok)report('reply_failed');
     }
    }
   }
   return response('OK');
  }catch{report('webhook_failed');return response('Temporary failure',503);}
 };
}
