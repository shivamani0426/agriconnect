import {chromium} from 'playwright';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:4181';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','preview','--host','127.0.0.1','--port','4181','--strictPort'],{stdio:'ignore'});
let browser;
try{
 for(let i=0;i<60;i++){try{if((await fetch(origin)).ok)break}catch{}await new Promise(r=>setTimeout(r,200))}
 const manifestResponse=await fetch(origin+'/manifest.webmanifest');assert.equal(manifestResponse.status,200);
 const manifest=await manifestResponse.json();assert.equal(manifest.display,'standalone');assert.equal(manifest.start_url,'/');
 for(const [path,size] of [...manifest.icons.map(icon=>[icon.src,Number(icon.sizes.split('x')[0])]),['/icons/apple-touch-icon.png',180]]){
  const r=await fetch(origin+path);assert.equal(r.status,200);assert.match(r.headers.get('content-type'),/image\/png/);
  const bytes=Buffer.from(await r.arrayBuffer());assert.equal(bytes.readUInt32BE(16),size);assert.equal(bytes.readUInt32BE(20),size);
 }
 browser=await chromium.launch({headless:true});
 const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,reducedMotion:'reduce'});
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(origin);
 await page.waitForFunction(()=>Boolean(navigator.serviceWorker.controller),{},{timeout:20000});
 // Deterministic fallback: native browser prompts are browser/OS-controlled.
 await page.evaluate(()=>{window.dispatchEvent(new Event('beforeinstallprompt',{cancelable:true}))});
 await page.getByRole('button',{name:'Install app',exact:true}).click();
 await page.getByRole('dialog',{name:'Take AgriConnect with you.'}).waitFor();
 assert.ok(await page.getByText('iPhone · Safari',{exact:true}).isVisible());
 assert.ok(await page.getByText('Android · Chrome',{exact:true}).isVisible());
 await page.getByRole('button',{name:'Close',exact:true}).click();
 await page.evaluate(()=>{const e=new Event('beforeinstallprompt',{cancelable:true});Object.defineProperties(e,{prompt:{value:async()=>{window.__installRequested=true}},userChoice:{value:Promise.resolve({outcome:'dismissed'})}});window.dispatchEvent(e)});
 await page.getByRole('button',{name:'Install app',exact:true}).click();await page.getByRole('dialog').waitFor();
 assert.equal(await page.evaluate(()=>window.__installRequested),true);
 await page.getByRole('button',{name:'Close',exact:true}).click();
 const keys=await page.evaluate(async()=>{const cache=await caches.open('agriconnect-offline-v1');return (await cache.keys()).map(r=>new URL(r.url).pathname).sort()});
 assert.deepEqual(keys,['/icons/icon-192.png','/offline.html']);
 await context.setOffline(true);
 await page.goto(origin+'/');await page.getByRole('heading',{name:"You're offline."}).waitFor();
 await context.setOffline(false);
 await page.getByRole('link',{name:'Try again'}).click();await page.getByRole('button',{name:'Get started',exact:true}).waitFor();
 assert.deepEqual(errors,[]);
 await page.evaluate(()=>window.dispatchEvent(new Event('appinstalled')));
 await page.getByRole('button',{name:'Install app',exact:true}).waitFor({state:'detached'});
 await context.close();
 console.log('PASS: standalone manifest, PNG icons, service worker, install instructions, mocked native prompt, private-cache exclusion, offline notice and reconnection');
}finally{await browser?.close();server.kill()}
