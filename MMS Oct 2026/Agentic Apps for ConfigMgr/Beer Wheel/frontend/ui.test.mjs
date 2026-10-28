import test from 'node:test';
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {extname} from 'node:path';
const server=createServer(async(req,res)=>{
 if(req.url.startsWith('/api/')){res.statusCode=503;res.setHeader('Content-Type','application/json');res.end(JSON.stringify({error:'Event unavailable'}));return}
 try { const file=req.url.includes('.')?req.url:'/index.html'; const data=await readFile(new URL('.'+file,import.meta.url));res.setHeader('Content-Type',({'.html':'text/html','.mjs':'text/javascript','.css':'text/css'})[extname(file)]||'text/plain');res.end(data)}catch{res.statusCode=404;res.end('Not found')}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({headless:true});
const base=`http://127.0.0.1:${server.address().port}`;
test.after(async()=>{await browser.close();server.close()});
for(const [route,role] of [['host','Host'],['redeem','Bartender']])test(`${role} requires API PIN authentication and does not expose protected tools on failure`,async()=>{
 const page=await browser.newPage({viewport:{width:390,height:844}});await page.goto(base+'/'+route);
 await page.getByLabel(`${role} PIN`).fill('invalid-test-pin');await page.getByRole('button',{name:`Sign in as ${role}`}).click();
 await page.getByRole('alert').filter({hasText:'Event unavailable'}).waitFor();
 assert.equal(await page.getByRole('button',{name:'Spin',exact:true}).count(),0);
 assert.equal(await page.getByRole('button',{name:'Confirm Redemption',exact:true}).count(),0);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.close();
});
test('Attendee Sign-in has labeled mobile inputs and cannot claim success when Event is unavailable',async()=>{
 const page=await browser.newPage({viewport:{width:390,height:844}});await page.goto(base+'/join');
 await page.getByLabel('Display name').fill('<img src=x onerror=alert(1)>');await page.getByLabel('Email (optional)').fill('test@example.net');
 await page.getByRole('button',{name:'Join the Wheel'}).waitFor();await page.getByText(/Cannot connect/).waitFor();
 assert.equal(await page.getByRole('button',{name:'Join the Wheel'}).isDisabled(),true);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.close();
});
test('Public Wheel has Join QR code, Squirrel, required copy, no Host controls and honest connection error',async()=>{
 const page=await browser.newPage();await page.goto(base);await page.getByRole('heading',{name:'Good people. Great pours.'}).waitFor();
 assert.ok(await page.getByText('ken is awesome',{exact:false}).count());assert.ok(await page.getByText('chris rox my PG..',{exact:false}).count());
 assert.equal(await page.getByRole('button',{name:'Spin',exact:true}).count(),0);
 await page.getByText(/Cannot connect/).waitFor();
 assert.equal(await page.locator('img[alt="Join QR code"]').getAttribute('src'),'/api/qr');
 await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.close();
});
