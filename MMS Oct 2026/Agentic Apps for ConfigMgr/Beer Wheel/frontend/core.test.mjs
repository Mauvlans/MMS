import test from 'node:test';
import assert from 'node:assert/strict';
const load = () => import('./core.mjs');
test('Long wheel names shorten visually without changing Attendee names',async()=>{
 const {shortName}=await load(); assert.equal(shortName('Alexandra Sunshine',12),'Alexandra S…'); assert.equal(shortName('Ken',12),'Ken');
});
test('API sends bearer and JSON; surfaces server errors instead of pretend success',async()=>{
 const {apiRequest}=await load(); let captured;
 const fetcher=async(path,options)=>{captured={path,...options};return {ok:true,status:200,json:async()=>({name:'Ken'})}};
 assert.deepEqual(await apiRequest('/api/me',{token:'private'},fetcher),{name:'Ken'});
 assert.equal(captured.headers.Authorization,'Bearer private'); assert.equal(captured.credentials,'same-origin');
 await apiRequest('/api/sign-in',{body:{name:'Ken',email:''}},fetcher); assert.equal(captured.method,'POST'); assert.equal(captured.body,'{"name":"Ken","email":""}');
 await assert.rejects(apiRequest('/api/host/spin',{},async()=>({ok:false,status:409,json:async()=>({error:'Card pool empty'})})),/Card pool empty/);
});
test('Wheel lands the server-selected Attendee under the top pointer after multiple turns', async () => {
 const {landingRotation} = await load();
 for (const n of [1,2,7,60]) for(let i=0;i<n;i++) {
  const r=landingRotation(n,i,791); assert.ok(r>791+1080);
  const angle=((r+(i+.5)*360/n)%360+360)%360;
  assert.ok(Math.abs(angle-270)<0.00001);
 }
});
