import {chromium} from 'playwright';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:4177',host='https://mobile-qa.supabase.co';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','4177','--strictPort'],{env:{...process.env,VITE_SUPABASE_URL:host,VITE_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_mobile_test'},stdio:'ignore'});
let browser;
try{
 for(let i=0;i<60;i++){try{if((await fetch(origin)).ok)break}catch{}await new Promise(r=>setTimeout(r,200))}
 browser=await chromium.launch({headless:true});
 for(const width of [320,360,390,430,768,1280]){
  const page=await browser.newPage({viewport:{width,height:844},isMobile:width<500,hasTouch:width<500,reducedMotion:'reduce'});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route(host+'/**',route=>route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'},body:'[]'}));
  await page.goto(origin);
  await page.getByRole('heading',{name:'Choose your dashboard'}).waitFor();
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Landing overflow '+width);
  assert.equal(await page.locator('.split-heading span').first().evaluate(el=>getComputedStyle(el).animationName),'none');
  await page.getByRole('link',{name:'Get started'}).click();
  for(const role of ['Open farmer dashboard','Open FPO dashboard','Open customer dashboard']){
   const button=page.getByRole('button',{name:role,exact:true});const box=await button.boundingBox();assert.ok(box.height>=44,'Small touch target '+role);
   await button.click();await page.getByRole('heading',{name:'Welcome back'}).waitFor();
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Auth overflow '+width);
   await page.getByRole('button',{name:'Back to login choices'}).click();
  }
  assert.deepEqual(errors,[]);await page.close();
 }
 console.log('PASS: original landing, touch targets, role navigation, authentication and reduced motion at 320/360/390/430/768/1280px');
}finally{await browser?.close();server.kill()}
