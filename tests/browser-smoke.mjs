import { chromium } from 'playwright';
import assert from 'node:assert/strict';
const browser=await chromium.launch({headless:true});
try {
 const page=await browser.newPage({viewport:{width:1280,height:800}});
 const url=process.env.AGRICONNECT_TEST_URL;
 if(!url)throw Error('Missing AGRICONNECT_TEST_URL');
 await page.goto(url,{waitUntil:'domcontentloaded'});
 // Supports the deployed pre-redesign release during PR verification and the new entry flow after release.
 await page.waitForFunction(()=>[...document.querySelectorAll('button,a')].some(el=>['Get started','Open farmer dashboard'].includes(el.textContent.trim())||el.textContent.trim().startsWith('Get started')));
 const start=page.getByRole('button',{name:'Get started',exact:true});
 if(await start.count())await start.click();
 const chooser=page.getByRole('button',{name:'Open farmer dashboard'});
 await chooser.waitFor();
 await chooser.click();
 await page.getByRole('heading',{name:'Welcome back'}).waitFor();
 assert.equal(await page.getByText('Backend configuration pending.',{exact:false}).count(),0);
 await page.getByRole('button',{name:'New here? Create account'}).click();
 await page.getByRole('heading',{name:'Create your account'}).waitFor();
 await page.getByRole('button',{name:'Already registered? Sign in'}).click();
 await page.getByLabel('Email',{exact:true}).fill('agriconnect-smoke@example.invalid');
 await page.getByLabel('Password',{exact:true}).fill('Not-a-real-account-123!');
 await page.locator('main form').getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByRole('alert').waitFor({timeout:20000});
 assert.match(await page.getByRole('alert').innerText(),/invalid login credentials|invalid credentials|invalid email or password/i);
 const back=page.getByRole('button',{name:/Switch workspace|Back to login choices/});
 await back.click();await page.getByRole('button',{name:'Open FPO dashboard'}).click();
 await page.getByRole('heading',{name:'Welcome back'}).waitFor();
 await back.click();await page.getByRole('button',{name:'Open customer dashboard'}).click();
 await page.getByRole('heading',{name:/Welcome back|Available produce/}).waitFor();
 await page.setViewportSize({width:390,height:844});
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Mobile viewport must not overflow');
 console.log('PASS: deployed login choices, signup form, invalid login rejection, and mobile layout');
} finally {await browser.close();}
