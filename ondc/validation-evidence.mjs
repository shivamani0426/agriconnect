import {randomUUID,createPublicKey} from 'node:crypto';
import {localHarness} from './simulator.mjs';
import {createLocalCommerce,fixtureBackend} from './commerce.mjs';
import {rows,eligibility,FPO_A} from './fixtures.mjs';
import {BUYER,SELLER,DOMAIN,VERSION,buyerUri,sellerUri,MAX_BODY} from './protocol.mjs';
import {verifyAuthorization} from './security.mjs';

const label='SYNTHETIC LOCAL TRACE ONLY';
const buyer_ref='fixture-buyer-a';
const flows={delivery:['search','select','init','confirm','status','status','status','track'],cancellation:['search','select','init','confirm','cancel','track']};
const fail=m=>{throw Error(m)};
const require=(v,m)=>{if(!v)fail(m);};
const raw64=b=>b.toString('base64');
function from64(s,max){require(typeof s==='string'&&s.length<=Math.ceil(max/3)*4,'Invalid encoded data');const b=Buffer.from(s,'base64');require(b.length<=max&&b.toString('base64')===s,'Noncanonical encoded data');return b;}
const parse=b=>JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(b));
const stock=async backend=>(await backend.catalogue()).find(r=>r.fpo_id===FPO_A&&r.crop==='Tomatoes'&&r.grade==='A').available_kg;
export async function captureFlow(flow){
 require(Object.hasOwn(flows,flow),'Unknown local scenario');
 const backend=fixtureBackend(rows),h=localHarness({rows,eligibility,readCatalogue:backend.catalogue,commerce:createLocalCommerce({backend,eligibility})});
 const tx=randomUUID(),steps=[],initial=await stock(backend);
 async function send(action,message){
  const req=action==='search'?h.request(message,{transaction_id:tx}):h.transaction(action,tx,{buyer_ref,...message});
  const signed=h.signed(req,'/'+action),r=await h.receive(signed);
  require(r.status===200&&r.ack.message.ack.status==='ACK'&&r.callback,'Local scenario failed');
  h.verifyCallback(r.callback);
  steps.push({path:signed.path,request_base64:raw64(signed.raw),request_authorization:signed.header,http_status:r.status,ack:r.ack,callback_path:r.callback.path,callback_base64:raw64(r.callback.raw),callback_authorization:r.callback.header});
  return parse(r.callback.raw).message;
 }
 const cat=(await send('search',{item:{descriptor:{name:'Tomatoes'}}})).catalog;
 const item=cat['bpp/providers'].find(p=>p.id===FPO_A).items[0].id;
 const q=(await send('select',{order:{provider:{id:FPO_A},items:[{id:item,quantity:{count:5}}]}})).order;
 const i=(await send('init',{quote_id:q.id,fulfillment:{type:'Delivery',mode:'LOCAL_TEST'}})).order;
 const beforeConfirm=await stock(backend);
 const o=(await send('confirm',{quote_id:q.id,init_id:i.init_id,total_paise:15000})).order;
 const afterConfirm=await stock(backend);
 if(flow==='cancellation')await send('cancel',{order_id:o.id});
 else for(const next of ['packed','out_for_delivery','delivered']){await backend.managerTransition(buyer_ref,tx,FPO_A,next);await send('status',{order_id:o.id});}
 await send('track',{order_id:o.id});
 return {mode:label,flow,transaction_id:tx,keys:[...h.registry].map(([key_id,k])=>({key_id,public_key_der:raw64(k.publicKey.export({format:'der',type:'spki'}))})),steps,fixture_stock:{before:initial,before_confirm:beforeConfirm,after_confirm:afterConfirm,after_final:await stock(backend),order_count:backend.count()}};
}
// These are self-generated fixture keys, not trusted ONDC registry credentials.
// Reverify signatures at signed creation time for historical local trace integrity only.
function historicalTime(header){const m=/(?:^|,)created="([0-9]{1,10})"/.exec(header??'');require(m,'Missing signed creation time');return Number(m[1])*1000;}
function verifyContext(c,action,tx){require(c&&c.domain===DOMAIN&&c.core_version===VERSION&&c.country==='IND'&&c.city==='std:080'&&c.action===action&&c.transaction_id===tx&&c.bap_id===BUYER&&c.bap_uri===buyerUri,'Context mismatch');if(action!=='search')require(c.bpp_id===SELLER&&c.bpp_uri===sellerUri,'Seller context mismatch');require(typeof c.message_id==='string'&&/^[0-9a-f-]{36}$/.test(c.message_id),'Missing message ID');}
export function validateTrace(trace){
 require(trace?.mode===label&&Object.hasOwn(flows,trace.flow),'Not a supported local trace');
 const expected=flows[trace.flow];
 require(Array.isArray(trace.steps)&&trace.steps.length===expected.length,'Unexpected flow length');
 require(Array.isArray(trace.keys)&&trace.keys.length===2,'Missing local public keys');
 const registry=new Map();
 for(const [subscriber,role,uri,suffix] of [[BUYER,'buyer',buyerUri,'test-buyer'],[SELLER,'seller',sellerUri,'test-seller']]){
  const keyId=subscriber+'|'+suffix+'|ed25519',entry=trace.keys.find(k=>k.key_id===keyId);
  require(entry,'Missing fixture key');
  const publicKey=createPublicKey({key:from64(entry.public_key_der,44),format:'der',type:'spki'});
  require(publicKey.asymmetricKeyType==='ed25519','Wrong key algorithm');
  registry.set(keyId,{subscriber,role,uri,publicKey});
 }
 const tx=trace.transaction_id,seen=new Set(),responses=[],requests=[];
 require(typeof tx==='string'&&/^[0-9a-f-]{36}$/.test(tx),'Missing transaction ID');
 for(let j=0;j<expected.length;j++){
  const s=trace.steps[j],action=expected[j];
  require(s.path==='/'+action&&s.callback_path==='/on_'+action,'Unexpected action sequence');
  require(s.http_status===200&&s.ack?.message?.ack?.status==='ACK','Missing local ACK');
  const req=from64(s.request_base64,MAX_BODY),cb=from64(s.callback_base64,MAX_BODY);
  verifyAuthorization(req,s.request_authorization,registry,historicalTime(s.request_authorization),'buyer');
  verifyAuthorization(cb,s.callback_authorization,registry,historicalTime(s.callback_authorization),'seller');
  const r=parse(req),c=parse(cb);
  verifyContext(r.context,action,tx);verifyContext(c.context,'on_'+action,tx);
  require(r.context.message_id===c.context.message_id&&!seen.has(r.context.message_id),'Message correlation mismatch');
  seen.add(r.context.message_id);requests.push(r.message);responses.push(c.message);
 }
 const products=responses[0].catalog['bpp/providers'],q=responses[1].order,i=responses[2].order,o=responses[3].order;
 const selected=requests[1].order.items[0],product=products.find(p=>p.id===FPO_A)?.items.find(p=>p.id===selected.id);
 require(product?.price?.value==='30.00'&&selected.quantity.count===5&&requests[1].order.provider.id===FPO_A,'Discovery/selection mismatch');
 require(q.provider.id===FPO_A&&q.items.length===1&&q.items[0].id===selected.id&&q.items[0].quantity.count===5&&q.quote.price.value==='150.00','Quote mismatch');
 require(requests[2].quote_id===q.id&&i.id===q.id&&i.quote.price.value==='150.00'&&requests[3].quote_id===q.id&&requests[3].init_id===i.init_id&&requests[3].total_paise===15000,'Checkout correlation mismatch');
 require(o.provider.id===FPO_A&&o.state==='confirmed'&&o.quote.price.value==='150.00'&&o.payment.status==='simulated_paid','Confirmation mismatch');
 for(let j=1;j<requests.length;j++)require(requests[j].buyer_ref===buyer_ref,'Buyer mismatch');
 const states=trace.flow==='delivery'?['packed','out_for_delivery','delivered']:['cancelled'];
 for(let j=0;j<states.length;j++){const idx=4+j,s=responses[idx].order;require(requests[idx].order_id===o.id&&s.id===o.id&&s.provider.id===FPO_A&&s.state===states[j]&&s.quote.price.value==='150.00'&&s.payment.status===(states[j]==='cancelled'?'simulated_refunded':'simulated_paid'),'Order state mismatch');}
 const final=states.at(-1),tracking=responses.at(-1).tracking;
 require(requests.at(-1).order_id===o.id&&tracking.id===o.id&&tracking.status===final&&tracking.mode==='STATUS_ONLY_LOCAL_TEST','Tracking mismatch');
 const s=trace.fixture_stock;require(s?.before==='25.500'&&s.before_confirm===s.before&&s.after_confirm==='20.500'&&s.after_final===(final==='cancelled'?'25.500':'20.500')&&s.order_count===1,'Fixture stock mismatch');
 return {scenario:trace.flow,local_trace_checks_passed:true,signed_pairs:expected.length,final_state:final,fixture_stock_check:'passed',official_validation:'NOT_PERFORMED',ondc_connected:false};
}
