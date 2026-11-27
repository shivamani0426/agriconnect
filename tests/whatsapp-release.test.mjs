import test from 'node:test';
import assert from 'node:assert/strict';
import {resolveSender,PHONE_ID,WABA_ID} from '../supabase/functions/whatsapp-webhook/config.mjs';
import {createHandler,signature} from '../supabase/functions/whatsapp-webhook/handler.mjs';
import {createRelay,checkToken,sendOnce} from '../supabase/functions/whatsapp-webhook/transport.mjs';
import {downloadMedia} from '../supabase/functions/whatsapp-webhook/media.mjs';
const phoneId='123456789012345',wabaId='987654321098765',recipient='919999999999',secret='unit-test-only';
const settings={WA_PHONE_NUMBER_ID:phoneId,WA_BUSINESS_ACCOUNT_ID:wabaId,WA_TEST_REPLIES_ENABLED:'true',WA_RELAY_V2_ENABLED:'true',WA_TEST_RECIPIENTS:recipient,WA_ACCESS_TOKEN:'mock',WA_APP_SECRET:secret};
const env=k=>settings[k];
test('06G sender default and paired override; invalid or partial overrides fail closed',()=>{
 assert.deepEqual(resolveSender(()=>undefined),{phoneId:PHONE_ID,wabaId:WABA_ID,source:'legacy_default'});
 assert.deepEqual(resolveSender(env),{phoneId,wabaId,source:'configured'});
 for(const p of [{WA_PHONE_NUMBER_ID:phoneId},{WA_BUSINESS_ACCOUNT_ID:wabaId},{WA_PHONE_NUMBER_ID:'../../evil',WA_BUSINESS_ACCOUNT_ID:wabaId},{WA_PHONE_NUMBER_ID:'',WA_BUSINESS_ACCOUNT_ID:wabaId}])assert.equal(resolveSender(k=>p[k]),null);
});
async function req(p=phoneId,w=wabaId){
 const body=JSON.stringify({object:'whatsapp_business_account',entry:[{id:w,changes:[{field:'messages',value:{metadata:{phone_number_id:p},messages:[{type:'text',id:'wamid.06g',from:recipient,timestamp:'1700000000',text:{body:'HI'}}]}}]}]});
 return new Request('https://example.invalid/webhook',{method:'POST',body,headers:{'x-hub-signature-256':await signature(secret,new TextEncoder().encode(body))}});
}
test('06G replacement sender validates both IDs and namespaces inbound receipts',async()=>{
 const calls=[];const create=e=>createHandler({env:e,now:()=>1700000000000,prepare:async x=>calls.push(x),dispatch:async()=>{}});
 const h=create(env);
 await h(await req(PHONE_ID,WABA_ID));await h(await req(phoneId,WABA_ID));assert.equal(calls.length,0);
 await h(await req());assert.equal(calls.length,1);
 const legacy=create(k=>k==='WA_PHONE_NUMBER_ID'||k==='WA_BUSINESS_ACCOUNT_ID'?undefined:env(k));
 await legacy(await req(PHONE_ID,WABA_ID));assert.equal(calls.length,2);assert.notEqual(calls[0].id,calls[1].id);
 const invalid=create(k=>k==='WA_BUSINESS_ACCOUNT_ID'?undefined:env(k));assert.equal((await invalid(await req())).status,503);assert.equal(calls.length,2);
});
test('06G outgoing messages and read-only health use the replacement ID',async()=>{
 const calls=[],logs=[];
 const relay=createRelay({env,rpc:async(n,p)=>n==='wa_relay_take'?{id:'a'.repeat(64),attempt:1,reply:{body:'Test'}}:n==='wa_relay_health'?{}:true,report:x=>logs.push(x),fetcher:async(url,options)=>{calls.push(url);return Response.json(options.method==='POST'?{messages:[{id:'wamid.ok'}]}:{id:phoneId})}});
 assert.equal(await relay.process(recipient),true);assert.equal((await relay.health()).token,'phone_readable');
 assert.deepEqual(calls,['https://graph.facebook.com/v25.0/'+phoneId+'/messages','https://graph.facebook.com/v25.0/'+phoneId+'?fields=id']);
 assert.equal((await relay.health()).sender_configuration,'configured');
 const invalid=createRelay({env:k=>k==='WA_BUSINESS_ACCOUNT_ID'?'invalid':env(k),rpc:async()=>({}),fetcher:async()=>assert.fail('invalid configuration sent'),report:x=>logs.push(x)});
 assert.equal(await invalid.process(recipient),false);assert.equal((await invalid.health()).token,'invalid_configuration');assert.ok(logs.includes('wa_health_token_invalid_configuration'));
 assert.equal(await checkToken({token:'mock',phoneId:'bad',fetcher:async()=>assert.fail()}),'invalid_configuration');
 assert.equal((await sendOnce({token:'mock',phoneId:'bad',to:recipient,reply:{body:'test'},fetcher:async()=>assert.fail()})).state,'credentials');
});
test('06G photo metadata uses replacement phone ID',async()=>{
 let url;await assert.rejects(downloadMedia({token:'mock',id:'123',kind:'image',expectedMime:'image/jpeg',phoneId,fetcher:async(u)=>{url=u;return new Response('{}',{status:403})}}));
 assert.equal(url,'https://graph.facebook.com/v25.0/123?phone_number_id='+phoneId);
});
