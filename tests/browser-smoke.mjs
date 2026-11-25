import { chromium } from 'playwright';
import assert from 'node:assert/strict';
const browser=await chromium.launch({headless:true});
try {
 const page=await browser.newPage({viewport:{width:1280,height:800}});
 const url=process.env.AGRICONNECT_TEST_URL;
 if(!url)throw Error('Missing AGRICONNECT_TEST_URL');
 await page.goto(url,{waitUntil:'domcontentloaded'});
 const chooser=page.getByRole('button',{name:'Open customer dashboard'});await chooser.or(page.getByRole('heading',{name:'Available produce'})).waitFor();if(await chooser.isVisible())await chooser.click();
 await page.getByRole('heading',{name:'Available produce'}).waitFor();
 assert.equal(await page.getByText('Backend configuration pending.',{exact:false}).count(),0);
 assert.equal(await page.getByRole('alert').count(),0);
 const modern=await page.getByRole('button',{name:'Switch workspace'}).isVisible();if(modern){await page.getByRole('button',{name:'Switch workspace'}).click();await page.getByRole('button',{name:'Open farmer dashboard'}).click();}else await page.getByRole('button',{name:'Farmer',exact:true}).click();
 await page.getByRole('heading',{name:'Welcome back'}).waitFor();
 await page.getByRole('button',{name:'New here? Create account'}).click();
 await page.getByRole('heading',{name:'Create your account'}).waitFor();
 await page.getByRole('button',{name:'Already registered? Sign in'}).click();
 await page.getByLabel('Email',{exact:true}).fill('agriconnect-smoke@example.invalid');
 await page.getByLabel('Password',{exact:true}).fill('Not-a-real-account-123!');
 await page.locator('main form').getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByRole('alert').waitFor({timeout:20000});
 assert.match(await page.getByRole('alert').innerText(),/invalid login credentials|invalid credentials|invalid email or password/i);
 if(modern){await page.getByRole('button',{name:'Switch workspace'}).click();await page.getByRole('button',{name:'Open FPO dashboard'}).click();}else await page.getByRole('button',{name:'FPO manager',exact:true}).click();
 await page.getByRole('heading',{name:'Welcome back'}).waitFor();
 await page.getByRole('button',{name:'Delivery',exact:true}).click();
 await page.getByText('Not enabled in Day 01.',{exact:false}).or(page.getByRole('heading',{name:'Welcome back'})).waitFor();
 if(!modern){await page.getByRole('button',{name:'Admin',exact:true}).click();await page.getByText('Not enabled in Day 01.',{exact:false}).waitFor();}else{assert.equal(await page.getByRole('button',{name:'Market',exact:true}).count(),0);await page.getByRole('button',{name:'Switch workspace'}).click();await page.getByRole('button',{name:'Open customer dashboard'}).click();}
 await page.setViewportSize({width:390,height:844});
 await page.getByRole('button',{name:'Market',exact:true}).click();
 await page.getByRole('heading',{name:'Available produce'}).waitFor();
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Mobile viewport must not overflow');
 console.log('PASS: deployed marketplace, auth gating, registration form, invalid login rejection, inactive privileged sections, mobile layout');
} finally {await browser.close();}
