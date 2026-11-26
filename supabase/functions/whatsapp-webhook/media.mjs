// Only authenticated allowlisted webhook events can call start(). No arbitrary media URLs.
import {PHONE_ID} from './handler.mjs';
import {allowedRecipients} from './transport.mjs';
const types={'image/jpeg':'jpg','image/png':'png','image/webp':'webp','audio/ogg':'ogg'};
const uuid='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const mediaId=/^[0-9]{1,32}$/;
const pathPattern=new RegExp('^'+uuid+'/wa-'+uuid+'\\.(jpg|png|webp)$');
const mime=s=>typeof s==='string'?s.split(';')[0].trim().toLowerCase():'';
const bytesLimit=kind=>kind==='image'?5*1024*1024:2*1024*1024;
const graph='https://graph.facebook.com/v25.0/';
function matchBytes(a,m){
 if(m==='image/jpeg')return a.length>4&&a[0]===255&&a[1]===216&&a[2]===255;
 if(m==='image/png')return a.length>8&&[137,80,78,71,13,10,26,10].every((v,i)=>a[i]===v);
 if(m==='image/webp')return a.length>12&&String.fromCharCode(...a.slice(0,4))==='RIFF'&&String.fromCharCode(...a.slice(8,12))==='WEBP';
 return m==='audio/ogg'&&a.length>4&&String.fromCharCode(...a.slice(0,4))==='OggS';
}
async function bounded(response,limit){
 if(!response.ok||!response.body)throw Error('Media unavailable');
 const size=Number(response.headers.get('content-length'));if(Number.isFinite(size)&&size>limit)throw Error('Media too large');
 const reader=response.body.getReader(),parts=[];let n=0;
 while(true){const {value,done}=await reader.read();if(done)break;n+=value.byteLength;if(n>limit){await reader.cancel();throw Error('Media too large');}parts.push(value);}
 const a=new Uint8Array(n);let offset=0;for(const p of parts){a.set(p,offset);offset+=p.length;}return a;
}
async function smallJson(r,limit=16384){return JSON.parse(new TextDecoder().decode(await bounded(r,limit)));}
export function validateMetaUrl(value){
 const u=new URL(value);
 if(u.protocol!=='https:'||u.hostname!=='lookaside.fbsbx.com'||u.port||u.username||u.password||!u.pathname.startsWith('/whatsapp_business/'))throw Error('Unsafe media URL');
 return u.href;
}
export async function downloadMedia({token,id,kind,expectedMime,fetcher=fetch}){
 if(!token||!mediaId.test(id)||!types[expectedMime]||(kind==='image')!==expectedMime.startsWith('image/'))throw Error('Invalid media');
 const headers={Authorization:'Bearer '+token};
 const meta=await smallJson(await fetcher(graph+id+'?phone_number_id='+PHONE_ID,{headers,redirect:'error',signal:AbortSignal.timeout(6000)}));
 if(String(meta.id)!==id||mime(meta.mime_type)!==expectedMime||!Number.isInteger(Number(meta.file_size))||Number(meta.file_size)<1||Number(meta.file_size)>bytesLimit(kind))throw Error('Invalid metadata');
 const url=validateMetaUrl(meta.url);
 const r=await fetcher(url,{headers,redirect:'error',signal:AbortSignal.timeout(10000)});
 const actual=mime(r.headers.get('content-type'));
 if(actual!==expectedMime&&actual!=='application/octet-stream')throw Error('Unexpected content type');
 const bytes=await bounded(r,bytesLimit(kind));
 if(bytes.length!==Number(meta.file_size)||!matchBytes(bytes,expectedMime))throw Error('Invalid content');
 const digest=new Uint8Array(await crypto.subtle.digest('SHA-256',bytes));
 const hex=Array.from(digest,x=>x.toString(16).padStart(2,'0')).join('');
 const base64=btoa(String.fromCharCode(...digest));
 if(typeof meta.sha256!=='string'||![hex,base64].includes(meta.sha256))throw Error('Media integrity mismatch');
 return bytes;
}
function voiceUrl(env){
 if(env('WA_VOICE_ENABLED')!=='true'||!env('WA_VOICE_ENDPOINT')||!env('WA_VOICE_SERVICE_TOKEN'))return null;
 try{const u=new URL(env('WA_VOICE_ENDPOINT'));return u.protocol==='https:'&&!u.username&&!u.password&&!u.hash?u.href:null;}catch{return null;}
}
export function createMedia({env,rpc,dbHeaders,dispatch,defer,fetcher=fetch,report=()=>{}}){
 const enabled=()=>env('WA_TEST_REPLIES_ENABLED')==='true'&&env('WA_RELAY_V2_ENABLED')==='true'&&env('WA_ADVANCED_ENABLED')==='true';
 const can=phone=>enabled()&&allowedRecipients(env).includes(phone);
 const storage=()=>env('SUPABASE_URL')+'/storage/v1/object/harvest-photos';
 const help=async(phone,id,kind)=>{
  await rpc('wa_relay_prepare',{p_id:id,p_phone:phone,p_route:'guide',p_command:kind==='audio'?'/voicehelp':'/photohelp'});
  await dispatch(phone,id);
 };
 async function start({id,phone,kind,media}){
  if(!can(phone))return;
  const m=mime(media?.mime_type),target=kind==='image'?new RegExp('^photo ('+uuid+')$','i').exec((media?.caption??'').trim())?.[1]?.toLowerCase():null;
  const endpoint=kind==='audio'?voiceUrl(env):null;
  if(!mediaId.test(media?.id??'')||!types[m]||(kind==='image'&&(!m.startsWith('image/')||!target||env('WA_PHOTO_ENABLED')!=='true'))||(kind==='audio'&&(m!=='audio/ogg'||!endpoint))){
   await help(phone,id,kind);return;
  }
  const job=await rpc('wa_media_claim',{p_id:id,p_phone:phone,p_kind:kind,p_target:target??null,p_ext:types[m]});
  if(job?.state==='duplicate'){await dispatch(phone,id);return;}
  if(job?.state==='busy')return;
  if(job?.state!=='claimed'){await help(phone,id,kind);return;}
  await defer((async()=>{
   let ok=false,transcript=null;
   try{
    if(!can(phone))throw Error('Disabled');
    const bytes=await downloadMedia({token:env('WA_ACCESS_TOKEN'),id:media.id,kind,expectedMime:m,fetcher});
    if(!can(phone))throw Error('Disabled');
    if(kind==='image'){
     if(env('WA_PHOTO_ENABLED')!=='true'||!pathPattern.test(job.path)||!job.path.endsWith('.'+types[m]))throw Error('Invalid path');
     const r=await fetcher(storage()+'/'+job.path,{method:'POST',headers:{...dbHeaders(),'Content-Type':m,'x-upsert':'false'},body:bytes,redirect:'error',signal:AbortSignal.timeout(10000)});
     ok=r.ok;
    }else{
     // Operator-configured speech-to-text endpoint only, after explicit account consent.
     if(voiceUrl(env)!==endpoint)throw Error('Voice disabled');
     const r=await fetcher(endpoint,{method:'POST',headers:{Authorization:'Bearer '+env('WA_VOICE_SERVICE_TOKEN'),'Content-Type':'audio/ogg'},body:bytes,redirect:'error',signal:AbortSignal.timeout(25000)});
     const result=await smallJson(r);
     if(typeof result.text==='string'&&result.text.trim().length>0&&result.text.trim().length<=512){transcript=result.text.trim();ok=true;}
    }
   }catch{report('wa_media_processing_failed');}
   if(can(phone)&&await rpc('wa_media_finish',{p_id:id,p_phone:phone,p_ok:ok,p_transcript:transcript}))await dispatch(phone,id);
  })().catch(()=>report('wa_media_worker_failed')));
 }
 async function cleanup(){
  const jobs=await rpc('wa_media_cleanup',{});
  if(!Array.isArray(jobs))return 0;
  let cleaned=0;
  for(const j of jobs){
   if(!pathPattern.test(j.path)||!/^[a-f0-9]{64}$/.test(j.message_hash))continue;
   try{
    const r=await fetcher(storage(),{method:'DELETE',headers:dbHeaders(),body:JSON.stringify({prefixes:[j.path]}),redirect:'error',signal:AbortSignal.timeout(8000)});
    if(r.ok){await rpc('wa_media_cleaned',{p_id:j.message_hash});cleaned++;}
   }catch{report('wa_media_cleanup_failed');}
  }
  return cleaned;
 }
 return {start,cleanup,voiceConfigured:()=>!!voiceUrl(env)};
}
