import test from 'node:test';
import assert from 'node:assert/strict';
import {classifyResponse,relayWithRetry} from '../supabase/functions/whatsapp-webhook/relay.mjs';
test('classifies provider response without exposing secrets',()=>{
 assert.equal(classifyResponse(200),'accepted');
 assert.equal(classifyResponse(401),'credentials');
 assert.equal(classifyResponse(400,190),'credentials');
 assert.equal(classifyResponse(429),'retryable');
 assert.equal(classifyResponse(400),'rejected');
});
test('rate limiting is retried once',async()=>{
 let calls=0;const delays=[];
 const result=await relayWithRetry(async()=>({state:++calls===1?'retryable':'accepted'}),{sleep:async ms=>delays.push(ms)});
 assert.equal(calls,2);assert.deepEqual(delays,[1000]);assert.equal(result.state,'accepted');
});
test('repeated throttling is bounded',async()=>{
 let calls=0;
 const result=await relayWithRetry(async()=>{calls++;return {state:'retryable'};},{sleep:async()=>{}});
 assert.equal(calls,2);assert.equal(result.state,'retryable');
});
test('ambiguous transport exception never retries',async()=>{
 let calls=0;
 const result=await relayWithRetry(async()=>{calls++;throw new Error('timeout');});
 assert.equal(calls,1);assert.equal(result.state,'unknown');
});
test('credential rejection never retries',async()=>{
 let calls=0;
 const result=await relayWithRetry(async()=>{calls++;return {state:'credentials'};});
 assert.equal(calls,1);assert.equal(result.state,'credentials');
});
