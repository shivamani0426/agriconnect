import React,{useEffect,useRef,useState} from 'react';
import {SunsetScene} from './sunset-scene';
// Original lightweight implementations of React Bits interaction patterns.
// No animation runtime, remote fonts, stock images, or continuous rendering.
export function Reveal({children,className=''}:{children:React.ReactNode;className?:string}){
 const ref=useRef<HTMLDivElement>(null);
 useEffect(()=>{const el=ref.current;if(!el||!('IntersectionObserver'in window)||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
 // Never conceal visible content or keyboard-focused controls.
 const io=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){el.classList.remove('reveal-pending');el.classList.add('revealed');io.disconnect()}},{threshold:.03});
 if(el.getBoundingClientRect().top>window.innerHeight)el.classList.add('reveal-pending');
 const show=()=>{el.classList.remove('reveal-pending');io.disconnect()};
 el.addEventListener('focusin',show);io.observe(el);return()=>{io.disconnect();el.removeEventListener('focusin',show);el.classList.remove('reveal-pending')}},[]);
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
// Original, locally rendered 3D-look artwork. Static SVG lighting plus CSS depth,
// rather than a GPU-heavy continuous WebGL scene. All details are decorative.
function Plant({x,y,size=1}:{x:number;y:number;size?:number}){return <g transform={'translate('+x+' '+y+') scale('+size+')'}><path d="M0 1 Q-2 -13 0 -24" fill="none" stroke="#4a6530" strokeWidth="2.5" strokeLinecap="round"/><path d="M0 -9Q-20 -5 -19 -20Q-3 -23 0 -9" fill="#6d9d3c"/><path d="M0 -15Q4 -31 17 -29Q22 -16 0 -15" fill="#b4d35e"/><path d="M0 -21Q-13 -35 -4 -41Q7 -39 0 -21" fill="#8bb047"/><path d="M-1 -10L-12 -17M2 -16L12 -24" fill="none" stroke="#d0e58e" strokeWidth=".7"/></g>}
export function FieldArt(){
 const id=React.useId().replace(/:/g,'');
 const fill=(name:string)=>'url(#'+id+name+')';
 return <svg className="field-art" viewBox="0 0 640 480" role="img" aria-label="Dimensional illustration of a floating farm with crop rows, trees and a barn">
 <defs>
  <linearGradient id={id+'soil'} x1="0" y1="0" x2=".8" y2="1"><stop stopColor="#a77946"/><stop offset="1" stopColor="#4c3229"/></linearGradient>
  <linearGradient id={id+'soil2'} x2="1" y2="1"><stop stopColor="#cb9b63"/><stop offset="1" stopColor="#76533a"/></linearGradient>
  <linearGradient id={id+'grass'} x2=".65" y2="1"><stop stopColor="#c0dc81"/><stop offset=".55" stopColor="#88b05e"/><stop offset="1" stopColor="#497643"/></linearGradient>
  <linearGradient id={id+'row'} x2=".7" y2="1"><stop stopColor="#af8050"/><stop offset="1" stopColor="#63472b"/></linearGradient>
  <linearGradient id={id+'roof'} x2="1" y2="1"><stop stopColor="#d9a77b"/><stop offset="1" stopColor="#914637"/></linearGradient>
  <radialGradient id={id+'tree'} cx=".35" cy=".25" r=".8"><stop stopColor="#c5e184"/><stop offset=".5" stopColor="#78a44d"/><stop offset="1" stopColor="#335f35"/></radialGradient>
  <radialGradient id={id+'shadow'}><stop stopColor="#122f1b" stopOpacity=".3"/><stop offset="1" stopColor="#122f1b" stopOpacity="0"/></radialGradient>
  <linearGradient id={id+'water'} x2="1" y2=".5"><stop stopColor="#b4d8c9"/><stop offset="1" stopColor="#508e84"/></linearGradient>
 </defs>
 <ellipse cx="322" cy="423" rx="248" ry="45" fill={fill('shadow')}/>
 <g className="farm-island">
  <path d="M62 216 311 95 581 221 581 276Q576 290 564 296L337 419Q324 426 310 419L80 298Q62 290 62 274Z" fill={fill('soil')}/>
  <path d="M62 216 325 347 325 423 80 298Q62 290 62 274Z" fill={fill('soil2')}/>
  <path d="M325 347 581 221 581 276Q576 290 564 296L337 419Q327 425 325 423Z" fill={fill('soil')}/>
  <path d="M67 264 324 395 573 268M73 281 324 409 565 284" stroke="#e1b078" strokeOpacity=".22" strokeWidth="2" fill="none"/>
  <path d="M62 216 311 95 581 221 325 351Z" fill={fill('grass')} stroke="#c5db90" strokeWidth="2" strokeLinejoin="round"/>
  <path d="M62 216 325 351 581 221 581 233 325 365 62 229Z" fill="#547944"/>
  <path d="M108 217 304 122 461 195 267 295Z" fill="#c9d99b" opacity=".75"/>
  {Array.from({length:6},(_,i)=>{const x=127+i*25,y=217+i*12;return <g key={i}><path d={'M'+x+' '+y+'l183 -88 16 8 -183 89Z'} fill={fill('row')}/>{Array.from({length:6},(_,j)=><Plant key={j} x={x+10+j*30} y={y-2-j*14.5} size={.58+j*.035}/>)}</g>})}
  <path d="M277 301 470 200 500 214 309 317Z" fill="#e0c69b"/><path d="M317 320 505 222 531 234 344 332Z" fill="#d8b783"/>
  <path d="M405 266Q446 239 481 252Q514 267 488 281L450 300Q421 309 396 291Q380 279 405 266" fill="#395f3b" opacity=".35"/>
  <path d="M400 260Q445 236 478 249Q512 261 485 275L448 294Q420 303 396 285Q381 273 400 260" fill={fill('water')} stroke="#c1dbaf" strokeWidth="3"/><path d="M418 265q15-6 32-4m-30 14q17-4 28-3" stroke="#e4f3dc" strokeOpacity=".75" fill="none" strokeWidth="2"/>
  <g transform="translate(360 98)"><path d="M-10 109 59 71 121 101 52 138Z" fill="#34512e" opacity=".25"/><path d="M0 43 60 14 112 42 112 98 52 128 0 100Z" fill="#efdcba"/><path d="M52 70 112 42 112 98 52 128Z" fill="#c19e73"/><path d="M0 43 27 4 80-23 60 14 52 70Z" fill="#f2c89d"/><path d="M27 4 80-23 130 27 76 55Z" fill={fill('roof')}/><path d="M-7 44 27 4 76 55 52 70Z" fill="#d99a6a"/><path d="M11 73 36 85 36 117 11 105Z" fill="#56634a"/><path d="M69 81 95 68 95 85 69 98Z" fill="#526b61"/><path d="M82 76v15" stroke="#ead7b4" strokeWidth="2"/></g>
  {[[94,209,.72],[330,119,.66],[527,202,.96],[554,220,.68],[358,322,.7]].map(([x,y,z],i)=><g key={i} transform={'translate('+x+' '+y+') scale('+z+')'}><ellipse cx="9" cy="6" rx="29" ry="13" fill="#28452b" opacity=".2"/><path d="M-4 -4 -3 -47 5 -47 6 -4Z" fill="#856540"/><circle cx="-11" cy="-46" r="25" fill={fill('tree')}/><circle cx="9" cy="-59" r="29" fill={fill('tree')}/><circle cx="24" cy="-38" r="21" fill={fill('tree')}/></g>)}
 </g>
 <g className="floating-seed seed-one" opacity=".85"><circle cx="100" cy="81" r="4" fill="#a9bd69"/><path d="M76 111q14-22 30-11-5 19-30 11" fill="#9abe60"/></g><g className="floating-seed seed-two"><path d="M520 68q19-22 33-9-11 20-33 9" fill="#c7d879"/><circle cx="553" cy="96" r="3" fill="#e3d4a7"/></g>
 </svg>
}
const crops: [RegExp,string,string][]=[[/tomat/,'tomato','Tomato'],[/carrot/,'carrot','Carrot'],[/banana/,'banana','Banana'],[/mango|manogo/,'mango','Mango'],[/potato/,'potato','Potato'],[/rice|wheat/,'grain','Grain'],[/onion/,'onion','Onion'],[/apple/,'apple','Apple'],[/grape/,'grape','Grape'],[/dragon|dargon/,'dragon','Dragon fruit'],[/corn|maize/,'corn','Corn'],[/cabbage|lettuce|spinach/,'leaf','Leaf']];
export function ProduceArt({crop}:{crop:string}){
 const kind=crops.find(([pattern])=>pattern.test(crop.toLowerCase()))?.[1]??'leaf';
 const id=React.useId().replace(/:/g,'');const color=({tomato:['#ff9a71','#d94032','#8a1d22'],apple:['#f29b83','#c73e40','#772b38'],carrot:['#ffd280','#e78527','#a85218'],banana:['#fff6aa','#ecc650','#a68b26'],mango:['#ffe68a','#f8b43e','#d07727'],potato:['#e5c49c','#b69464','#795634'],onion:['#e7badc','#ae739d','#76466a'],grape:['#c8a7df','#8963a8','#51356f'],dragon:['#f9a2bf','#d65386','#9d2c58'],grain:['#f8e6ac','#c6aa62','#997432'],corn:['#fff2a9','#e4b838','#b38523'],leaf:['#d2e6a0','#77a64f','#3f7340']} as Record<string,string[]>)[kind];
 const g='url(#'+id+'fruit)';const leaf=<path d="M61 29Q72 5 92 13Q87 33 61 29" fill="#658c43"/>;
 return <div className={'product-icon produce-art '+kind} aria-hidden="true"><svg viewBox="0 0 120 100" className="produce-object"><defs><radialGradient id={id+'fruit'} cx=".3" cy=".22" r=".85"><stop stopColor={color[0]}/><stop offset=".55" stopColor={color[1]}/><stop offset="1" stopColor={color[2]}/></radialGradient><radialGradient id={id+'sh'}><stop stopColor="#293b21" stopOpacity=".27"/><stop offset="1" stopColor="#293b21" stopOpacity="0"/></radialGradient></defs><ellipse cx="60" cy="85" rx="45" ry="11" fill={'url(#'+id+'sh)'}/>
 {kind==='carrot'?<><path d="M40 26Q60 16 78 29Q73 60 30 88Q28 55 40 26" fill={g}/><path d="M56 28Q33 10 44 4Q60 10 60 25Q65 0 78 7Q79 18 63 29Q86 8 91 18Q83 30 66 31" fill="#608d42"/><path d="m44 44 12 5m-18 7 11 5" stroke="#ad5c26" strokeWidth="2" fill="none"/></>:kind==='banana'?<><path d="M21 29Q29 67 67 66Q93 65 98 24L105 24Q108 74 73 85Q29 91 15 42Z" fill={g}/><path d="M27 41Q47 78 80 69" fill="none" stroke="#fff3ae" strokeWidth="3"/></>:kind==='grape'?<>{leaf}{[[47,38],[73,39],[35,55],[59,57],[84,57],[47,73],[72,74],[60,86]].map(([x,y],i)=><circle key={i} cx={x} cy={y} r="15" fill={g}/>)}</>:kind==='leaf'||kind==='grain'||kind==='corn'?<><path d="M60 86Q12 80 21 31Q32 7 60 37Q83 6 100 26Q116 64 60 86" fill={g}/><path d="M60 85Q53 48 60 29M59 66 35 43M60 59 84 35" fill="none" stroke="#fff8c6" strokeWidth="2.5" opacity=".7"/></>:<><path d={kind==='mango'?'M74 22Q106 31 88 66Q77 92 46 84Q19 75 30 45Q42 16 74 22':kind==='potato'?'M37 26Q80 12 98 44Q109 76 74 86Q30 96 21 63Q13 40 37 26':'M60 26Q88 11 103 46Q115 84 76 88Q63 86 60 84Q31 97 18 64Q8 25 40 23Q51 20 60 26'} fill={g}/>{kind!=='potato'&&<><path d="M60 28Q59 14 66 9" stroke="#6d6238" strokeWidth="4" fill="none" strokeLinecap="round"/>{leaf}</>}</>}
 </svg></div>
}
export function Portal({phase}:{phase:'cover'|'reveal'|null}){
 return phase?<div className={'portal-layer portal-'+phase} aria-hidden="true"><div className="portal-sphere"/></div>:null;
}
export function RoleChooser({onNavigate}:{onNavigate:(tab:string)=>void}){
 const roles=[{tab:'Farmer',icon:'farmer',title:'Farmer',description:'Submit harvests, join an FPO and track earnings.',action:'Open farmer dashboard'},{tab:'FPO manager',icon:'manager',title:'FPO manager',description:'Verify harvests, manage inventory and deliveries.',action:'Open FPO dashboard'},{tab:'Market',icon:'customer',title:'Customer',description:'Discover local produce, shop and track orders.',action:'Open customer dashboard'}];
 return <section className="editorial-band role-band open-roles portal-roles sunset-role"><SunsetScene className="role-scenery"/><div className="role-content"><span className="eyebrow">YOUR JOURNEY STARTS HERE</span><h2 id="workspaces" tabIndex={-1}>Choose your dashboard</h2><p>One connected community. Find your place.</p><div className="role-list">{roles.map((w,i)=><button className="role-row" key={w.tab} aria-label={w.action} onClick={()=>onNavigate(w.tab)}><span className={'role-object role-object-'+i}><Icon name={w.icon}/></span><span className="role-copy"><strong>{w.title}</strong><small>{w.description}</small></span><span className="role-arrow"><Icon name="arrow"/></span></button>)}</div><p className="workspace-note">Each account has one permanent role. Existing accounts open their own dashboard.</p></div></section>
}
export function Landing({onNavigate}:{onNavigate:(tab:string)=>void}){
 const features=[
 {icon:'farmer',label:'01 / FOR FARMERS',title:'Every harvest counts.',text:'Join an FPO, submit crops with photos and follow approvals and estimated earnings.'},
 {icon:'manager',label:'02 / FOR FPOs',title:'One view of your supply.',text:'Review harvests and memberships, publish graded stock, manage notifications and coordinate demo deliveries.'},
 {icon:'customer',label:'03 / FOR CUSTOMERS',title:'Fresh produce, closer to you.',text:'Explore verified produce listings, check available quantities, build a cart and track orders.'},
 {icon:'chat',label:'04 / CONNECTED CONVERSATIONS',title:'Just say hello.',text:'Link your account from Profile and use our restricted WhatsApp test assistant in English, Kannada, Telugu or Hindi.'}
 ];
 return <section className="workspace-home immersive-home">
  <div className="landing-hero immersive-hero sunset-hero"><SunsetScene live className="hero-scenery"/><div className="sunset-scrim"/><div className="landing-copy"><span className="eyebrow">AGRICULTURE, RECONNECTED</span><SplitHeading lines={['Good things','grow together.']}/><p>One connection from the soil to your doorstep.</p><button className="primary-link" onClick={()=>onNavigate('Roles')}>Get started <Icon name="arrow"/></button><div className="scroll-cue" aria-hidden="true"><span/>Scroll to discover</div></div><div className="sunset-caption"><span className="sunset-dot"/> EVERY HARVEST, A NEW HORIZON</div></div>
  <div className="feature-story">{features.map((f,i)=><Reveal key={f.label} className={'feature-chapter chapter-'+i}><div className="chapter-object" aria-hidden="true"><span className="chapter-orbit"/><span className="chapter-emblem"><Icon name={f.icon}/></span></div><div className="chapter-copy"><span className="eyebrow">{f.label}</span><h2>{f.title}</h2><p>{f.text}</p></div></Reveal>)}</div>
  <Reveal className="editorial-band supply-band open-supply"><div><span className="eyebrow">A CONNECTED SUPPLY CHAIN</span><h2>From a seed<br/>to a shared future.</h2></div><div className="supply-flow">{[{i:'farmer',n:'Harvest'},{i:'manager',n:'Verify'},{i:'customer',n:'Purchase'},{i:'truck',n:'Deliver'}].map((s,i)=><div key={s.n}><span className="supply-object"><Icon name={s.i}/></span><small>0{i+1}</small><b>{s.n}</b></div>)}</div><p className="supply-disclaimer">Test environment. Payments and deliveries are simulated. ONDC is a local sandbox.</p></Reveal>
 </section>
}
