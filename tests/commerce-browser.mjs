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
let stock=100,order=null,request=null,events=[];
const product=()=>({fpo_id:fpo,fpo_name:'Mock FPO',crop:'Tomatoes',grade:'A',price_paise_per_kg:3000,available_kg:stock});
try{
 for(let i=0;i<60;i++){try{if((await fetch(origin)).ok)break}catch{}await new Promise(r=>setTimeout(r,200))}
 browser=await chromium.launch({headless:true});
 const page=await browser.newPage({viewport:{width:390,height:844}});
 await page.addInitScript(({session})=>{localStorage.setItem('sb-commerce-test-auth-token',JSON.stringify(session))},{session});
 await page.route(host+'/**',async route=>{
  const req=route.request(),url=new URL(req.url()),path=url.pathname;
  const send=(body,status=200)=>route.fulfill({status,contentType:'application/json',headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,OPTIONS'},body:JSON.stringify(body)});
  if(req.method()==='OPTIONS')return send({});
  if(path==='/auth/v1/user')return send(user);
  if(path.endsWith('/rpc/catalogue'))return send([product()]);
  if(path.endsWith('/fpos'))return send([{id:fpo,name:'Mock FPO',location:'Test'}]);
  if(path.endsWith('/profiles'))return send({display_name:'Mock Customer'});
  if(path.endsWith('/memberships')||path.endsWith('/harvests')||path.endsWith('/inventory_lots')||path.endsWith('/order_allocations'))return send([]);
  if(path.endsWith('/rpc/checkout_order')){
   request=req.postDataJSON();stock-=request.p_items[0].quantity_kg;
   order={id:oid,customer_id:uid,fpo_id:fpo,items:request.p_items,delivery_address:request.p_address,status:'confirmed',payment_status:'simulated_paid',total_paise:15000,gateway_paise:300,platform_paise:750,logistics_paise:1200,farmer_pool_paise:12750,created_at:new Date().toISOString()};
   events=[{id:1,order_id:oid,status:'confirmed',created_at:new Date().toISOString()}];
   return send(oid);
  }
  if(path.endsWith('/rpc/transition_order')){
   const body=req.postDataJSON();assert.equal(body.p_next,'cancelled');assert.equal(body.p_id,oid);stock+=order.items[0].quantity_kg;order={...order,status:'cancelled',payment_status:'simulated_refunded'};events.push({id:2,order_id:oid,status:'cancelled',created_at:new Date().toISOString()});return send(null);
  }
  if(path.endsWith('/orders'))return send(order?[order]:[]);
  if(path.endsWith('/order_events'))return send(events);
  return send([]);
 });
 await page.goto(origin);
 await page.getByRole('button',{name:'Open customer dashboard'}).click();
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
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Mobile layout overflow');
 console.log('PASS: mocked customer cart, demo acknowledgement, checkout payload, order tracking, cancellation, restored stock, mobile layout');
}finally{await browser?.close();server.kill();}
