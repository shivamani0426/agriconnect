import React,{useState,useEffect,useRef} from 'react';
import {client,result} from './api';
type Status={status:'linked'|'pending'|'unlinked';last4?:string;expires_at?:string};
type Ticket={code:string;expires_at:string};
export function WhatsAppLink(){
 const [status,setStatus]=useState<Status|null>(null),[ticket,setTicket]=useState<Ticket|null>(null),[phone,setPhone]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const mounted=useRef(true);
 async function refresh(){const s=await result(client().rpc('wa_status')) as Status;if(mounted.current){setStatus(s);if(s.status!=='pending')setTicket(null);}}
 useEffect(()=>{mounted.current=true;refresh().catch(()=>{if(mounted.current)setError('Unable to load WhatsApp status. Refresh to try again.');});return()=>{mounted.current=false;};},[]);
 async function run(fn:()=>Promise<void>){if(busy)return;setBusy(true);setError('');try{await fn();}catch(e){if(mounted.current)setError(e instanceof Error?e.message:'Unable to complete request.');}finally{if(mounted.current)setBusy(false);}}
 return <section className="panel"><h2>WhatsApp account</h2><p>Test numbers only. Your permanent account role stays the same. Send HI to choose your language and use simple numbered menus. Confirm orders and harvests with buttons. Linked customers can also send SHOP to the test number to place simulated orders. Linked farmers can send FPOS to submit text-only harvests for FPO approval. Photos can be uploaded with a new website harvest instead. Linked FPO managers can send ALERTS to view unread activity and current workload. Farmer and manager ordering is disabled.</p>
 {error&&<p role="alert">{error}</p>}
 <p role="status">{status?.status==='linked'?'Linked · number ending '+status.last4:status?.status==='pending'?'Awaiting WhatsApp confirmation · number ending '+status.last4:status?.status==='unlinked'?'Not linked':'Checking status…'}</p>
 <button className="quiet" disabled={busy} onClick={()=>void run(refresh)}>Refresh linking status</button>
 {status&&status.status!=='linked'&&<form onSubmit={e=>{e.preventDefault();void run(async()=>{const digits=phone.trim().replace(/^\+/,'');if(!/^[1-9][0-9]{6,14}$/.test(digits))throw Error('Enter country code and phone number, digits only.');const t=await result(client().rpc('wa_begin',{p_phone:digits})) as Ticket;if(mounted.current)setTicket(t);await refresh();});}}><label>WhatsApp phone number (with country code)<input type="tel" value={phone} onChange={e=>setPhone(e.target.value)} placeholder="91XXXXXXXXXX" autoComplete="tel" required maxLength={16}/></label><label className="checkline"><input type="checkbox" required/>I consent to linking this test number to my account.</label><button disabled={busy}>Generate linking code</button></form>}
 {ticket&&status?.status==='pending'&&<div><p>Send this exact message to AgriConnect test number +1 (555) 191-4596 within 10 minutes. Do not share this code with anyone else.</p><code style={{overflowWrap:'anywhere'}}>LINK {ticket.code}</code><p>Expires {new Date(ticket.expires_at).toLocaleTimeString()}</p><button className="quiet" disabled={busy} onClick={()=>void run(async()=>{await navigator.clipboard.writeText('LINK '+ticket.code);})}>Copy linking message</button></div>}
 {status&&status.status!=='unlinked'&&<button className="quiet" disabled={busy} onClick={()=>{if(window.confirm('Remove WhatsApp connection and any pending code?'))void run(async()=>{await result(client().rpc('wa_unlink'));if(mounted.current)setTicket(null);await refresh();});}}>{status.status==='linked'?'Unlink WhatsApp':'Cancel linking'}</button>}
 </section>;
}
