// Candidate v2 transport, no network access unless injected by the existing signed webhook.
export async function hashProvider(id){const b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(id));return Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');}
export function graphMessage(reply){
 const body=reply?.body;
 if(typeof body!=='string'||body.length<1||body.length>4096)throw Error('Invalid reply body');
 if(reply.list){
  if(reply.buttons||body.length>1024||!Array.isArray(reply.list)||reply.list.length<1||reply.list.length>10||reply.list.some(x=>!/^ac_nav:[0-9a-f-]{36}:[1-6]$/.test(x.id)||typeof x.title!=='string'||x.title.length<1||x.title.length>24))throw Error('Invalid list');
  return {type:'interactive',interactive:{type:'list',body:{text:body},action:{button:'Choose action',sections:[{title:'AgriConnect',rows:reply.list}]}}};
 }
 if(reply.buttons){
  if(body.length>1024||!Array.isArray(reply.buttons)||reply.buttons.length<1||reply.buttons.length>3||reply.buttons.some(x=>!/^ac_(confirm|cancel):[0-9a-f-]{36}$/.test(x.id)||typeof x.title!=='string'||x.title.length<1||x.title.length>20))throw Error('Invalid button');
  return {type:'interactive',interactive:{type:'button',body:{text:body},action:{buttons:reply.buttons.map(x=>({type:'reply',reply:x}))}}};
 }
 return {type:'text',text:{preview_url:false,body}};
}
// Retry only an explicit provider rate-limit rejection. Ambiguous timeouts or 5xx are never retried.
export function classifyGraph(status,body){
 const code=Number.isInteger(body?.error?.code)?body.error.code:null;
 const id=body?.messages?.[0]?.id;
 if(status>=200&&status<300&&typeof id==='string'&&id.startsWith('wamid.')&&id.length<=512)return {outcome:'accepted',providerId:id,error:null};
 if(status===429&&code!==null&&code!==190)return {outcome:'retry',providerId:null,error:code};
 if(status>=400&&status<500&&code!==null)return {outcome:'failed',providerId:null,error:code};
 return {outcome:'uncertain',providerId:null,error:code};
}
export function createV2({rpc,send,clock=()=>Date.now()}){
 return {
 async process({id,phone,text,mode}){
  await rpc('wa_v2_prepare',{p_hash:id,p_phone:phone,p_text:text,p_mode:mode});
  const q=await rpc('wa_v2_take',{p_hash:id,p_phone:phone});
  if(q.state==='retry')return 'retry';
  if(q.state!=='sending'||!q.token)return 'done';
  const start=clock();let r;
  try{r=await send(phone,graphMessage(q.reply));}catch{r={outcome:'uncertain',providerId:null,error:null};}
  const s=await rpc('wa_v2_finish',{p_hash:id,p_token:q.token,p_outcome:r.outcome,p_provider_hash:r.providerId?await hashProvider(r.providerId):null,p_error:r.error??null,p_latency:Math.max(0,Math.min(60000,Math.round(clock()-start)))});
  return s==='retry'?'retry':'done';
 },
 async delivery(id,phone,status){if(typeof id==='string'&&id.startsWith('wamid.')&&id.length<=512&&['sent','delivered','read','failed'].includes(status))await rpc('wa_v2_delivery',{p_provider_hash:await hashProvider(id),p_phone:phone,p_status:status});}
 };
}
