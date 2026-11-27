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

// 06D: real cross-channel checkout race, not mocked transport. Disposable DB only.
const fpo='b9800000-0000-4000-8000-000000000001';
const farmer='a9800000-0000-4000-8000-000000000001';
const manager='a9800000-0000-4000-8000-000000000002';
const harvest='c9800000-0000-4000-8000-000000000001';
const customers=Array.from({length:12},(_,i)=>'a9800000-0000-4000-8000-'+String(i+3).padStart(12,'0'));
const phones=customers.map((_,i)=>'9190000098'+String(i+1).padStart(2,'0'));
const cart='[{"crop":"QA06 Race Tomatoes","grade":"A","price_paise_per_kg":4000,"quantity_kg":10}]';
const web=(u,sql)=>run("set role authenticated; select set_config('request.jwt.claim.sub','"+u+"',false); "+sql).then(s=>s.split('\n').at(-1));
const wa=(i,sql)=>run("set role service_role; select set_config('app.wa_advanced','on',false); "+sql).then(s=>s.split('\n').at(-1));
assert.equal(await run('select count(*) from public.orders'),'0','CI commerce fixtures must be empty');
await run("insert into auth.users(id,email) values "+[farmer,manager,...customers].map((u,i)=>"('"+u+"','race"+i+"@example.invalid')").join(',')+"; insert into public.profiles(id,display_name,account_role) values "+[farmer,manager,...customers].map((u,i)=>"('"+u+"','Race QA','"+(i===0?'farmer':i===1?'manager':'customer')+"')").join(',')+"; insert into public.fpos(id,name,location) values('"+fpo+"','Race QA FPO','Test'); insert into public.memberships(fpo_id,user_id,role,status) values('"+fpo+"','"+farmer+"','farmer','active'),('"+fpo+"','"+manager+"','manager','active'); insert into public.harvests(id,fpo_id,farmer_id,crop,quantity_kg,harvest_date) values('"+harvest+"','"+fpo+"','"+farmer+"','QA06 Race Tomatoes',60,'2026-01-01'); insert into private.wa_links(user_id,phone) values "+customers.map((u,i)=>"('"+u+"','"+phones[i]+"')").join(',')+";");
await web(manager,"select public.review_harvest('"+harvest+"','A',4000,true,'')");
const quote=await Promise.all(customers.slice(0,6).map(async(_,i)=>{
 const p=phones[i];
 const raw=await wa(i,"select public.wa_guide('"+p+"','HI',false); select public.wa_guide('"+p+"','1',false); select public.wa_guide('"+p+"','SEARCH QA06 Race Tomatoes',false); select public.wa_guide('"+p+"','ADD 1 10',false); select public.wa_guide('"+p+"','CHECKOUT',false)");
 const q=JSON.parse(raw);assert.match(q.buttons[0].id,/^ac_confirm:/);return q.buttons[0].id;
}));
const keys=customers.map((_,i)=>'d9800000-0000-4000-8000-'+String(i+1).padStart(12,'0'));
const hashes=customers.map((_,i)=>createHash('sha256').update(prefix+':commerce:'+i).digest('hex'));
const attempt=async i=>{
 if(i<6){
  const result=await wa(i,"select public.wa_advanced_prepare('"+hashes[i]+"','"+phones[i]+"','button','"+quote[i]+"')");
  return {i,channel:'whatsapp',prepared:result};
 }
 try{
  const order=await web(customers[i],"select public.checkout_order('"+fpo+"','"+cart+"','Race test address','"+keys[i]+"')");
  assert.match(order,/^[0-9a-f-]{36}$/);return {i,channel:'web',order};
 }catch(e){if(!String(e.stderr??'').includes('Stock or price changed'))throw e;return {i,channel:'web',rejected:true};}
};
const raceStart=performance.now();
const attempts=await Promise.all(customers.map((_,i)=>attempt(i)));
assert.equal(attempts.filter(x=>x.channel==='whatsapp'&&x.prepared==='t').length,6);
const state=JSON.parse(await run("select json_build_object('orders',(select count(*) from public.orders where fpo_id='"+fpo+"'),'available',(select available_kg from public.inventory_lots where harvest_id='"+harvest+"'),'reserved',(select reserved_kg from public.inventory_lots where harvest_id='"+harvest+"'),'allocated',(select sum(quantity_kg) from public.order_allocations where fpo_id='"+fpo+"'),'gross',(select sum(total_paise) from public.orders where fpo_id='"+fpo+"'),'payout',(select sum(payout_paise) from public.order_allocations where fpo_id='"+fpo+"'))"));
assert.deepEqual(state,{orders:6,available:0,reserved:60,allocated:60,gross:240000,payout:204000});
const winners=JSON.parse(await run("select json_agg(json_build_object('customer',customer_id,'source',source,'id',id)) from public.orders where fpo_id='"+fpo+"'"));
for(let i=0;i<6;i++){
 const winner=winners.find(x=>x.customer===customers[i]);
 const reply=JSON.parse(await run("select reply from private.wa_relay_outbox where message_hash='"+hashes[i]+"'"));
 assert.match(reply.body,winner?/Test order confirmed/:/Order not placed/);
 assert.equal(await wa(i,"select public.wa_advanced_prepare('"+hashes[i]+"','"+phones[i]+"','button','"+quote[i]+"')"),'f');
}
const webWinner=winners.find(x=>x.source==='web');
if(webWinner){const i=customers.indexOf(webWinner.customer);assert.equal(await web(customers[i],"select public.checkout_order('"+fpo+"','"+cart+"','Race test address','"+keys[i]+"')"),webWinner.id);}
assert.equal(await run("select count(*) from public.orders where fpo_id='"+fpo+"'"),'6');
console.log('PASS 06D: 12 competing customers (6 WhatsApp, 6 web), 60kg stock, exactly 6 orders, no oversell, safe replays; checkout race elapsed ms='+Math.round(performance.now()-raceStart));
// Fixtures intentionally remain only in the guarded, ephemeral CI service.
