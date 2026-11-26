import {randomUUID} from 'node:crypto';
import {ProtocolError,object,BUYER} from './protocol.mjs';
import {projectCatalogue,sku} from './catalogue.mjs';
const fail=(code,message)=>{throw new ProtocolError(code,message)};
const fields=(o,allowed)=>{if(!object(o)||Object.keys(o).some(k=>!allowed.includes(k)))fail('LOCAL_SCHEMA','Unsupported or invalid transaction field');};
const uid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const money=n=>String(Math.floor(n/100))+'.'+String(n%100).padStart(2,'0');
const clone=structuredClone;
export const LOCAL_BUYERS=new Set(['fixture-buyer-a','fixture-buyer-b']);
// Local buyer_ref is an assertion made by the signed synthetic BAP, not a production end-user identity proof.
export function createLocalCommerce({backend,eligibility,clock=()=>Date.now(),quoteMs=120000,maxTransactions=1000}){
 const sessions=new Map(),busy=new Set();
 const unavailable=()=>fail('LOCAL_ORDER','Order or transaction unavailable');
 const quoteView=s=>({id:s.quoteId,provider:{id:s.provider},items:s.items.map(x=>({id:x.id,quantity:{count:x.quantity_kg},price:{currency:'INR',value:money(x.price_paise_per_kg)}})),quote:{price:{currency:'INR',value:money(s.total)},expires_at:new Date(s.expiry).toISOString()},payment:{type:'SIMULATED'},fulfillment:{type:'Delivery',mode:'LOCAL_TEST'}});
 function view(o){return {order:{id:o.id,state:o.status,provider:{id:o.provider},quote:{price:{currency:'INR',value:money(o.total_paise)}},payment:{status:o.payment_status,type:'SIMULATED'}}};}
 async function current(s){const o=await backend.get(s.buyer,s.transaction);if(!o||o.id!==s.orderId)unavailable();return o;}
 function checkFresh(s){if(s.expiry<=clock())fail('LOCAL_QUOTE_EXPIRED','Quote expired; select again');}
 return {async handle(action,c,m,now){
  if(!object(m)||!LOCAL_BUYERS.has(m.buyer_ref)||c.bap_id!==BUYER)fail('LOCAL_BUYER','Unknown local buyer');
  const buyer=m.buyer_ref,k=JSON.stringify([c.bap_id,c.transaction_id]);
  if(busy.has(k))fail('LOCAL_PENDING','Transaction busy; retry later');
  busy.add(k);
  try{
   let s=sessions.get(k);
   if(s&&s.buyer!==buyer)unavailable();
   if(action==='select'){
    fields(m,['buyer_ref','order']);fields(m.order,['provider','items']);fields(m.order.provider,['id']);
    if(s?.orderId)fail('LOCAL_STATE','Order already confirmed');
    if(!uid(m.order.provider.id)||!Array.isArray(m.order.items)||m.order.items.length<1||m.order.items.length>20)fail('LOCAL_SCHEMA','Invalid cart');
    const provider=m.order.provider.id,rows=await backend.catalogue(),catalog=projectCatalogue(rows,eligibility,{query:'',provider,city:c.city});
    const permitted=new Set(catalog['bpp/providers'].flatMap(p=>p.items.map(i=>i.id)));
    const seen=new Set(),items=[];let total=0;
    for(const line of m.order.items){
     fields(line,['id','quantity']);fields(line.quantity,['count']);
     if(typeof line.id!=='string'||!/^sku-[0-9a-f]{32}$/.test(line.id)||seen.has(line.id)||!Number.isInteger(line.quantity.count)||line.quantity.count<1||line.quantity.count>10000)fail('LOCAL_SCHEMA','Invalid or duplicate cart line');
     seen.add(line.id);const r=rows.find(x=>x.fpo_id===provider&&sku(x.fpo_id,x.crop,x.grade,x.price_paise_per_kg)===line.id);
     if(!r||!permitted.has(line.id)||Number(r.available_kg)<line.quantity.count)fail('LOCAL_STOCK','Stock or item unavailable');
     const q=line.quantity.count;total+=q*r.price_paise_per_kg;
     items.push({id:line.id,crop:r.crop,grade:r.grade,price_paise_per_kg:r.price_paise_per_kg,quantity_kg:q});
    }
    if(!Number.isSafeInteger(total)||total<=0)fail('LOCAL_SCHEMA','Invalid total');
    if(!s&&sessions.size>=maxTransactions)fail('LOCAL_CAPACITY','Transaction capacity reached; restart local harness');
    s={buyer,transaction:c.transaction_id,provider,items,total,quoteId:randomUUID(),expiry:clock()+quoteMs,phase:'selected'};sessions.set(k,s);
    return {order:quoteView(s)};
   }
   if(!s)unavailable();
   if(action==='init'){
    fields(m,['buyer_ref','quote_id','fulfillment']);fields(m.fulfillment,['type','mode']);
    if(s.orderId||m.quote_id!==s.quoteId||m.fulfillment.type!=='Delivery'||m.fulfillment.mode!=='LOCAL_TEST')fail('LOCAL_STATE','Invalid quote or fulfillment');
    checkFresh(s);s.initId??=randomUUID();s.phase='initialized';
    return {order:{...quoteView(s),init_id:s.initId}};
   }
   if(action==='confirm'){
    fields(m,['buyer_ref','quote_id','init_id','total_paise']);
    if(s.phase!=='initialized'&&s.phase!=='confirmed'||m.quote_id!==s.quoteId||m.init_id!==s.initId||m.total_paise!==s.total)fail('LOCAL_STATE','Confirmation does not match initialized quote');
    if(s.orderId)return view(await current(s));
    checkFresh(s);
    // Backend must atomically revalidate prices and stock, allocate and deduplicate by buyer+transaction.
    const o=await backend.checkout({buyer,transaction:s.transaction,provider:s.provider,items:s.items.map(({id,...i})=>i),total_paise:s.total});
    if(!o||!uid(o.id)||o.provider!==s.provider||o.total_paise!==s.total||o.status!=='confirmed')fail('LOCAL_FAILURE','Unexpected checkout result');
    s.orderId=o.id;s.phase='confirmed';return view(o);
   }
   if(!['status','track','cancel'].includes(action))fail('LOCAL_ACTION','Unsupported transaction action');
   fields(m,['buyer_ref','order_id']);
   if(!s.orderId||m.order_id!==s.orderId)unavailable();
   const o=await current(s);
   if(action==='status')return view(o);
   if(action==='track')return {tracking:{id:o.id,status:o.status,mode:'STATUS_ONLY_LOCAL_TEST'}};
   if(o.status==='cancelled')return view(o);
   if(o.status!=='confirmed')fail('LOCAL_STATE','Cancellation not allowed at current status');
   return view(await backend.cancel(buyer,s.transaction));
  }finally{busy.delete(k);}
 }};
}
// Synthetic in-memory fixture only. It is NOT the production allocation algorithm.
export function fixtureBackend(input){
 const stock=clone(input),orders=new Map();
 const key=(buyer,transaction)=>JSON.stringify([buyer,transaction]);
 const get=(buyer,transaction)=>orders.get(key(buyer,transaction));
 const view=o=>o?clone(o):null;
 const transition=(o,next,manager)=>{
  if(!o)fail('LOCAL_ORDER','Order unavailable');
  const allowed=next==='cancelled'?(o.status==='confirmed'||manager&&o.status==='packed'):manager&&({confirmed:'packed',packed:'out_for_delivery',out_for_delivery:'delivered'}[o.status]===next);
  if(!allowed)fail('LOCAL_STATE','Invalid lifecycle transition');
  if(next==='cancelled'){for(const l of o.items){const r=stock.find(x=>x.fpo_id===o.provider&&x.crop===l.crop&&x.grade===l.grade&&x.price_paise_per_kg===l.price_paise_per_kg);if(!r)fail('LOCAL_FAILURE','Fixture stock missing');r.available_kg=(Number(r.available_kg)+l.quantity_kg).toFixed(3);}o.payment_status='simulated_refunded';}
  o.status=next;return view(o);
 };
 return {
  catalogue:async()=>clone(stock),
  checkout:async({buyer,transaction,provider,items,total_paise})=>{
   const k=key(buyer,transaction),prior=orders.get(k);if(prior){if(prior.provider!==provider||prior.total_paise!==total_paise||JSON.stringify(prior.items)!==JSON.stringify(items))fail('LOCAL_STATE','Transaction conflict');return view(prior);}
   const picks=items.map(l=>({l,r:stock.find(x=>x.fpo_id===provider&&x.crop===l.crop&&x.grade===l.grade&&x.price_paise_per_kg===l.price_paise_per_kg)}));
   if(picks.some(({l,r})=>!r||Number(r.available_kg)<l.quantity_kg))fail('LOCAL_STOCK','Stock or price changed');
   for(const {l,r} of picks)r.available_kg=(Number(r.available_kg)-l.quantity_kg).toFixed(3);
   const o={id:randomUUID(),provider,items:clone(items),total_paise,status:'confirmed',payment_status:'simulated_paid'};orders.set(k,o);return view(o);
  },
  get:async(b,t)=>view(get(b,t)),cancel:async(b,t)=>transition(get(b,t),'cancelled',false),
  // Simulates a trusted FPO manager, intentionally not an incoming ONDC route.
  managerTransition:async(b,t,provider,next)=>{const o=get(b,t);if(!o||o.provider!==provider)fail('LOCAL_ORDER','FPO mismatch');return transition(o,next,true);},
  count:()=>orders.size
 };
}
