// Local-only subset of ONDC RET10. No networking or database writes.
export const DOMAIN='ONDC:RET10', VERSION='1.2.5', MAX_BODY=65536;
export const BUYER='buyer.agriconnect.invalid', SELLER='seller.agriconnect.invalid';
export const buyerUri='https://'+BUYER+'/ondc', sellerUri='https://'+SELLER+'/ondc';
export const ack=()=>({message:{ack:{status:'ACK'}}});
export const nack=(code,message)=>({message:{ack:{status:'NACK'}},error:{type:'DOMAIN-ERROR',code,message}});
export class ProtocolError extends Error {constructor(code,message){super(message);this.code=code;}}
const fail=(code,message)=>{throw new ProtocolError(code,message)};
export const object=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const id=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
function fields(o,allowed){if(!object(o)||Object.keys(o).some(k=>!allowed.includes(k)))fail('LOCAL_SCHEMA','Unsupported or invalid field');}
export function parseSearch(raw,now,sender){
 let x;try{x=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw))}catch{fail('LOCAL_JSON','Malformed JSON')}
 fields(x,['context','message']);const c=x.context;
 fields(c,['domain','country','city','action','core_version','bap_id','bap_uri','bpp_id','bpp_uri','transaction_id','message_id','timestamp','ttl']);
 if(c.action!=='search')fail('LOCAL_ACTION','Only discovery is implemented in this batch');
 if(c.domain!==DOMAIN||c.core_version!==VERSION||c.country!=='IND'||!['std:080','*'].includes(c.city))fail('LOCAL_CONTEXT','Unsupported domain, version, country or city');
 if(c.bap_id!==sender.subscriber||c.bap_uri!==sender.uri||c.bap_id!==BUYER||c.bap_uri!==buyerUri)fail('LOCAL_IDENTITY','Buyer identity mismatch');
 if((c.bpp_id!==undefined||c.bpp_uri!==undefined)&&(c.bpp_id!==SELLER||c.bpp_uri!==sellerUri))fail('LOCAL_IDENTITY','Seller identity mismatch');
 if(!id(c.transaction_id)||!id(c.message_id))fail('LOCAL_CONTEXT','Invalid transaction or message ID');
 if(typeof c.timestamp!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/.test(c.timestamp)||!Number.isFinite(Date.parse(c.timestamp)))fail('LOCAL_CONTEXT','Invalid timestamp');
 const ttl=/^PT([1-9][0-9]{0,2})S$/.exec(c.ttl??'');const stamp=Date.parse(c.timestamp);
 if(!ttl||Number(ttl[1])>300||stamp>now+30000||stamp+Number(ttl[1])*1000<=now)fail('LOCAL_EXPIRED','Invalid or expired request');
 fields(x.message,['intent']);const intent=x.message.intent;
 // Deliberately reject unknown filters rather than silently broadening search.
 fields(intent,['item','category','provider']);
 if(intent.item!==undefined){fields(intent.item,['descriptor']);fields(intent.item.descriptor,['name']);if(typeof intent.item.descriptor.name!=='string'||!intent.item.descriptor.name.trim()||intent.item.descriptor.name.length>100)fail('LOCAL_SCHEMA','Invalid item name');}
 if(intent.category!==undefined){fields(intent.category,['id']);if(intent.category.id!=='Fruits and Vegetables')fail('LOCAL_SCHEMA','Unsupported category');}
 if(intent.provider!==undefined){fields(intent.provider,['id']);if(!id(intent.provider.id))fail('LOCAL_SCHEMA','Invalid provider');}
 return {context:c,filters:{query:intent.item?.descriptor.name?.trim()??'',provider:intent.provider?.id??null,city:c.city}};
}
export function callbackContext(c,now){return {domain:DOMAIN,country:'IND',city:c.city,action:'on_search',core_version:VERSION,bap_id:c.bap_id,bap_uri:c.bap_uri,bpp_id:SELLER,bpp_uri:sellerUri,transaction_id:c.transaction_id,message_id:c.message_id,timestamp:new Date(now).toISOString(),ttl:'PT30S'};}
