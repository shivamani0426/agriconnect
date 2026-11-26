import {createHash,generateKeyPairSync,randomUUID} from 'node:crypto';
import {DOMAIN,VERSION,BUYER,SELLER,buyerUri,sellerUri,MAX_BODY,ProtocolError,ack,nack,parseSearch,callbackContext} from './protocol.mjs';
import {authorization,verifyAuthorization} from './security.mjs';
import {projectCatalogue} from './catalogue.mjs';
// No HTTP listener, fetch, external registry, credentials or real orders. Callback is returned to the local harness only.
export function createLocalSimulator({registry,signer,readCatalogue,eligibility,clock=()=>Date.now(),maxReceipts=1000}){
 const receipts=new Map();
 return async function receive({path,raw,header}){
  const now=clock();
  try{
   if(!Buffer.isBuffer(raw)||raw.length>MAX_BODY)return {status:413,ack:nack('LOCAL_SIZE','Payload too large')};
   const sender=verifyAuthorization(raw,header,registry,now,'buyer');
   if(path!=='/search')return {status:400,ack:nack('LOCAL_ACTION','Only search is available')};
   const {context,filters}=parseSearch(raw,now,sender);
   for(const [k,r] of receipts)if(r.until<=now)receipts.delete(k);
   const k=JSON.stringify([sender.subscriber,context.message_id]),hash=createHash('sha256').update(raw).digest('hex'),existing=receipts.get(k);
   if(existing){if(existing.hash!==hash)return {status:409,ack:nack('LOCAL_REPLAY','Message ID reused for different content')};if(!existing.complete)return {status:503,ack:nack('LOCAL_PENDING','Message is already processing; retry later')};return {status:200,ack:ack(),duplicate:true};}
   if(receipts.size>=maxReceipts)return {status:503,ack:nack('LOCAL_CAPACITY','Local receipt capacity reached')};
   // Claim before await to prevent parallel duplicate callbacks. On read failure, release for safe retry.
   receipts.set(k,{hash,until:now+360000,complete:false});
   try{
    const catalog=projectCatalogue(await readCatalogue(),eligibility,filters);
    const callback=Buffer.from(JSON.stringify({context:callbackContext(context,now),message:{catalog}}));
    if(callback.length>MAX_BODY)throw new ProtocolError('LOCAL_SIZE','Catalogue exceeds local limit');
    const created=Math.floor(now/1000);
    const header=authorization(callback,signer.keyId,signer.privateKey,created,created+30);
    receipts.get(k).complete=true;
    return {status:200,ack:ack(),callback:{path:'/on_search',raw:callback,header}};
   }catch(e){receipts.delete(k);throw e;}
  }catch(e){const code=e instanceof ProtocolError?e.code:'LOCAL_FAILURE';return {status:code==='LOCAL_AUTH'?401:code==='LOCAL_FAILURE'||code==='LOCAL_CATALOGUE'?503:400,ack:nack(code,code==='LOCAL_FAILURE'?'Local simulation failed':e.message)};}
 };
}
export function localHarness({rows,eligibility,clock=()=>Date.now(),readCatalogue=async()=>structuredClone(rows),maxReceipts}){
 const b=generateKeyPairSync('ed25519'),s=generateKeyPairSync('ed25519'),bk=BUYER+'|test-buyer|ed25519',sk=SELLER+'|test-seller|ed25519';
 const registry=new Map([[bk,{subscriber:BUYER,uri:buyerUri,role:'buyer',publicKey:b.publicKey}],[sk,{subscriber:SELLER,uri:sellerUri,role:'seller',publicKey:s.publicKey}]]);
 const receive=createLocalSimulator({registry,signer:{keyId:sk,privateKey:s.privateKey},readCatalogue,eligibility,clock,maxReceipts});
 const request=(intent={},overrides={})=>({context:{domain:DOMAIN,core_version:VERSION,country:'IND',city:'std:080',action:'search',bap_id:BUYER,bap_uri:buyerUri,transaction_id:randomUUID(),message_id:randomUUID(),timestamp:new Date(clock()).toISOString(),ttl:'PT30S',...overrides},message:{intent}});
 const signed=(value,path='/search')=>{const raw=Buffer.isBuffer(value)?value:Buffer.from(JSON.stringify(value)),t=Math.floor(clock()/1000);return {path,raw,header:authorization(raw,bk,b.privateKey,t,t+60)};};
 const verifyCallback=c=>verifyAuthorization(c.raw,c.header,registry,clock(),'seller');
 return {receive,request,signed,verifyCallback,registry};
}
