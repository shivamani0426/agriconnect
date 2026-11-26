// Disposable local PostgreSQL only. Exercise the real transactional RPC across independent sessions.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const exec=promisify(execFile);
if(process.env.WA_DISPOSABLE_CI!=='1'||process.env.PGDATABASE!=='agricitest'||!['localhost','127.0.0.1'].includes(process.env.PGHOST??''))throw Error('Disposable CI database only');
const prefix=randomBytes(16).toString('hex');
const ids=Array.from({length:10},(_,i)=>createHash('sha256').update(prefix+':'+i).digest('hex'));
const phone='919000099999';
const run=async sql=>(await exec('psql',['-X','-qAt','-v','ON_ERROR_STOP=1','-c',sql],{timeout:30000,maxBuffer:1048576})).stdout.trim();
assert.equal(await run("select current_database()"),'agricitest');
const start=performance.now();
try{
 const results=await Promise.all(Array.from({length:40},(_,i)=>run("set role service_role; select public.wa_advanced_prepare('"+ids[i%10]+"','"+phone+"','guide','HI')")));
 assert.equal(results.filter(x=>x==='t').length,10);
 assert.equal(results.filter(x=>x==='f').length,30);
 const jobs=await Promise.all(Array.from({length:12},()=>run("set role service_role; select coalesce(public.wa_relay_take('"+phone+"','"+ids[0]+"')::text,'none')")));
 assert.equal(jobs.filter(x=>x!=='none').length,1);
 const job=JSON.parse(jobs.find(x=>x!=='none'));assert.equal(job.attempt,1);
 assert.equal(await run("set role service_role; select public.wa_relay_finish('"+ids[0]+"',1,'accepted','wamid."+prefix+"',10)"),'t');
 const list=ids.map(x=>"'"+x+"'").join(',');
 assert.equal(await run("select count(*) from private.wa_relay_outbox where message_hash in ("+list+")"),'10');
 console.log('PASS: 40 concurrent SQL preparations, 10 unique receipts, 30 duplicate rejections, 12 competing claims, exactly 1 winner; elapsed ms='+Math.round(performance.now()-start));
}finally{
 await run("delete from public.whatsapp_webhook_receipts where message_hash in ("+ids.map(x=>"'"+x+"'").join(',')+")");
}
