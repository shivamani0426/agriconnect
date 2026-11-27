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
  const start=page.getByRole('button',{name:'Get started',exact:true});
  await start.waitFor();
  assert.equal(await page.locator('.role-list .role-row').count(),0);
  assert.equal(await page.locator('.feature-chapter').count(),4);
  assert.equal(await page.locator('.workspace-home button').count(),1,'Only Get started on landing');
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Landing overflow '+width);
  assert.equal(await page.locator('.hero-scenery .scene-village').count(),1);
  assert.equal(await page.locator('.hero-scenery .scene-nest-tree').count(),1);
  assert.equal(await page.locator('.hero-scenery .scene-walk').count(),1);
  assert.equal(await page.locator('.hero-scenery .scene-bird').count(),3);
  assert.equal(await page.locator('.workspace-home .panel').count(),0,'Landing should not contain boxed text panels');
  assert.equal(await page.locator('.hero-scenery .scene-bird').first().evaluate(el=>getComputedStyle(el).animationName),'none');
  assert.equal(await page.locator('.split-heading span').first().evaluate(el=>getComputedStyle(el).animationName),'none');
  await start.click();
  await page.getByRole('heading',{name:'Choose your dashboard'}).waitFor();
  assert.equal(await page.locator('.role-list .role-row').count(),3);
  assert.equal(await page.locator('.role-scenery').count(),1);
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Roles overflow '+width);
  assert.equal(await page.locator('.portal-layer').count(),0,'Reduced motion bypasses portal');
  for(const role of ['Open farmer dashboard','Open FPO dashboard','Open customer dashboard']){
   const button=page.getByRole('button',{name:role,exact:true});const box=await button.boundingBox();assert.ok(box.height>=44,'Small touch target '+role);
   await button.click();await page.getByRole('heading',{name:'Welcome back'}).waitFor();
   assert.equal(await page.locator('.auth-landscape .sunset-scene').count(),1);
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Auth overflow '+width);
   await page.getByRole('button',{name:'Back to login choices'}).click();
   await page.getByRole('heading',{name:'Choose your dashboard'}).waitFor();
  }
  assert.deepEqual(errors,[]);await page.close();
 }
 console.log('PASS: original landing, touch targets, role navigation, authentication and reduced motion at 320/360/390/430/768/1280px');
 // Normal motion: assert both transition phases, the locked old surface, and destination.
 const animated=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true,reducedMotion:'no-preference'});
 const errors=[];animated.on('pageerror',e=>errors.push(e.message));
 await animated.route(host+'/**',route=>route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'},body:'[]'}));
 await animated.goto(origin);
 await animated.getByRole('button',{name:'Get started',exact:true}).waitFor();
 await animated.locator('.hero-scenery.scene-moving').waitFor({state:'attached'});
 assert.equal(await animated.locator('.scene-bird').first().evaluate(el=>getComputedStyle(el).animationPlayState),'running');
 const last=animated.locator('.chapter-3');
 await last.scrollIntoViewIfNeeded();
 await animated.locator('.hero-scenery.scene-moving').waitFor({state:'detached'});
 assert.equal(await animated.locator('.hero-scenery .scene-bird').first().evaluate(el=>getComputedStyle(el).animationPlayState),'paused');
 await last.evaluate(el=>new Promise((resolve,reject)=>{let n=0;const check=()=>{if(el.classList.contains('revealed'))resolve();else if(++n>180)reject(Error('Scroll reveal did not activate'));else requestAnimationFrame(check)};check()}));
 await animated.evaluate(()=>window.scrollTo(0,0));
 for(const [selector,destination] of [['.landing-copy .primary-link','Choose your dashboard'],['.role-row[aria-label="Open farmer dashboard"]','Welcome back']]){
  await animated.locator(selector).evaluate(el=>{el.click();el.click()});
  await animated.locator('.portal-cover').waitFor({state:'attached'});
  assert.equal(await animated.locator('.app-surface').getAttribute('inert'),'');
  await animated.locator('.portal-reveal').waitFor({state:'attached'});
  await animated.locator('.portal-layer').waitFor({state:'detached'});
  await animated.getByRole('heading',{name:destination}).waitFor();
  assert.equal(await animated.locator('.app-surface').getAttribute('inert'),null);
 }
 assert.deepEqual(errors,[]);await animated.close();
 console.log('PASS: sunset village, scene motion pauses offscreen, reduced motion, scroll reveal and both black sphere transitions');
}finally{await browser?.close();server.kill()}
