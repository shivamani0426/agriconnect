import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,signature,PHONE_ID,WABA_ID} from '../supabase/functions/whatsapp-webhook/handler.mjs';
import {createRelay,buildMessage,sendOnce,checkToken,authorizeWorker} from '../supabase/functions/whatsapp-webhook/transport.mjs';
const phone='919999999999', secret='unit-test-secret', token='test-token', worker='x'.repeat(40), uuid='12345678-1234-4123-8123-123456789abc', now=1700000000000;
const settings={WA_APP_SECRET:secret,WA_TEST_RECIPIENTS:phone,WA_TEST_REPLIES_ENABLED:'true',WA_RELAY_V2_ENABLED:'true',WA_ACCESS_TOKEN:token,WA_RELAY_WORKER_TOKEN:worker};
const env=k=>settings[k];
const list={body:'Choose:\n1. Shop',list:[{id:'ac_menu:'+uuid+':1',title:'Shop'}],list_label:'Choose'};
const button={body:'Confirm',buttons:[{id:'ac_confirm:'+uuid,title:'Confirm'}]};
const msg=(type='text',data={text:{body:'Hi'}})=>({id:'wamid.inbound',from:phone,type,timestamp:String(now/1000),...data});
const payload=(value={messages:[msg()]})=>({object:'whatsapp_business_account',entry:[{id:WABA_ID,changes:[{field:'messages',value:{metadata:{phone_number_id:PHONE_ID},...value}}]}]});
async function request(p=payload(),key=secret){const body=JSON.stringify(p);return new Request('https://test.invalid/webhook',{method:'POST',headers:{'x-hub-signature-256':await signature(key,new TextEncoder().encode(body))},body});}
test('valid text, duplicate and actual list events use durable prepare before dispatch',async()=>{
 const calls=[];const handle=createHandler({env,now:()=>now,prepare:async x=>{calls.push(['prepare',x]);return false;},dispatch:async(...args)=>calls.push(['dispatch',...args])});
 await handle(await request());await handle(await request());
 assert.equal(calls.length,4);assert.equal(calls[0][1].route,'guide');assert.equal(calls[0][1].id,calls[2][1].id);assert.equal(calls[1][2],calls[0][1].id);
 const m=msg('interactive',{interactive:{type:'list_reply',list_reply:{id:list.list[0].id}}});
 await handle(await request(payload({messages:[m]})));
 assert.equal(calls[4][1].route,'list');assert.equal(calls[4][1].command,list.list[0].id);
 await handle(await request(payload({messages:[msg('text',{text:{body:list.list[0].id}})]})));
 assert.equal(calls[6][1].route,'guide');
});
test('invalid signature, list ID and unallowlisted sender never dispatch',async()=>{
 let n=0;const handle=createHandler({env,now:()=>now,prepare:async()=>n++,dispatch:async()=>n++});
 assert.equal((await handle(await request(payload(),'wrong'))).status,403);
 await handle(await request(payload({messages:[msg('interactive',{interactive:{type:'list_reply',list_reply:{id:'confirm:evil'}}}),{...msg(),from:'919000000000'}]})));
 assert.equal(n,0);
});
test('prepare failure does not acknowledge or send',async()=>{
 let sent=0;const handle=createHandler({env,now:()=>now,prepare:async()=>{throw Error('db');},dispatch:async()=>sent++});
 assert.equal((await handle(await request())).status,503);assert.equal(sent,0);
});
test('signed status callbacks use allowlisted recipient and do not run commands',async()=>{
 const got=[];const handle=createHandler({env,now:()=>now,prepare:async()=>assert.fail('command executed'),dispatch:async()=>assert.fail('sent'),statusCallback:async(...a)=>got.push(a)});
 await handle(await request(payload({statuses:[{id:'wamid.out',recipient_id:phone,status:'delivered'},{id:'wamid.bad',recipient_id:'919000000000',status:'read'}]})));
 assert.deepEqual(got,[[phone,'wamid.out','delivered']]);
});
test('list and button payloads are restricted, text remains supported',()=>{
 assert.equal(buildMessage(list).interactive.type,'list');assert.equal(buildMessage(button).interactive.type,'button');
 assert.equal(buildMessage({body:'hello'}).type,'text');
 assert.throws(()=>buildMessage({...list,buttons:button.buttons}));
 assert.throws(()=>buildMessage({...list,list:[{id:'ac_confirm:'+uuid,title:'bad'}]}));
 assert.throws(()=>buildMessage({...list,list:[...list.list,...list.list]}));
});
test('provider acceptance needs a message ID; ambiguous failure never claims delivery',async()=>{
 const invoke=async(status,body)=>sendOnce({token,to:phone,reply:list,fetcher:async()=>Response.json(body,{status})});
 assert.deepEqual(await invoke(200,{messages:[{id:'wamid.out'}]}),{state:'accepted',provider:'wamid.out'});
 assert.equal((await invoke(200,{})).state,'unknown');
 assert.equal((await invoke(429,{error:{code:4}})).state,'retryable');
 assert.equal((await invoke(401,{error:{code:190}})).state,'credentials');
 assert.equal((await invoke(500,{})).state,'unknown');
 assert.equal((await sendOnce({token,to:phone,reply:list,fetcher:async()=>{throw Error('timeout');}})).state,'unknown');
});
test('relay sends stored reply only once per acquired job and records latency',async()=>{
 const calls=[];let job={id:'a'.repeat(64),attempt:1,reply:list};
 const relay=createRelay({env,now:()=>1000,rpc:async(name,p)=>{calls.push([name,p]);if(name==='wa_relay_take'){const j=job;job=null;return j;}return true;},fetcher:async(url,opts)=>{calls.push(['provider',JSON.parse(opts.body)]);return Response.json({messages:[{id:'wamid.out'}]});}});
 await relay.process(phone);await relay.process(phone);await relay.process('919000000000');
 assert.equal(calls.filter(a=>a[0]==='provider').length,1);
 assert.equal(calls.filter(a=>a[0]==='wa_relay_prepare').length,0);
 assert.equal(calls.find(a=>a[0]==='wa_relay_finish')[1].p_state,'accepted');
 assert.equal(calls.find(a=>a[0]==='wa_relay_finish')[1].p_provider,'wamid.out');
});
test('worker refuses disabled or non-allowlisted recipients; token checks are read-only',async()=>{
 let n=0;const relay=createRelay({env:k=>k==='WA_RELAY_V2_ENABLED'?'false':env(k),rpc:async()=>n++,fetcher:async()=>n++});
 assert.equal(await relay.process(phone),false);assert.equal((await relay.drain()).enabled,false);assert.equal(n,0);
 assert.equal(await authorizeWorker(env,'Bearer '+worker),true);assert.equal(await authorizeWorker(env,'Bearer wrong'),false);
 assert.equal(await checkToken({token,fetcher:async(url,opts)=>{assert.match(url,/\?fields=id$/);assert.equal(opts.method,undefined);return Response.json({id:PHONE_ID});}}),'phone_readable');
 assert.equal(await checkToken({token:null}),'missing');
});

test('provider diagnostics contain only numeric codes and safe message kind',async()=>{
 const logs=[];
 const result=await sendOnce({token,to:phone,reply:list,report:x=>logs.push(x),fetcher:async()=>Response.json({error:{code:131030,error_subcode:123,message:'private token and recipient',error_data:{details:'private contents'}}},{status:400})});
 assert.equal(result.state,'rejected');
 assert.deepEqual(logs,['wa_relay_provider_error status=400 code=131030 subcode=123 kind=list']);
 logs.length=0;
 await sendOnce({token,to:phone,reply:{body:''},report:x=>logs.push(x),fetcher:async()=>assert.fail('invalid payload sent')});
 assert.deepEqual(logs,['wa_relay_payload_invalid']);
});

test('06E: failed claim for one recipient does not starve the next recovery job',async()=>{
 const other='919999999998',calls=[],logs=[];
 const relay=createRelay({env:k=>k==='WA_TEST_RECIPIENTS'?phone+','+other:env(k),report:x=>logs.push(x),
 rpc:async(n,p)=>{calls.push([n,p]);if(n==='wa_relay_take'){if(p.p_phone===phone)throw Error('private database error');return {id:'b'.repeat(64),attempt:1,reply:{body:'Recovery reply'}};}return true;},
 fetcher:async(url,opts)=>{assert.equal(JSON.parse(opts.body).to,other);return Response.json({messages:[{id:'wamid.recovered'}]});}});
 assert.deepEqual(await relay.drain(),{enabled:true,attempted:1});
 assert.equal(calls.filter(x=>x[0]==='wa_relay_finish').length,1);
 assert.deepEqual(logs,['wa_relay_drain_recipient_failed','wa_relay_accepted']);
});
test('06E: failed finalize after provider acceptance does not send twice or block another recipient',async()=>{
 const other='919999999998',sent=[],logs=[];
 const relay=createRelay({env:k=>k==='WA_TEST_RECIPIENTS'?phone+','+other:env(k),report:x=>logs.push(x),
 rpc:async(n,p)=>{if(n==='wa_relay_take')return {id:(p.p_phone===phone?'a':'b').repeat(64),attempt:1,reply:{body:'Stored reply'}};if(p.p_id==='a'.repeat(64))throw Error('temporary database error');return true;},
 fetcher:async(url,opts)=>{const p=JSON.parse(opts.body).to;sent.push(p);return Response.json({messages:[{id:'wamid.'+p}]});}});
 assert.deepEqual(await relay.drain(),{enabled:true,attempted:1});
 assert.deepEqual(sent,[phone,other]);
 assert.deepEqual(logs,['wa_relay_drain_recipient_failed','wa_relay_accepted']);
});
test('06C/E: revoked allowlist during claim blocks provider call and records safe rejection',async()=>{
 let revoked=false;const finishes=[];
 const relay=createRelay({env:k=>k==='WA_TEST_RECIPIENTS'&&revoked?'':env(k),rpc:async(n,p)=>{if(n==='wa_relay_take'){revoked=true;return {id:'a'.repeat(64),attempt:1,reply:{body:'private'}};}finishes.push(p);return true;},fetcher:async()=>assert.fail('revoked recipient sent')});
 assert.equal(await relay.process(phone),true);assert.equal(finishes[0].p_state,'rejected');
});
test('06E: non-JSON and malformed provider outcomes are never falsely acknowledged',async()=>{
 for(const status of [200,408,500,502,503]){
  const res=await sendOnce({token,to:phone,reply:list,fetcher:async()=>new Response('unparseable',{status})});
  assert.equal(res.state,'unknown');
 }
});
