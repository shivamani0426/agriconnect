import {generateKeyPairSync,createPublicKey,sign,verify,diffieHellman,randomUUID,timingSafeEqual} from 'node:crypto';
// Local preflight only. No credential persistence, registry requests or actual subscription.
const edPrefix=Buffer.from('302a300506032b6570032100','hex');
const xPrefix=Buffer.from('302a300506032b656e032100','hex');
function exportDer(key,type,prefix){if(key?.type!=='public'||key.asymmetricKeyType!==type)throw Error('Invalid public key algorithm');const der=key.export({format:'der',type:'spki'});if(der.length!==prefix.length+32||!der.subarray(0,prefix.length).equals(prefix))throw Error('Unexpected public key encoding');return der;}
export const signingPublicKey=key=>exportDer(key,'ed25519',edPrefix).subarray(edPrefix.length).toString('base64');
export const encryptionPublicKey=key=>exportDer(key,'x25519',xPrefix).toString('base64');
function canonical(s,len){if(typeof s!=='string'||s.length!==4*Math.ceil(len/3)||!/^[A-Za-z0-9+/]+={0,2}$/.test(s))throw Error('Invalid key or signature encoding');const b=Buffer.from(s,'base64');if(b.length!==len||b.toString('base64')!==s)throw Error('Invalid key or signature encoding');return b;}
export function importSigningPublicKey(s){return createPublicKey({key:Buffer.concat([edPrefix,canonical(s,32)]),format:'der',type:'spki'});}
export function importEncryptionPublicKey(s){const der=canonical(s,44);if(!der.subarray(0,xPrefix.length).equals(xPrefix))throw Error('Invalid encryption key algorithm');return createPublicKey({key:der,format:'der',type:'spki'});}
function requestBytes(id){if(typeof id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id))throw Error('Invalid request UUID');return Buffer.from(id,'utf8');}
export function siteProof(id,privateKey){if(privateKey?.type!=='private'||privateKey.asymmetricKeyType!=='ed25519')throw Error('Invalid signing private key');return sign(null,requestBytes(id),privateKey).toString('base64');}
export function verifySiteProof(id,signature,publicKey){try{return verify(null,requestBytes(id),importSigningPublicKey(publicKey),canonical(signature,64));}catch{return false;}}
export function siteVerificationHtml(signature){canonical(signature,64);return '<!doctype html>\n<html><head><meta name="ondc-site-verification" content="'+signature+'"></head><body>ONDC Site Verification Page</body></html>\n';}
export function deriveShared(privateKey,encodedPublic){if(privateKey?.type!=='private'||privateKey.asymmetricKeyType!=='x25519')throw Error('Invalid encryption private key');return diffieHellman({privateKey,publicKey:importEncryptionPublicKey(encodedPublic)});}
export function cryptoSelfTest(){const s=generateKeyPairSync('ed25519'),a=generateKeyPairSync('x25519'),b=generateKeyPairSync('x25519'),id=randomUUID(),sp=signingPublicKey(s.publicKey),ep=encryptionPublicKey(a.publicKey),proof=siteProof(id,s.privateKey);
 const sa=deriveShared(a.privateKey,encryptionPublicKey(b.publicKey)),sb=deriveShared(b.privateKey,ep);
 return {ed25519_raw_public_bytes:Buffer.from(sp,'base64').length,x25519_der_public_bytes:Buffer.from(ep,'base64').length,site_verification_signature_valid:verifySiteProof(id,proof,sp),tampered_request_rejected:!verifySiteProof(randomUUID(),proof,sp),site_verification_meta_valid:siteVerificationHtml(proof).includes('name="ondc-site-verification" content="'+proof+'"'),local_x25519_shared_secret_matches:sa.length===32&&timingSafeEqual(sa,sb)};
}
