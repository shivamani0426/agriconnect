// Explicit provider rejection can be retried; ambiguous network failures cannot.
export function classifyResponse(status,code){
 if(status>=200&&status<300)return 'accepted';
 if(status===401||status===403||code===190)return 'credentials';
 if(status===429)return 'retryable';
 return 'rejected';
}
export async function relayWithRetry(send,{sleep=ms=>new Promise(r=>setTimeout(r,ms)),maxAttempts=2,report=()=>{}}={}){
 for(let attempt=1;attempt<=maxAttempts;attempt++){
  let result;
  try{result=await send();}catch{report('relay_unknown');return {state:'unknown',attempts:attempt};}
  if(result.state!=='retryable'||attempt===maxAttempts)return {...result,attempts:attempt};
  report('relay_rate_limited');
  await sleep(1000);
 }
}
