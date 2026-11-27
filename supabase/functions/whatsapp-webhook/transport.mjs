// Testable relay transport. Never forward provider response bodies or credentials to clients/logs.
import {PHONE_ID} from './handler.mjs';
const graph='https://graph.facebook.com/v25.0/'+PHONE_ID;
const chars=s=>typeof s==='string'?Array.from(s).length:Infinity;
const uuid='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const confirmId=new RegExp('^ac_(confirm|cancel):'+uuid+'$');
const listId=new RegExp('^ac_menu:'+uuid+':[1-7]$');
const validId=s=>typeof s==='string'&&s.startsWith('wamid.')&&s.length<=512;
export function allowedRecipients(env){
 return [...new Set((env('WA_TEST_RECIPIENTS')??'').split(',').map(s=>s.trim()).filter(s=>/^[1-9][0-9]{6,14}$/.test(s)))];
}
export function buildMessage(reply){
 const body=reply?.body;
 if(typeof body!=='string'||!body.trim()||chars(body)>4096)throw new Error('Invalid reply body');
 if(reply.buttons&&reply.list)throw new Error('Conflicting interactive payload');
 if(reply.buttons){
  const buttons=reply.buttons;
  if(!Array.isArray(buttons)||buttons.length<1||buttons.length>3||chars(body)>1024||buttons.some(b=>!confirmId.test(b?.id)||!b?.title||chars(b.title)>20)||new Set(buttons.map(b=>b.id)).size!==buttons.length)throw new Error('Invalid buttons');
  return {type:'interactive',interactive:{type:'button',body:{text:body},action:{buttons:buttons.map(b=>({type:'reply',reply:{id:b.id,title:b.title}}))}}};
 }
 if(reply.list){
  const rows=reply.list,label=reply.list_label;
  if(!Array.isArray(rows)||rows.length<1||rows.length>10||chars(body)>1024||!label||chars(label)>20||rows.some(b=>!listId.test(b?.id)||!b?.title||chars(b.title)>24)||new Set(rows.map(b=>b.id)).size!==rows.length)throw new Error('Invalid list');
  return {type:'interactive',interactive:{type:'list',body:{text:body},action:{button:label,sections:[{rows:rows.map(b=>({id:b.id,title:b.title}))}]}}};
 }
 return {type:'text',text:{preview_url:false,body}};
}
function rejection(status,code){
 if(status===401||status===403||code===190)return 'credentials';
 if(status===429)return 'retryable';
 if(status===408||status>=500)return 'unknown';
 return 'rejected';
}
export async function sendOnce({token,to,reply,fetcher=fetch,report=()=>{}}){
 let message;
 try{message=buildMessage(reply);}catch{report('wa_relay_payload_invalid');return {state:'rejected'};}
 if(!token)return {state:'credentials'};
 try{
  const r=await fetcher(graph+'/messages',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({messaging_product:'whatsapp',recipient_type:'individual',to,...message}),signal:AbortSignal.timeout(8000),redirect:'error'});
  let data;try{data=await r.json();}catch{/* A successful HTTP response without a valid message ID is ambiguous. */}
  if(!r.ok){
   const code=Number.isSafeInteger(data?.error?.code)?data.error.code:'unknown';
   const subcode=Number.isSafeInteger(data?.error?.error_subcode)?data.error.error_subcode:'unknown';
   const kind=message.type==='interactive'?message.interactive.type:'text';
   report('wa_relay_provider_error status='+r.status+' code='+code+' subcode='+subcode+' kind='+kind);
   return {state:rejection(r.status,data?.error?.code)};
  }
  const provider=data?.messages?.[0]?.id;
  return validId(provider)?{state:'accepted',provider}:{state:'unknown'};
 }catch{return {state:'unknown'};}
}
export async function checkToken({token,fetcher=fetch}){
 if(!token)return 'missing';
 try{
  const r=await fetcher(graph+'?fields=id',{headers:{Authorization:'Bearer '+token},signal:AbortSignal.timeout(5000),redirect:'error'});
  if(r.ok){const data=await r.json();return data?.id===PHONE_ID?'phone_readable':'unexpected_response';}
  let code;try{code=(await r.json())?.error?.code;}catch{}
  return rejection(r.status,code);
 }catch{return 'unreachable';}
}
export function createRelay({env,rpc,fetcher=fetch,now=()=>Date.now(),report=()=>{}}){
 const enabled=()=>env('WA_TEST_REPLIES_ENABLED')==='true'&&env('WA_RELAY_V2_ENABLED')==='true';
 const canSend=phone=>enabled()&&allowedRecipients(env).includes(phone);
 async function process(phone,id=null){
  if(!canSend(phone)||!env('WA_ACCESS_TOKEN'))return false;
  const q=await rpc('wa_relay_take',{p_phone:phone,p_id:id});
  if(!q)return false;
  const start=now();
  // Recheck flags and allowlist on every attempt; never use a recipient from a stored arbitrary payload.
  const result=canSend(phone)?await sendOnce({token:env('WA_ACCESS_TOKEN'),to:phone,reply:q.reply,fetcher,report}):{state:'rejected'};
  const elapsed=Math.min(120000,Math.max(0,Math.round(now()-start)));
  await rpc('wa_relay_finish',{p_id:q.id,p_attempt:q.attempt,p_state:result.state,p_provider:result.provider??null,p_latency:elapsed});
  report('wa_relay_'+result.state);
  return true;
 }
 return {
  prepare:({id,phone,route,command})=>rpc('wa_relay_prepare',{p_id:id,p_phone:phone,p_route:route,p_command:command}),
  process,
  statusCallback:(phone,id,status)=>rpc('wa_relay_delivery',{p_phone:phone,p_provider:id,p_delivery:status}),
  // Bounded batch. The scheduler can invoke this without another inbound message.
  async drain(){
   if(!enabled())return {enabled:false,attempted:0};
   let attempted=0;
   for(const phone of allowedRecipients(env).slice(0,20)){if(await process(phone))attempted++;}
   return {enabled:true,attempted};
  },
  async health(){
   const queue=await rpc('wa_relay_health',{});
   return {enabled:enabled(),allowlisted_recipients:allowedRecipients(env).length,token:await checkToken({token:env('WA_ACCESS_TOKEN'),fetcher}),queue};
  }
 };
}
export async function authorizeWorker(env,header){
 const secret=env('WA_RELAY_WORKER_TOKEN');
 if(typeof secret!=='string'||secret.length<32||typeof header!=='string'||!header.startsWith('Bearer ')||header.length>1024)return false;
 const enc=new TextEncoder();
 const [a,b]=await Promise.all([crypto.subtle.digest('SHA-256',enc.encode(secret)),crypto.subtle.digest('SHA-256',enc.encode(header.slice(7)))]);
 const x=new Uint8Array(a),y=new Uint8Array(b);let d=0;for(let i=0;i<x.length;i++)d|=x[i]^y[i];return d===0;
}
