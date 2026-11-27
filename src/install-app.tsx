import React,{useEffect,useRef,useState} from 'react';
type InstallEvent=Event & {prompt:()=>Promise<void>;userChoice:Promise<{outcome:'accepted'|'dismissed'}>};
let pending:InstallEvent|null=null;
const listeners=new Set<()=>void>();
const notify=()=>listeners.forEach(fn=>fn());
window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();pending=e as InstallEvent;notify()});
window.addEventListener('appinstalled',()=>{pending=null;notify()});
const standalone=()=>matchMedia('(display-mode: standalone)').matches||(navigator as Navigator & {standalone?:boolean}).standalone===true;
export function InstallApp(){
 const [installed,setInstalled]=useState(standalone),[message,setMessage]=useState('');
 const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const media=matchMedia('(display-mode: standalone)');const update=()=>setInstalled(standalone());
  const done=()=>{setInstalled(true);dialog.current?.close()};listeners.add(update);media.addEventListener('change',update);window.addEventListener('appinstalled',done);
  return()=>{listeners.delete(update);media.removeEventListener('change',update);window.removeEventListener('appinstalled',done)}
 },[]);
 async function install(){
  setMessage('');
  const event=pending;
  if(event){pending=null;try{await event.prompt();const result=await event.userChoice;if(result.outcome==='accepted'){setMessage('Installation requested. Follow your browser prompts.');dialog.current?.showModal();return}}catch{/* show manual instructions */}}
  dialog.current?.showModal();
 }
 if(installed)return null;
 return <><button type="button" className="install-app-button" onClick={()=>void install()}>Install app <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><path d="M12 3v12m-5-5 5 5 5-5M4 17v4h16v-4"/></svg></button>
 <dialog ref={dialog} className="install-app-dialog" aria-labelledby="install-heading"><img src="/icons/icon-192.png" alt="" width="52" height="52"/><h2 id="install-heading">Take AgriConnect with you.</h2>{message&&<p role="status">{message}</p>}<p>Install the app from your browser. No app store download is required.</p><h3>Android · Chrome</h3><p>Open the browser menu and tap Install app or Add to Home screen.</p><h3>iPhone · Safari</h3><p>Tap Share, then Add to Home Screen and Add. Enable Open as Web App if offered.</p><h3>Laptop · Chrome or Edge</h3><p>Use the install icon in the address bar or the browser's install menu.</p><p className="install-note">An internet connection is required for sign-in and live agricultural operations.</p><form method="dialog"><button type="submit">Close</button></form></dialog></>
}
export function registerAppWorker(){
 if(import.meta.env.PROD&&'serviceWorker' in navigator)window.addEventListener('load',()=>{void navigator.serviceWorker.register('/sw.js',{scope:'/'}).catch(()=>console.warn('AgriConnect offline notice unavailable'))},{once:true});
}
