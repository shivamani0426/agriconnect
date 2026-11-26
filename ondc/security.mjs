import {createHash,sign,verify} from 'node:crypto';
import {MAX_BODY,ProtocolError} from './protocol.mjs';
const keys=['keyId','algorithm','created','expires','headers','signature'];
const keyPattern=/^[a-z0-9.-]{1,120}\|[A-Za-z0-9_-]{1,80}\|ed25519$/;
const b64=/^[A-Za-z0-9+/]{86}==$/;
export const digest=raw=>createHash('blake2b512').update(raw).digest('base64');
export const signingString=(raw,created,expires)=>Buffer.from('(created): '+created+'\n(expires): '+expires+'\ndigest: BLAKE-512='+digest(raw),'utf8');
function denied(){throw new ProtocolError('LOCAL_AUTH','Authentication failed')}
export function authorization(raw,keyId,privateKey,created,expires){
 if(!Buffer.isBuffer(raw)||!keyPattern.test(keyId)||!Number.isSafeInteger(created)||!Number.isSafeInteger(expires)||expires<=created||expires-created>300)throw new Error('Invalid local signing inputs');
 const signature=sign(null,signingString(raw,created,expires),privateKey).toString('base64');
 return 'Signature keyId="'+keyId+'",algorithm="ed25519",created="'+created+'",expires="'+expires+'",headers="(created) (expires) digest",signature="'+signature+'"';
}
export function verifyAuthorization(raw,header,registry,now,role){
 if(!Buffer.isBuffer(raw)||raw.length===0||raw.length>MAX_BODY||typeof header!=='string'||header.length>2048||!header.startsWith('Signature '))denied();
 const params=Object.create(null);for(const field of header.slice(10).split(',')){const m=/^\s*([A-Za-z]+)="([^"\r\n]*)"\s*$/.exec(field);if(!m||!keys.includes(m[1])||Object.hasOwn(params,m[1]))denied();params[m[1]]=m[2];}
 if(keys.some(k=>!Object.hasOwn(params,k))||!keyPattern.test(params.keyId)||params.algorithm!=='ed25519'||params.headers!=='(created) (expires) digest'||!/^\d{1,10}$/.test(params.created)||!/^\d{1,10}$/.test(params.expires)||!b64.test(params.signature))denied();
 const c=Number(params.created),e=Number(params.expires),t=Math.floor(now/1000);
 if(c>t+30||e<=t||e<=c||e-c>300||c<t-300)denied();
 const entry=registry.get(params.keyId);
 if(!entry||entry.role!==role||entry.subscriber!==params.keyId.split('|')[0]||entry.publicKey?.asymmetricKeyType!=='ed25519')denied();
 const sig=Buffer.from(params.signature,'base64');if(sig.length!==64||sig.toString('base64')!==params.signature)denied();
 if(!verify(null,signingString(raw,c,e),entry.publicKey,sig))denied();
 return entry;
}
