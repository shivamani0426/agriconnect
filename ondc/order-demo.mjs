import {randomUUID} from 'node:crypto';
import {localHarness} from './simulator.mjs';
import {createLocalCommerce,fixtureBackend} from './commerce.mjs';
import {rows,eligibility,FPO_A} from './fixtures.mjs';
const backend=fixtureBackend(rows),h=localHarness({rows,eligibility,readCatalogue:backend.catalogue,commerce:createLocalCommerce({backend,eligibility})});
const tx=randomUUID(),buyer_ref='fixture-buyer-a';
async function send(action,message){const req=action==='search'?h.request(message,{transaction_id:tx}):h.transaction(action,tx,{buyer_ref,...message});const r=await h.receive(h.signed(req,'/'+action));if(!r.callback)throw Error(JSON.stringify(r.ack));h.verifyCallback(r.callback);const m=JSON.parse(r.callback.raw.toString()).message;console.log(action,JSON.stringify(m));return m;}
const catalog=(await send('search',{item:{descriptor:{name:'Tomatoes'}}})).catalog;
const sku=catalog['bpp/providers'].find(p=>p.id===FPO_A).items[0].id;
const q=(await send('select',{order:{provider:{id:FPO_A},items:[{id:sku,quantity:{count:5}}]}})).order;
const i=(await send('init',{quote_id:q.id,fulfillment:{type:'Delivery',mode:'LOCAL_TEST'}})).order;
const o=(await send('confirm',{quote_id:q.id,init_id:i.init_id,total_paise:15000})).order;
if(process.argv.includes('--cancel'))await send('cancel',{order_id:o.id});
else {for(const next of ['packed','out_for_delivery','delivered']){await backend.managerTransition(buyer_ref,tx,FPO_A,next);await send('status',{order_id:o.id});}}
await send('track',{order_id:o.id});
console.log('LOCAL ONLY; no real order, payment, courier, database or network.');
