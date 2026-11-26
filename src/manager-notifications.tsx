import React,{useState,useEffect,useRef} from 'react';
import {client,result} from './api';
type Alert={id:string;kind:'membership_requested'|'harvest_submitted'|'order_confirmed'|'order_cancelled';fpo_id:string;fpo_name:string;created_at:string};
type Inbox={unread:number;pending_members:number;pending_harvests:number;open_orders:number;alerts:Alert[]};
const labels:Record<Alert['kind'],string>={membership_requested:'New membership request',harvest_submitted:'New harvest submitted',order_confirmed:'New test order',order_cancelled:'Test order cancelled'};
export function ManagerNotifications(){
 const [inbox,setInbox]=useState<Inbox|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const alive=useRef(true),running=useRef(false);
 async function load(){const data=await result(client().rpc('manager_inbox')) as Inbox;if(alive.current)setInbox(data);}
 async function run(action?:()=>Promise<void>){if(running.current)return;running.current=true;setBusy(true);setError('');try{if(action)await action();await load();}catch{if(alive.current){setInbox(null);setError('Unable to refresh notifications. Please try again.');}}finally{running.current=false;if(alive.current)setBusy(false);}}
 useEffect(()=>{alive.current=true;void run();return()=>{alive.current=false;};},[]);
 return <section className="panel"><div className="sectionhead"><div><h2>FPO notifications</h2><p>New activity across your currently managed FPOs. Alerts are recorded automatically; refresh to retrieve them.</p></div><button className="quiet" disabled={busy} onClick={()=>void run()}>Refresh notifications</button></div>
 {error&&<p role="alert">{error}</p>}
 {inbox?<><div className="stats"><div><small>Pending memberships</small><b>{inbox.pending_members}</b></div><div><small>Pending harvests</small><b>{inbox.pending_harvests}</b></div><div><small>Open test orders</small><b>{inbox.open_orders}</b></div></div><h3>{inbox.unread} unread alerts</h3><p>Showing up to 30 unread alerts. Marking an alert read does not resolve the underlying work.</p>{inbox.alerts.length===0?<p>No unread alerts.</p>:inbox.alerts.map(a=><div className="item" key={a.id}><div><b>{labels[a.kind]}</b><small>{a.fpo_name} · {new Date(a.created_at).toLocaleString()}</small></div><button className="quiet" disabled={busy} onClick={()=>void run(async()=>{if(!await result(client().rpc('manager_read',{p_id:a.id})))throw Error('Alert unavailable');})}>Mark read</button></div>)}</>:<p>{busy?'Loading notifications…':'Notifications unavailable.'}</p>}
 <p>Linked managers can send ALERTS to the WhatsApp test number. No automatic outbound WhatsApp messages are sent.</p></section>;
}
