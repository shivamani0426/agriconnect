// Executed only by the disposable database GitHub Actions job. Never connect to Supabase.
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {localHarness} from '../ondc/simulator.mjs';
import {createLocalCommerce} from '../ondc/commerce.mjs';
import {FPO_A,eligibility} from '../ondc/fixtures.mjs';
import {ProtocolError} from '../ondc/protocol.mjs';
if(process.env.ONDC_DISPOSABLE_CI!=='1'||process.env.GITHUB_ACTIONS!=='true'||process.env.PGDATABASE!=='agricitest'||process.env.PGHOST!=='localhost'||process.env.PGUSER!=='postgres')throw Error('Only disposable GitHub Actions database supported');
function query(sql){const raw=execFileSync('psql',['-X','-qAt','-h','127.0.0.1','-p','5432','-U','postgres','-d','agricitest','-v','ON_ERROR_STOP=1','-c',sql],{encoding:'utf8',timeout:10000,stdio:['ignore','pipe','pipe']}).trim();return raw?JSON.parse(raw):null;}
const literal=x=>"'"+Buffer.from(JSON.stringify(x)).toString('base64')+"'";
const payload=x=>"convert_from(decode("+literal(x)+",'base64'),'UTF8')::jsonb";
const arg=x=>"("+payload(x)+"#>>'{}')";
const backend={
 catalogue:async()=>query("select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.catalogue() c"),
 checkout:async p=>{try{return query('select ondc_fixture.checkout('+payload(p)+')')}catch(e){if(String(e.stderr).includes('Stock or price changed'))throw new ProtocolError('LOCAL_STOCK','Stock or price changed');throw e;}},
 get:async(b,t)=>query('select ondc_fixture.result('+arg(b)+','+arg(t)+'::uuid)'),
 cancel:async(b,t)=>query('select ondc_fixture.transition('+arg(b)+','+arg(t)+"::uuid,'cancelled',false)"),
 managerTransition:async(b,t,n)=>query('select ondc_fixture.transition('+arg(b)+','+arg(t)+'::uuid,'+arg(n)+',true)')
};
const h=localHarness({rows:[],eligibility,readCatalogue:backend.catalogue,commerce:createLocalCommerce({backend,eligibility})});
const tx=randomUUID(),t2=randomUUID(),buyer='fixture-buyer-a',b2='fixture-buyer-b';
async function send(action,t,b,message){const r=await h.receive(h.signed(h.transaction(action,t,{buyer_ref:b,...message}),'/'+action));if(!r.callback)return r.ack;h.verifyCallback(r.callback);return JSON.parse(r.callback.raw.toString()).message;}
const discovery=await h.receive(h.signed(h.request({item:{descriptor:{name:'Tomatoes'}}})));h.verifyCallback(discovery.callback);
const item=JSON.parse(discovery.callback.raw.toString()).message.catalog['bpp/providers'][0].items[0].id;
async function ready(t,b,count){const q=(await send('select',t,b,{order:{provider:{id:FPO_A},items:[{id:item,quantity:{count}}]}})).order;assert.ok(q);const i=(await send('init',t,b,{quote_id:q.id,fulfillment:{type:'Delivery',mode:'LOCAL_TEST'}})).order;return {quote_id:q.id,init_id:i.init_id,total_paise:count*3000};}
const a=await ready(tx,buyer,20),b=await ready(t2,b2,15);
const order=(await send('confirm',tx,buyer,a)).order;assert.ok(order);assert.equal(order.quote.price.value,'600.00');assert.equal((await send('confirm',tx,buyer,a)).order.id,order.id);
assert.equal((await send('confirm',t2,b2,b)).error.code,'LOCAL_STOCK');
assert.deepEqual(query("select jsonb_build_object('orders',count(*),'gross',sum(total_paise),'pool',sum(farmer_pool_paise)) from public.orders"),{orders:1,gross:60000,pool:51000});
assert.deepEqual(query("select jsonb_build_object('lots',count(*),'qty',sum(quantity_kg),'payout',sum(payout_paise)) from public.order_allocations"),{lots:2,qty:20,payout:51000});
assert.deepEqual(query("select jsonb_build_object('available',sum(available_kg),'reserved',sum(reserved_kg)) from public.inventory_lots"),{available:10,reserved:20});
assert.equal((await send('status',tx,b2,{order_id:order.id})).error.code,'LOCAL_ORDER');
for(const state of ['packed','out_for_delivery','delivered']){await backend.managerTransition(buyer,tx,state);assert.equal((await send('status',tx,buyer,{order_id:order.id})).order.state,state);}
assert.equal((await send('cancel',tx,buyer,{order_id:order.id})).error.code,'LOCAL_STATE');
const t3=randomUUID(),m=await ready(t3,b2,5),o=(await send('confirm',t3,b2,m)).order;assert.ok(o);
assert.equal((await send('cancel',t3,b2,{order_id:o.id})).order.payment.status,'simulated_refunded');
assert.equal((await send('cancel',t3,b2,{order_id:o.id})).order.state,'cancelled');
assert.deepEqual(query("select jsonb_build_object('available',sum(available_kg),'reserved',sum(reserved_kg)) from public.inventory_lots"),{available:10,reserved:0});
assert.deepEqual(query("select jsonb_build_object('events',count(*),'orders',count(distinct external_id)) from private.integration_events where event_type='local_protocol_checkout'"),{events:2,orders:2});
console.log('PASS: signed local ONDC discovery/checkout through actual SQL engine, two-farmer allocation, payout, oversell rollback, idempotency, buyer isolation, delivery and cancellation stock restoration');
