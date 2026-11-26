import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:4176',host='https://commerce-test.supabase.co';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','4176','--strictPort'],{env:{...process.env,VITE_SUPABASE_URL:host,VITE_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_mock_test_only'},stdio:'ignore'});
let browser;
const uid='10000000-0000-4000-8000-000000000001',fpo='20000000-0000-4000-8000-000000000001',oid='30000000-0000-4000-8000-000000000001';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'mock@example.invalid',app_metadata:{provider:'email'},user_metadata:{},created_at:new Date().toISOString()};
const token=[Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),Buffer.from(JSON.stringify({sub:uid,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),'mock-signature'].join('.');
const session={access_token:token,refresh_token:'mock-refresh',token_type:'bearer',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,user};
let stock=100,order=null,request=null,events=[],managerEnabled=false;
const product=()=>({fpo_id:fpo,fpo_name:'Mock FPO',crop:'Tomatoes',grade:'A',price_paise_per_kg:3000,available_kg:stock});
try{
 for(let i=0;i<60;i++){try{if((await fetch(origin)).ok)break}catch{}await new Promise(r=>setTimeout(r,200))}
 browser=await chromium.launch({headless:true});
 async function openRole(role,requested,id=uid){
 const page=await browser.newPage({viewport:{width:390,height:844}});
 const u={...user,id};
 const access_token=[Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),Buffer.from(JSON.stringify({sub:id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),'mock-signature'].join('.');
 const mockSession={...session,user:u,access_token};
 let storedRole=role;
 let alertsRead=false;
 let waStatus={status:'unlinked'};
 const waCode='12345678-1234-4123-8123-123456789abc';
 page.simulateWhatsAppLink=()=>{assert.equal(waStatus.status,'pending');waStatus={status:'linked',last4:'0001'};};
 await page.addInitScript(({mockSession,requested})=>{localStorage.setItem('sb-commerce-test-auth-token',JSON.stringify(mockSession));sessionStorage.setItem('agriconnect.oauth.workspace',requested)},{mockSession,requested});
 await page.route(host+'/**',async route=>{
  const req=route.request(),url=new URL(req.url()),path=url.pathname;
  const send=(body,status=200)=>route.fulfill({status,contentType:'application/json',headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,OPTIONS'},body:JSON.stringify(body)});
  if(req.method()==='OPTIONS')return send({});
  if(path==='/auth/v1/user')return send(u);
  if(path.endsWith('/rpc/manager_inbox')){assert.equal(storedRole,'manager');return send({unread:alertsRead?0:1,pending_members:1,pending_harvests:2,open_orders:1,alerts:alertsRead?[]:[{id:oid,kind:'harvest_submitted',fpo_id:fpo,fpo_name:'Mock FPO',created_at:new Date().toISOString()}]});}
  if(path.endsWith('/rpc/manager_read')){assert.equal(storedRole,'manager');assert.equal(req.postDataJSON().p_id,oid);alertsRead=true;return send(true);}
  if(path.endsWith('/rpc/wa_status'))return send(waStatus);
  if(path.endsWith('/rpc/wa_begin')){assert.equal(req.postDataJSON().p_phone,'919000000001');waStatus={status:'pending',last4:'0001',expires_at:new Date(Date.now()+600000).toISOString()};return send({code:waCode,expires_at:waStatus.expires_at});}
  if(path.endsWith('/rpc/wa_unlink')){waStatus={status:'unlinked'};return send(null);}
  if(path.endsWith('/rpc/catalogue'))return send([product()]);
  if(path.endsWith('/fpos'))return send([{id:fpo,name:'Mock FPO',location:'Test'}]);
  if(path.endsWith('/profiles')){if(req.method()==='POST'){assert.equal(req.postDataJSON().id,id);storedRole=req.postDataJSON().account_role;return send(null,201);}return send(storedRole?{display_name:'Mock '+storedRole,account_role:storedRole}:null);}
  if(path.endsWith('/memberships'))return send(storedRole==='manager'&&managerEnabled?[{fpo_id:fpo,user_id:id,role:'manager',status:'active',profiles:{display_name:'Mock manager'},fpos:{name:'Mock FPO'}}]:[]);
  if(path.endsWith('/harvests')||path.endsWith('/inventory_lots')||path.endsWith('/order_allocations'))return send([]);
  if(path.endsWith('/rpc/checkout_order')||path.endsWith('/rpc/checkout_demo_channel')){
   assert.equal(storedRole,'customer');request=req.postDataJSON();stock-=request.p_items[0].quantity_kg;
   order={id:oid,customer_id:uid,fpo_id:fpo,items:request.p_items,delivery_address:request.p_address,status:'confirmed',payment_status:'simulated_paid',source:request.p_channel?request.p_channel+'_demo':'web',total_paise:15000,gateway_paise:300,platform_paise:750,logistics_paise:1200,farmer_pool_paise:12750,created_at:new Date().toISOString()};
   events=[{id:1,order_id:oid,status:'confirmed',created_at:new Date().toISOString()}];
   return send(oid);
  }
  if(path.endsWith('/rpc/transition_order')){
   const body=req.postDataJSON();assert.equal(body.p_id,oid);if(body.p_next==='cancelled'){stock+=order.items[0].quantity_kg;order={...order,status:'cancelled',payment_status:'simulated_refunded'};}else{assert.equal(storedRole,'manager');assert.ok(managerEnabled);assert.ok(['packed','out_for_delivery','delivered'].includes(body.p_next));order={...order,status:body.p_next};}events.push({id:events.length+1,order_id:oid,status:body.p_next,created_at:new Date().toISOString()});return send(null);
  }
  if(path.endsWith('/orders'))return send(order?[order]:[]);
  if(path.endsWith('/order_events'))return send(events);
  return send([]);
 });
 await page.goto(origin);return page;
 }
 const page=await openRole('customer','FPO manager');
 await page.getByRole('heading',{name:'Available produce'}).waitFor();
 assert.equal(await page.getByRole('button',{name:'Switch workspace'}).count(),0);
 assert.equal(await page.getByRole('button',{name:'Overview',exact:true}).count(),0);
 assert.equal(await page.getByRole('button',{name:'Submit harvest',exact:true}).count(),0);
 await page.getByRole('button',{name:'Add to cart',exact:true}).click();
 await page.getByRole('button',{name:'Cart (1)',exact:true}).click();
 await page.getByRole('heading',{name:'Shopping cart'}).waitFor();
 await page.getByLabel('Quantity (kg)').fill('5');
 await page.getByLabel('Demo delivery address').fill('Test street, Bengaluru');
 const place=page.getByRole('button',{name:'Place demo order'});
 assert.ok(await place.isDisabled());
 await page.getByRole('checkbox').check();
 await place.click();
 await page.getByRole('heading',{name:'My orders'}).waitFor();
 await page.getByText('Order #'+oid.slice(0,8),{exact:false}).waitFor();
 assert.equal(request.p_fpo,fpo);assert.equal(request.p_items[0].quantity_kg,5);assert.equal(request.p_items[0].price_paise_per_kg,3000);assert.match(request.p_request,/^[0-9a-f-]{36}$/i);
 await page.getByRole('button',{name:'Market',exact:true}).click();
 await page.getByText('95 kg available',{exact:true}).waitFor();
 await page.getByRole('button',{name:'My orders',exact:true}).click();
 page.once('dialog',d=>d.accept());await page.getByRole('button',{name:'Cancel order'}).click();
 await page.getByText('Demo refund recorded',{exact:false}).waitFor();
 await page.getByRole('button',{name:'Market',exact:true}).click();
 await page.getByText('100 kg available',{exact:true}).waitFor();
 await page.getByRole('button',{name:'Add to cart',exact:true}).click();
 await page.getByRole('button',{name:'Cart (1)',exact:true}).click();
 await page.getByText('External channel sandbox (optional)').click();
 await page.getByLabel('Order channel').selectOption('whatsapp');
 await page.getByLabel('Quantity (kg)').fill('5');
 await page.getByLabel('Demo delivery address').fill('Test street, Bengaluru');
 await page.getByRole('checkbox').check();await page.getByRole('button',{name:'Place demo order'}).click();
 await page.getByText('WhatsApp demo',{exact:false}).waitFor();assert.equal(request.p_channel,'whatsapp');
 await page.getByRole('button',{name:'Market',exact:true}).click();await page.getByRole('button',{name:'Add to cart',exact:true}).click();await page.getByRole('button',{name:'Cart (1)',exact:true}).click();await page.getByText('External channel sandbox (optional)').click();await page.getByLabel('Order channel').selectOption('ondc');await page.getByLabel('Quantity (kg)').fill('5');await page.getByLabel('Demo delivery address').fill('Test street, Bengaluru');await page.getByRole('checkbox').check();await page.getByRole('button',{name:'Place demo order'}).click();await page.getByText('ONDC demo',{exact:false}).waitFor();assert.equal(request.p_channel,'ondc');
 assert.equal(await page.getByRole('button',{name:'Switch workspace'}).count(),0);
 const farmer=await openRole('farmer','Market','10000000-0000-4000-8000-000000000002');
 await farmer.getByRole('heading',{name:'My farm'}).waitFor();assert.equal(await farmer.getByRole('button',{name:'Market',exact:true}).count(),0);assert.equal(await farmer.getByRole('button',{name:'Overview',exact:true}).count(),0);assert.equal(await farmer.getByRole('button',{name:'Switch workspace'}).count(),0);
 await farmer.getByRole('button',{name:'Join FPO',exact:true}).click();await farmer.getByRole('heading',{name:'My memberships'}).waitFor();
 const manager=await openRole('manager','Farmer','10000000-0000-4000-8000-000000000003');
 await manager.getByRole('heading',{name:'Manage your organisation'}).waitFor();assert.equal(await manager.getByRole('button',{name:'Cart',exact:true}).count(),0);assert.equal(await manager.getByRole('button',{name:'Submit harvest',exact:true}).count(),0);assert.equal(await manager.getByRole('button',{name:'Switch workspace'}).count(),0);
 await manager.getByRole('button',{name:'Delivery',exact:true}).click();await manager.getByText('You must manage an FPO to coordinate deliveries.').waitFor();
 managerEnabled=true;await manager.getByRole('button',{name:'Overview',exact:true}).click();await manager.getByRole('button',{name:'Refresh',exact:true}).click();await manager.getByText('Workspace refreshed.',{exact:true}).waitFor();await manager.getByRole('button',{name:'Members',exact:true}).click();await manager.getByRole('heading',{name:'Members and requests'}).waitFor();await manager.getByRole('button',{name:'Harvest review',exact:true}).click();await manager.getByRole('heading',{name:'Harvest verification'}).waitFor();await manager.getByRole('button',{name:'Inventory',exact:true}).click();await manager.getByRole('heading',{name:'Shared inventory'}).waitFor();await manager.getByRole('button',{name:'Delivery',exact:true}).click();await manager.getByRole('button',{name:'Mark packed'}).click();await manager.getByRole('button',{name:'Dispatch',exact:true}).click();await manager.getByRole('button',{name:'Mark delivered'}).click();await manager.getByRole('button',{name:'Mark delivered'}).waitFor({state:'hidden'});assert.equal(order.status,'delivered');

 assert.equal(await page.getByRole('button',{name:'Notifications',exact:true}).count(),0);assert.equal(await farmer.getByRole('button',{name:'Notifications',exact:true}).count(),0);
 await manager.getByRole('button',{name:'Notifications',exact:true}).click();await manager.getByRole('heading',{name:'FPO notifications'}).waitFor();await manager.getByText('New harvest submitted',{exact:true}).waitFor();await manager.getByRole('button',{name:'Mark read',exact:true}).click();await manager.getByText('No unread alerts.',{exact:true}).waitFor();await manager.getByRole('button',{name:'Refresh notifications'}).click();await manager.getByText('0 unread alerts',{exact:true}).waitFor();
 const fresh=await openRole(null,'Farmer','10000000-0000-4000-8000-000000000004');
 await fresh.getByRole('heading',{name:'Complete your profile'}).waitFor();await fresh.getByLabel('Your name').fill('New farmer');assert.equal(await fresh.getByLabel('Account role').inputValue(),'farmer');await fresh.getByRole('checkbox').check();await fresh.getByRole('button',{name:'Save profile'}).click();await fresh.getByRole('heading',{name:'My farm'}).waitFor();assert.equal(await fresh.getByRole('button',{name:'Switch workspace'}).count(),0);
 await page.getByRole('button',{name:'Profile',exact:true}).click();
 await page.getByRole('heading',{name:'WhatsApp account'}).waitFor();
 await page.getByText('Not linked',{exact:true}).waitFor();
 await page.getByLabel('WhatsApp phone number (with country code)').fill('919000000001');
 await page.getByRole('checkbox',{name:'I consent to linking this test number to my account.'}).check();
 await page.getByRole('button',{name:'Generate linking code'}).click();
 await page.getByText('LINK 12345678-1234-4123-8123-123456789abc',{exact:true}).waitFor();
 page.simulateWhatsAppLink();
 await page.getByRole('button',{name:'Refresh linking status'}).click();
 await page.getByText('Linked · number ending 0001',{exact:true}).waitFor();
 assert.equal(await page.getByText('LINK 12345678-1234-4123-8123-123456789abc',{exact:true}).count(),0);
 await farmer.getByRole('button',{name:'Profile',exact:true}).click();await farmer.getByText('Not linked',{exact:true}).waitFor();
 await manager.getByRole('button',{name:'Profile',exact:true}).click();await manager.getByText('Not linked',{exact:true}).waitFor();
 page.once('dialog',d=>d.accept());await page.getByRole('button',{name:'Unlink WhatsApp'}).click();await page.getByText('Not linked',{exact:true}).waitFor();
 console.log('PASS: WhatsApp profile consent, code display, refresh, separate account status and unlink UI (mocked backend)');
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Mobile layout overflow');
 console.log('PASS: three distinct accounts cannot switch dashboards, wrong login choice redirects to assigned role, new role registration, commerce and delivery regression');
}finally{await browser?.close();server.kill();}
