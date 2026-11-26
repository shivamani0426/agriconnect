import {captureFlow,validateTrace} from './validation-evidence.mjs';
import {readiness} from './preflight.mjs';
import {pathToFileURL} from 'node:url';
// No input flags can mark official gates passed. This report is strictly local.
export const gaps=Object.freeze([
 ['04H','Approved legal identity, free eligibility, accepted hostname and preprod whitelisting'],
 ['04H','Dynamic HTTPS callback, securely stored real keys, site proof, registry challenge and verified lookup'],
 ['04I','Confirm RET10 version/flows in Workbench; official schema validation of complete payloads'],
 ['04I','Full and incremental catalogue, serviceability, fulfilment/location, tax and statutory metadata'],
 ['04I','Standard delivery flow 004: unsolicited on_status and agent-assigned/picked events; routing-specific semantics'],
 ['04I','Official cancellation/rejection/recovery/return and other mandatory scenarios per participant profile'],
 ['04J','Durable buyer/order identity, receipts, transaction mapping and callback outbox; ingress authorization and retry policy'],
 ['04J','External buyer test discovery and order; real shared-engine test reconciliation with correlated independent logs'],
 ['04J','Compliance, grievance, settlement, privacy and dependency security review; official signoff']
].map(([pipeline,requirement])=>Object.freeze({pipeline,requirement,status:'OPEN'})));
export async function localAudit(){
 const r=await readiness();
 const scenarios=await Promise.all(['delivery','cancellation'].map(async flow=>validateTrace(await captureFlow(flow))));
 return {mode:'LOCAL AUDIT ONLY',local_crypto_passed:r.local_crypto_passed,scenarios,local_audit_passed:r.local_crypto_passed&&scenarios.every(s=>s.local_trace_checks_passed),open_external_gates:gaps,official_protocol_validation:'NOT_PERFORMED',official_network_test:'NOT_PERFORMED',external_traffic_enabled:false,ondc_connected:false,release_ready:false};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 try{
  const args=process.argv.slice(2);
  if(args.length===0){const r=await localAudit();console.log(JSON.stringify(r,null,2));if(!r.local_audit_passed)process.exitCode=1;}
  else if(args.length===2&&args[0]==='--trace'&&['delivery','cancellation'].includes(args[1])){const trace=await captureFlow(args[1]);validateTrace(trace);console.log(JSON.stringify(trace,null,2));}
  else{console.error('Usage: node ondc/final-audit.mjs [--trace delivery|cancellation]');process.exitCode=2;}
 }catch(e){console.error('Local audit failed: '+e.message);process.exitCode=1;}
}
