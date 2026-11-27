import React,{useEffect,useRef,useState} from 'react';
// Original lightweight implementations of React Bits interaction patterns.
// No animation runtime, remote fonts, stock images, or continuous rendering.
export function Reveal({children,className=''}:{children:React.ReactNode;className?:string}){
 const ref=useRef<HTMLDivElement>(null);
 useEffect(()=>{const el=ref.current;if(!el||!('IntersectionObserver'in window)||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
 const io=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){el.classList.add('revealed');io.disconnect()}},{threshold:.05});
 // Visible by default; reveal is an enhancement, not a requirement to access content.
 io.observe(el);return()=>io.disconnect()},[]);
 return <div ref={ref} className={'reveal '+className}>{children}</div>
}
export function SplitHeading({lines}:{lines:string[]}){return <h1 className="split-heading">{lines.map((line,i)=><span key={i} style={{'--delay':i*100+'ms'} as React.CSSProperties}>{line}{i<lines.length-1?' ':''}</span>)}</h1>}
export function Spotlight({children,className=''}:{children:React.ReactNode;className?:string}){
 const ref=useRef<HTMLElement>(null);
 return <article ref={ref} className={'spotlight '+className} onPointerMove={e=>{if(e.pointerType!=='mouse'||matchMedia('(prefers-reduced-motion: reduce)').matches)return;const el=ref.current;if(!el)return;const rect=el.getBoundingClientRect();el.style.setProperty('--px',e.clientX-rect.left+'px');el.style.setProperty('--py',e.clientY-rect.top+'px')}}>{children}</article>
}
export function CountUp({value,decimals=0,suffix=''}:{value:number;decimals?:number;suffix?:string}){
 const [display,setDisplay]=useState(value);const last=useRef(value);
 useEffect(()=>{const from=last.current;let frame=0;const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;let start:number|undefined;
 if(reduced||!Number.isFinite(value)||from===value){last.current=value;setDisplay(value);return}
 const tick=(now:number)=>{start??=now;const p=Math.min((now-start)/320,1);const next=from+(value-from)*(1-Math.pow(1-p,3));last.current=next;setDisplay(next);if(p<1)frame=requestAnimationFrame(tick)};
 frame=requestAnimationFrame(tick);return()=>cancelAnimationFrame(frame)},[value]);
 const format=(n:number)=>n.toFixed(decimals)+suffix;
 return <><span aria-hidden="true">{format(display)}</span><span className="sr-only">{format(value)}</span></>
}
export function Stepper({steps,current}:{steps:string[];current:number}){return <ol className="ui-stepper" aria-label="Progress">{steps.map((step,i)=><li key={step} className={i<current?'complete':i===current?'current':''} aria-current={i===current?'step':undefined}><span aria-hidden="true">{i<current?'✓':i+1}</span>{step}</li>)}</ol>}
const paths:Record<string,React.ReactNode>={
 farmer:<><path d="M12 21v-9M12 14C4 14 3 9 3 5c7 0 9 3 9 9ZM12 12c0-6 4-9 9-9 0 6-3 9-9 9Z"/></>,
 manager:<><path d="M3 21V9l9-6 9 6v12H3ZM8 21v-7h8v7M3 10h18"/></>,
 customer:<><path d="m4 10 2 10h12l2-10H4ZM8 10l4-7 4 7M9 14v3m6-3v3"/></>,
 home:<><path d="m3 10 9-7 9 7v11H3V10Zm6 11v-7h6v7"/></>,
 profile:<><circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/></>,
 list:<><rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h6"/></>,
 cart:<><path d="M2 3h3l3 13h11l3-10H6"/><circle cx="9" cy="21" r="1"/><circle cx="19" cy="21" r="1"/></>,
 bell:<><path d="M4 17h16l-2-4V9A6 6 0 0 0 6 9v4l-2 4Zm6 3h4"/></>,
 truck:<><path d="M2 5h13v13H2V5Zm13 6h4l3 4v3h-7"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="19" r="2"/></>,
 money:<><path d="M6 4h12M6 9h12M6 4c9 0 9 10 0 10l9 7"/></>,
 users:<><circle cx="9" cy="8" r="3"/><path d="M2 21v-3a7 7 0 0 1 14 0v3m0-16a3 3 0 0 1 0 6m2 3c3 1 4 3 4 7"/></>,
 chat:<><path d="M21 11a9 9 0 0 1-9 9 10 10 0 0 1-4-1l-5 2 1-5a9 9 0 1 1 17-5Z"/><path d="M8 11h8"/></>,
 arrow:<><path d="M4 12h15m-6-6 6 6-6 6"/></>
};
export function Icon({name}:{name:string}){return <svg aria-hidden="true" className="ui-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{paths[name]??paths.list}</svg>}
const tabIcons:Record<string,string>={'Farmer':'farmer','Join FPO':'users','My harvests':'list','Earnings':'money','FPO manager':'home','Notifications':'bell','Members':'users','Harvest review':'list','Inventory':'manager','Delivery':'truck','Market':'customer','Cart':'cart','My orders':'list'};
export function PillNav({tabs,active,label,cartCount,onNavigate,role}:{tabs:string[];active:string;label:(s:string)=>string;cartCount:number;onNavigate:(s:string)=>void;role:string}){
 return <nav className="workspace-nav pill-nav" aria-label={role+' navigation'}>{tabs.map(n=><button key={n} aria-current={active===n?'page':undefined} className={active===n?'active':'quiet'} onClick={()=>onNavigate(n)}><Icon name={tabIcons[n]??'profile'}/><span>{n==='Cart'&&cartCount?`Cart (${cartCount})`:label(n)}</span></button>)}</nav>
}
// Original vector artwork: no borrowed brand photography or deceptive product images.
export function FieldArt(){return <svg className="field-art" viewBox="0 0 640 390" role="img" aria-label="Illustration of cultivated fields at sunrise">
 <defs><linearGradient id="sky" x2="0" y2="1"><stop stopColor="#f8c58a"/><stop offset="1" stopColor="#f3e8bd"/></linearGradient><linearGradient id="land" x2=".7" y2="1"><stop stopColor="#b9cf79"/><stop offset="1" stopColor="#456a43"/></linearGradient><pattern id="grain" width="19" height="17" patternUnits="userSpaceOnUse"><circle cx="3" cy="7" r=".65" fill="#233c2c" opacity=".18"/><circle cx="12" cy="13" r=".8" fill="#f8f3dc" opacity=".22"/></pattern></defs>
 <path fill="url(#sky)" d="M0 0h640v390H0z"/><circle cx="473" cy="87" r="54" fill="#fce7a5"/><path d="M0 190 82 132 166 168 273 99 406 161 521 121 640 181v209H0" fill="#98a65c"/><path d="M0 199Q155 114 307 196T640 179V390H0" fill="#668653"/><path d="M0 248Q190 172 320 232T640 205V390H0" fill="url(#land)"/>
 <g fill="none" strokeLinecap="round"><path d="M-70 303Q205 171 344 237T720 272M-40 350Q218 195 351 261T690 319M-20 395Q218 228 377 295T700 367" stroke="#d8df99" strokeWidth="16"/><path d="M-50 320Q210 187 354 247T680 292M-30 369Q222 216 367 279T680 345M33 417Q220 257 389 317T680 393" stroke="#35533b" strokeWidth="8"/></g>
 <path d="M-10 244q126-46 210-28" stroke="#f5e7ba" strokeWidth="4" fill="none"/><path d="M0 0h640v390H0z" fill="url(#grain)"/><g fill="#253f30"><path d="M70 200l8-30 8 30Zm-8-4 16-37 16 37ZM100 190l7-24 7 24Z"/><path d="M512 190l10-33 10 33Zm-7-6 17-40 17 40Z"/></g></svg>}
const crops: [RegExp,string,string][]=[[/tomat/,'🍅','tomato'],[/carrot/,'🥕','carrot'],[/banana/,'🍌','banana'],[/mango|manogo/,'🥭','mango'],[/potato/,'🥔','potato'],[/rice|wheat/,'🌾','grain'],[/onion/,'🧅','onion'],[/apple/,'🍎','apple'],[/grape/,'🍇','grape'],[/dragon|dargon/,'🌵','dragon'],[/corn|maize/,'🌽','corn'],[/cabbage|lettuce|spinach/,'🥬','leaf']];
export function ProduceArt({crop}:{crop:string}){const match=crops.find(([pattern])=>pattern.test(crop.toLowerCase()));return <div className={'product-icon produce-art '+(match?.[2]??'leaf')} aria-hidden="true"><span>{match?.[1]??'🌿'}</span><i/></div>}
export function Landing({onNavigate}:{onNavigate:(tab:string)=>void}){
 const roles=[{tab:'Farmer',icon:'farmer',title:'Farmer',description:'Join an FPO, submit harvests and see your earnings.',action:'Open farmer dashboard'},{tab:'FPO manager',icon:'manager',title:'FPO manager',description:'Manage farmers, verify crops, inventory and deliveries.',action:'Open FPO dashboard'},{tab:'Market',icon:'customer',title:'Customer',description:'Shop local produce and track your orders.',action:'Open customer dashboard'}];
 return <section className="workspace-home">
  <div className="landing-hero editorial-band"><div className="landing-copy"><span className="eyebrow">GROW TOGETHER · AGRICONNECT</span><SplitHeading lines={['Rooted in agriculture.','Connected by technology.']}/><p>A simpler way for farmers, FPOs and customers to grow together — from the first harvest to the final order.</p><a className="primary-link" href="#workspaces">Get started <Icon name="arrow"/></a></div><div className="landing-art"><FieldArt/><span className="art-caption">FROM THE SOIL · TO OUR COMMUNITY</span></div></div>
  <Reveal className="editorial-band role-band"><span className="eyebrow">ONE PLATFORM · THREE COMMUNITIES</span><h2 id="workspaces" tabIndex={-1}>Choose your dashboard</h2><p>Choose your role to sign in or register.</p><div className="workspace-cards magic-bento">{roles.map(w=><Spotlight className="panel workspace-card" key={w.tab}><div className="workspace-icon"><Icon name={w.icon}/></div><h3>{w.title}</h3><p>{w.description}</p><button onClick={()=>onNavigate(w.tab)}>{w.action}</button></Spotlight>)}</div><p className="workspace-note">Already registered? Your account opens its own dashboard. Each account has one permanent role.</p></Reveal>
  <Reveal className="editorial-band supply-band"><div><span className="eyebrow">A BETTER WAY TO CONNECT</span><h2>Good things grow together.</h2><p>From harvest submission and FPO verification to local shopping and delivery tracking.</p></div><div className="supply-flow">{[{i:'farmer',n:'Harvest'},{i:'manager',n:'Verify'},{i:'customer',n:'Purchase'},{i:'truck',n:'Deliver'}].map((s,i)=><div key={s.n}><Icon name={s.i}/><small>0{i+1}</small><b>{s.n}</b></div>)}</div></Reveal>
  <Reveal className="editorial-band whatsapp-band"><div className="chat-mark"><Icon name="chat"/></div><div><span className="eyebrow">SIMPLE CONVERSATIONS</span><h2>Agriculture meets WhatsApp.</h2><p>Link your account from Profile. Use English, Kannada, Telugu or Hindi with the restricted test assistant.</p></div><button onClick={()=>onNavigate('Account')}>Sign in to link <Icon name="arrow"/></button></Reveal>
 </section>
}
