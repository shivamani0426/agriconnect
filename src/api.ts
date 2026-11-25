import { createClient } from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
export const configured=Boolean(url && key);
export const db=configured?createClient(url,key):null;
export function client(){if(!db)throw new Error('Backend configuration is pending.');return db;}
export async function result<T>(p:PromiseLike<{data:T;error:{message:string}|null}>):Promise<T>{const {data,error}=await p;if(error)throw new Error(error.message);return data;}
export const api={
 profile:(uid:string)=>result(client().from('profiles').select('*').eq('id',uid).maybeSingle()),
 saveProfile:(uid:string,name:string)=>result(client().from('profiles').upsert({id:uid,display_name:name})),
 fpos:()=>result(client().from('fpos').select('*').order('name')),
 memberships:()=>result(client().from('memberships').select('*,profiles(display_name),fpos(name)')),
 harvests:()=>result(client().from('harvests').select('*').order('created_at',{ascending:false})),
 inventory:()=>result(client().from('inventory_lots').select('*')),
 catalogue:()=>result(client().rpc('catalogue')),
 createFpo:(name:string,location:string)=>result(client().rpc('create_fpo',{p_name:name,p_location:location})),
 join:(fpo:string,uid:string)=>result(client().from('memberships').insert({fpo_id:fpo,user_id:uid,role:'farmer',status:'pending'})),
 reviewMember:(fpo:string,uid:string,approve:boolean)=>result(client().rpc('review_member',{p_fpo:fpo,p_user:uid,p_approve:approve})),
 submitHarvest:async(uid:string,fpo:string,crop:string,qty:number,date:string,photo:File|null)=>{
  let path:string|null=null;
  if(photo){if(!['image/jpeg','image/png','image/webp'].includes(photo.type)||photo.size>5*1024*1024)throw new Error('Use a JPG, PNG or WebP image up to 5 MB.');path=uid+'/'+crypto.randomUUID()+'.'+({ 'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[photo.type]);await result(client().storage.from('harvest-photos').upload(path,photo,{contentType:photo.type}));}
  return result(client().from('harvests').insert({fpo_id:fpo,farmer_id:uid,crop,quantity_kg:qty,harvest_date:date,photo_path:path}));
 },
 photo:(path:string)=>result(client().storage.from('harvest-photos').createSignedUrl(path,60)),
 reviewHarvest:(id:string,grade:string,price:number,approve:boolean,reason:string)=>result(client().rpc('review_harvest',{p_id:id,p_grade:grade,p_price:price,p_approve:approve,p_reason:reason}))
};
