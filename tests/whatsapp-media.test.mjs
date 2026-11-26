import test from 'node:test';
import assert from 'node:assert/strict';
import {downloadMedia,validateMetaUrl,createMedia} from '../supabase/functions/whatsapp-webhook/media.mjs';
import {createHandler,signature,PHONE_ID,WABA_ID} from '../supabase/functions/whatsapp-webhook/handler.mjs';
const phone='919999999999', secret='unit-test-secret', now=1700000000000, id='a'.repeat(64), uuid='12345678-1234-4123-8123-123456789abc', path=uuid+'/wa-'+uuid+'.jpg';
const photo={id:'123456789',mime_type:'image/jpeg',caption:'PHOTO '+uuid};
const imageBytes=new Uint8Array([255,216,255,224,0,1,255,217]);
const oggBytes=new Uint8Array([79,103,103,83,1,2,3,4]);
const metaUrl='https://lookaside.fbsbx.com/whatsapp_business/attachments/?mid=123';
const baseEnv={WA_TEST_REPLIES_ENABLED:'true',WA_RELAY_V2_ENABLED:'true',WA_ADVANCED_ENABLED:'true',WA_PHOTO_ENABLED:'true',WA_TEST_RECIPIENTS:phone,WA_APP_SECRET:secret,WA_ACCESS_TOKEN:'fake',SUPABASE_URL:'https://example.invalid',WA_VOICE_ENABLED:'true',WA_VOICE_ENDPOINT:'https://speech.example.invalid/transcribe',WA_VOICE_SERVICE_TOKEN:'fake-voice'};
async function metadata(bytes,mime_type){const h=await crypto.subtle.digest('SHA-256',bytes);return {id:photo.id,mime_type,file_size:bytes.length,sha256:Array.from(new Uint8Array(h),x=>x.toString(16).padStart(2,'0')).join(''),url:metaUrl};}
test('Meta media URL is restricted to verified host, no redirect or arbitrary URL',()=>{
 assert.equal(validateMetaUrl(metaUrl),metaUrl);
 for(const u of ['http://lookaside.fbsbx.com/whatsapp_business/attachments/','https://evil.invalid/whatsapp_business/attachments/','https://lookaside.fbsbx.com.evil.invalid/whatsapp_business/attachments/','https://lookaside.fbsbx.com/other','https://user@lookaside.fbsbx.com/whatsapp_business/attachments/'])assert.throws(()=>validateMetaUrl(u));
});
test('download validates media identity, MIME, bytes, length and hash',async()=>{
 const data=await metadata(imageBytes,'image/jpeg');
 const fetcher=async(url,opts)=>{assert.equal(opts.redirect,'error');return url.startsWith('https://graph.facebook.com/')?Response.json(data):new Response(imageBytes,{headers:{'content-type':'image/jpeg'}});};
 assert.deepEqual(await downloadMedia({token:'fake',id:photo.id,kind:'image',expectedMime:'image/jpeg',fetcher}),imageBytes);
 data.sha256='bad';
 await assert.rejects(downloadMedia({token:'fake',id:photo.id,kind:'image',expectedMime:'image/jpeg',fetcher}),/integrity/);
 data.file_size=6*1024*1024;
 await assert.rejects(downloadMedia({token:'fake',id:photo.id,kind:'image',expectedMime:'image/jpeg',fetcher}),/metadata/);
});
test('media claim denied before any provider or storage request',async()=>{
 const calls=[];const media=createMedia({env:k=>baseEnv[k],rpc:async(n,p)=>{calls.push([n,p]);return {state:'denied'};},dbHeaders:()=>({}),dispatch:async()=>{},defer:async t=>t,fetcher:async()=>assert.fail('external access')});
 await media.start({id,phone,kind:'image',media:photo});
 assert.deepEqual(calls.map(x=>x[0]),['wa_media_claim','wa_advanced_prepare']);
 assert.equal(calls[0][1].p_target,uuid);
});
test('photo is uploaded only to reserved private path and finished once',async()=>{
 const calls=[];const data=await metadata(imageBytes,'image/jpeg');
 const media=createMedia({env:k=>baseEnv[k],rpc:async(n,p)=>{calls.push([n,p]);return n==='wa_media_claim'?{state:'claimed',path}:true;},dbHeaders:()=>({apikey:'fake'}),dispatch:async(...a)=>calls.push(['dispatch',a]),defer:async t=>t,fetcher:async(url,opts)=>{if(url.startsWith('https://graph.facebook.com/'))return Response.json(data);if(url===metaUrl)return new Response(imageBytes,{headers:{'content-type':'image/jpeg'}});assert.equal(url,'https://example.invalid/storage/v1/object/harvest-photos/'+path);assert.equal(opts.headers['x-upsert'],'false');assert.deepEqual(opts.body,imageBytes);return new Response('ok');}});
 await media.start({id,phone,kind:'image',media:photo});
 assert.equal(calls.find(x=>x[0]==='wa_media_finish')[1].p_ok,true);
 assert.equal(calls.filter(x=>x[0]==='dispatch').length,1);
});
test('voice is preview-only; configured service receives audio only, never sender identity',async()=>{
 const calls=[];const data=await metadata(oggBytes,'audio/ogg');
 const media=createMedia({env:k=>baseEnv[k],rpc:async(n,p)=>{calls.push([n,p]);return n==='wa_media_claim'?{state:'claimed',path:null}:true;},dbHeaders:()=>({}),dispatch:async()=>{},defer:async t=>t,fetcher:async(url,opts)=>{if(url.startsWith('https://graph.facebook.com/'))return Response.json(data);if(url===metaUrl)return new Response(oggBytes,{headers:{'content-type':'audio/ogg'}});assert.equal(url,baseEnv.WA_VOICE_ENDPOINT);assert.equal(opts.headers.Authorization,'Bearer fake-voice');assert.deepEqual(opts.body,oggBytes);return Response.json({text:'CONFIRM order'});}});
 await media.start({id,phone,kind:'audio',media:{id:photo.id,mime_type:'audio/ogg; codecs=opus'}});
 assert.equal(calls.find(x=>x[0]==='wa_media_finish')[1].p_transcript,'CONFIRM order');
 assert.ok(!calls.some(x=>x[0]==='wa_advanced_prepare'));
});
test('disabled voice and unallowlisted media never fetch data',async()=>{
 const calls=[];const media=createMedia({env:k=>k==='WA_VOICE_ENABLED'?'false':baseEnv[k],rpc:async(n,p)=>{calls.push([n,p]);return true;},dbHeaders:()=>({}),dispatch:async()=>{},defer:async t=>t,fetcher:async()=>assert.fail('external access')});
 await media.start({id,phone,kind:'audio',media:{id:photo.id,mime_type:'audio/ogg'}});
 await media.start({id,phone:'919000000000',kind:'image',media:photo});
 assert.equal(calls.length,1);assert.equal(calls[0][1].p_command,'/voicehelp');
});
async function request(n,{sender=phone,key=secret,age=0,type='text'}={}){
 const msg={id:'wamid.load'+n,from:sender,type,timestamp:String(now/1000-age),[type]:type==='text'?{body:'Hi'}:photo};
 const body=JSON.stringify({object:'whatsapp_business_account',entry:[{id:WABA_ID,changes:[{field:'messages',value:{metadata:{phone_number_id:PHONE_ID},messages:[msg]}}]}]});
 return new Request('https://example.invalid/webhook',{method:'POST',headers:{'x-hub-signature-256':await signature(key,new TextEncoder().encode(body))},body});
}
test('only fresh signed allowlisted media reaches handler',async()=>{
 const events=[];const handler=createHandler({env:k=>baseEnv[k],now:()=>now,prepare:async()=>{},dispatch:async()=>{},media:async x=>events.push(x)});
 await handler(await request(1,{type:'image'}));await handler(await request(2,{type:'image',key:'wrong'}));await handler(await request(3,{type:'image',age:601}));await handler(await request(4,{type:'image',sender:'919000000000'}));
 assert.equal(events.length,1);assert.equal(events[0].kind,'image');assert.equal(events[0].phone,phone);
});
test('200 concurrent signed webhook requests preserve unique message identities (mocked DB)',async()=>{
 const ids=new Set(),dispatches=new Set();let duplicates=0;
 const handler=createHandler({env:k=>baseEnv[k],now:()=>now,prepare:async x=>{if(ids.has(x.id))duplicates++;ids.add(x.id);},dispatch:async(p,id)=>dispatches.add(id)});
 const requests=await Promise.all(Array.from({length:200},(_,i)=>request(i%100)));
 const results=await Promise.all(requests.map(r=>handler(r)));
 assert.ok(results.every(r=>r.status===200));assert.equal(ids.size,100);assert.equal(duplicates,100);assert.equal(dispatches.size,100);
});
