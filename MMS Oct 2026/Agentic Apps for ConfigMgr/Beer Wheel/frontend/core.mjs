export function shortName(name,max=16){const chars=Array.from(String(name));return chars.length>max?chars.slice(0,max-1).join('')+'…':String(name)}
export async function apiRequest(path,{body,token,...rest}={},fetcher=globalThis.fetch){
 const response=await fetcher(path,{credentials:'same-origin',...rest,method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{'Content-Type':'application/json'}),...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});
 let data;try{data=await response.json()}catch{data={}}
 if(!response.ok){const error=new Error(typeof data.error==='string'?data.error:typeof data.detail==='string'?data.detail:`Request failed (${response.status}). Please try again.`);error.status=response.status;throw error}
 return data;
}
export function landingRotation(count,index,current=0){
 const target=270-(index+.5)*360/count;
 return current+1440+((target-current)%360+360)%360;
}
