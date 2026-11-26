import {cryptoSelfTest} from './onboarding-crypto.mjs';
import {pathToFileURL} from 'node:url';
export const candidateHost='agriconnect-q7c2.onrender.com';
export const registryLookup='https://preprod.registry.ondc.org/v2.0/lookup';
export const workbench='https://workbench.ondc.tech/';
export const participantPortal='https://portal.ondc.org/';
// Fixed known public website only. A successful HTTP request is NOT registry approval.
export async function probeWebsite(fetcher=fetch){try{
 const r=await fetcher('https://'+candidateHost+'/',{method:'HEAD',redirect:'error',signal:AbortSignal.timeout(8000),cache:'no-store'});
 return {checked:true,status:r.status,reachable:r.status>=200&&r.status<300,scope:'Public website HTTPS only; callback routing, OCSP, registry eligibility and subscription not verified'};
 }catch{return {checked:true,status:null,reachable:false,scope:'Public website HTTPS request failed; no registry request attempted'};}}
export async function readiness({https=false,fetcher=fetch}={}){
 const local_crypto=cryptoSelfTest();
 const cryptoPassed=local_crypto.ed25519_raw_public_bytes===32&&local_crypto.x25519_der_public_bytes===44&&local_crypto.site_verification_signature_valid&&local_crypto.tampered_request_rejected&&local_crypto.site_verification_meta_valid&&local_crypto.local_x25519_shared_secret_matches;
 return {mode:'LOCAL READINESS ONLY',candidate_subscriber_id:candidateHost,environment:'preprod',domain:'ONDC:RET10',role:'sellerApp',local_crypto,local_crypto_passed:cryptoPassed,website:https?await probeWebsite(fetcher):{checked:false,reachable:null},official:{participant_portal:participantPortal,registry_lookup:registryLookup,protocol_workbench:workbench},gates:{zero_cost_eligibility:'unverified',subscriber_whitelisting:'not_verified',site_verification_deployed:'not_verified',registry_on_subscribe:'not_implemented',registry_lookup:'not_attempted',official_protocol_validation:'not_attempted',durable_transactions_and_external_identity:'not_implemented'},external_traffic_enabled:false,ondc_connected:false,private_keys_persisted:false};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const args=process.argv.slice(2);
 if(args.some(x=>x!=='--https')||args.length>1){console.error('Usage: node ondc/preflight.mjs [--https]');process.exitCode=2;}
 else{const report=await readiness({https:args.includes('--https')});console.log(JSON.stringify(report,null,2));if(!report.local_crypto_passed||args.includes('--https')&&!report.website.reachable)process.exitCode=1;}
}
