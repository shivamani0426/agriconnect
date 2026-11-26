import {localHarness} from './simulator.mjs';
import {rows,eligibility} from './fixtures.mjs';
const h=localHarness({rows,eligibility});
const intent=process.argv[2]?{item:{descriptor:{name:process.argv[2]}}}:{};
const result=await h.receive(h.signed(h.request(intent)));
if(!result.callback){console.error(JSON.stringify(result.ack,null,2));process.exitCode=1;}
else{h.verifyCallback(result.callback);console.log(JSON.stringify({mode:'LOCAL SIMULATION ONLY',http_status:result.status,ack:result.ack,signature_verified:true,on_search:JSON.parse(result.callback.raw.toString('utf8'))},null,2));}
