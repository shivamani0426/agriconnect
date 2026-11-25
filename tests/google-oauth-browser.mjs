import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:4175';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','4175','--strictPort'],{env:{...process.env,VITE_SUPABASE_URL:'https://oauth-test.supabase.co',VITE_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_placeholder_for_test'},stdio:'ignore'});
let browser;
try{
 for(let i=0;i<50;i++){try{if((await fetch(origin)).ok)break;}catch{}await new Promise(r=>setTimeout(r,200));}
 browser=await chromium.launch({headless:true});
 const page=await browser.newPage();
 let request;
 await page.route('https://oauth-test.supabase.co/**',async route=>{
 const u=new URL(route.request().url());
 if(u.pathname==='/auth/v1/authorize'){request=u;await route.fulfill({status:200,contentType:'text/plain',body:'Mock Google OAuth redirect'});return;}
 await route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'},body:'[]'});
 });
 await page.goto(origin);
 await page.getByRole('button',{name:'Open FPO dashboard',exact:true}).click();
 await page.getByRole('button',{name:'Continue with Google'}).waitFor();
 await Promise.all([page.waitForURL('https://oauth-test.supabase.co/auth/v1/authorize?**'),page.getByRole('button',{name:'Continue with Google'}).click()]);
 assert.equal(request.searchParams.get('provider'),'google');
 assert.equal(request.searchParams.get('redirect_to'),origin+'/');
 assert.equal(request.searchParams.get('prompt'),'select_account');
 console.log('PASS: Google OAuth button initiates correct Supabase authorize redirect (mocked provider)');
}finally{await browser?.close();server.kill();}
