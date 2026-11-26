import { createHandler, PHONE_ID } from './handler.mjs';
const env=(name:string)=>Deno.env.get(name);
function dbHeaders(){
 let secret:string|undefined;try{const keys=JSON.parse(env('SUPABASE_SECRET_KEYS')??'{}');secret=typeof keys.default==='string'?keys.default:undefined;}catch{/* use legacy key */}
 if(secret)return {'apikey':secret,'Content-Type':'application/json'};
 const legacy=env('SUPABASE_SERVICE_ROLE_KEY');if(!legacy)throw new Error('DB credential unavailable');
 return {'apikey':legacy,'Authorization':'Bearer '+legacy,'Content-Type':'application/json'};
}
const table=()=>env('SUPABASE_URL')+'/rest/v1/whatsapp_webhook_receipts';
Deno.serve(createHandler({
 env,
 managerCommand:async(phone:string,command:string)=>{
  const r=await fetch(env('SUPABASE_URL')+'/rest/v1/rpc/wa_manager_command',{method:'POST',headers:dbHeaders(),body:JSON.stringify({p_phone:phone,p_command:command}),signal:AbortSignal.timeout(8000)});
  if(!r.ok)throw new Error('Manager command failed');const reply=await r.json();if(typeof reply!=='string'||reply.length>4096)throw new Error('Invalid manager reply');return reply;
 },
 harvestCommand:async(phone:string,command:string)=>{
  const r=await fetch(env('SUPABASE_URL')+'/rest/v1/rpc/wa_harvest_command',{method:'POST',headers:dbHeaders(),body:JSON.stringify({p_phone:phone,p_command:command}),signal:AbortSignal.timeout(8000)});
  if(!r.ok)throw new Error('Harvest command failed');const reply=await r.json();if(typeof reply!=='string'||reply.length>4096)throw new Error('Invalid harvest reply');return reply;
 },
 orderCommand:async(phone:string,command:string)=>{
  const r=await fetch(env('SUPABASE_URL')+'/rest/v1/rpc/wa_order_command',{method:'POST',headers:dbHeaders(),body:JSON.stringify({p_phone:phone,p_command:command}),signal:AbortSignal.timeout(8000)});
  if(!r.ok)throw new Error('Order command failed');const reply=await r.json();if(typeof reply!=='string'||reply.length>4096)throw new Error('Invalid order reply');return reply;
 },
 redeem:async(phone:string,code:string)=>{
  const r=await fetch(env('SUPABASE_URL')+'/rest/v1/rpc/wa_redeem',{method:'POST',headers:dbHeaders(),body:JSON.stringify({p_phone:phone,p_code:code}),signal:AbortSignal.timeout(5000)});
  if(!r.ok)throw new Error('Link redemption failed');return await r.json();
 },
 claim:async (id:string)=>{
  const r=await fetch(table()+'?on_conflict=message_hash',{method:'POST',headers:{...dbHeaders(),Prefer:'resolution=ignore-duplicates,return=representation'},body:JSON.stringify({message_hash:id}),signal:AbortSignal.timeout(5000)});
  if(!r.ok)throw new Error('Receipt claim failed');const rows=await r.json();return Array.isArray(rows)&&rows.length===1;
 },
 finish:async(id:string,status:string)=>{
  const r=await fetch(table()+'?message_hash=eq.'+id,{method:'PATCH',headers:dbHeaders(),body:JSON.stringify({status}),signal:AbortSignal.timeout(5000)});
  if(!r.ok)throw new Error('Receipt update failed');
 },
 send:async(to:string,body:string)=>{
  const token=env('WA_ACCESS_TOKEN');if(!token)return false;
  const r=await fetch('https://graph.facebook.com/v25.0/'+PHONE_ID+'/messages',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({messaging_product:'whatsapp',recipient_type:'individual',to,type:'text',text:{preview_url:false,body}}),signal:AbortSignal.timeout(8000)});
  if(!r.ok){let code:number|undefined;let subcode:number|undefined;try{const e=(await r.json()).error;if(Number.isInteger(e?.code))code=e.code;if(Number.isInteger(e?.error_subcode))subcode=e.error_subcode;}catch{/* never log raw provider response */}console.warn('WhatsApp Graph reply rejected',r.status,'code',code??'unknown','subcode',subcode??'unknown');return false;}return true;
 },
 report:(event:string)=>console.warn(event)
}));
