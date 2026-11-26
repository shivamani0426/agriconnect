import {createHash} from 'node:crypto';
import {ProtocolError,object} from './protocol.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const clean=(v,max)=>typeof v==='string'&&v.trim().length>0&&v.length<=max&&!/[\u0000-\u001f\u007f]/.test(v);
const reject=()=>{throw new ProtocolError('LOCAL_CATALOGUE','Invalid catalogue snapshot')};
const exactKg=v=>{if(typeof v!=='string'&&typeof v!=='number')reject();const s=String(v);if(!/^\d{1,9}(\.\d{1,3})?$/.test(s))reject();const [whole,frac='']=s.split('.');return Number(whole)*1000+Number(frac.padEnd(3,'0'))};
const priceString=p=>String(Math.floor(p/100))+'.'+String(p%100).padStart(2,'0');
export const sku=(fpo,crop,grade,price)=>'sku-'+createHash('sha256').update(JSON.stringify([fpo,crop,grade,price])).digest('hex').slice(0,32);
// Input shape is public.catalogue() output. Explicit local eligibility metadata: no guessing categories or service areas.
export function projectCatalogue(rows,eligibility,filters){
 if(!Array.isArray(rows)||rows.length>1000||!(eligibility instanceof Map))reject();
 const providers=new Map(),seen=new Set();
 for(const r of rows){
  if(!object(r)||typeof r.fpo_id!=='string'||!uuid.test(r.fpo_id)||!clean(r.fpo_name,120)||!clean(r.crop,100)||!['A','B','C'].includes(r.grade)||!Number.isInteger(r.price_paise_per_kg)||r.price_paise_per_kg<=0||r.price_paise_per_kg>2147483647)reject();
  const stock=exactKg(r.available_kg),meta=eligibility.get(r.fpo_id);
  const itemId=sku(r.fpo_id,r.crop,r.grade,r.price_paise_per_kg);
  if(seen.has(itemId))reject();seen.add(itemId);
  if(!meta||meta.city!== 'std:080'||!Array.isArray(meta.crops)||!meta.crops.includes(r.crop)||stock<1000)continue;
  if(filters.city!=='*'&&filters.city!==meta.city||filters.provider&&filters.provider!==r.fpo_id||filters.query&&!r.crop.toLowerCase().includes(filters.query.toLowerCase()))continue;
  let p=providers.get(r.fpo_id);
  if(!p){p={id:r.fpo_id,descriptor:{name:r.fpo_name},items:[]};providers.set(r.fpo_id,p);}
  if(p.descriptor.name!==r.fpo_name)reject();
  p.items.push({id:itemId,descriptor:{name:r.crop,short_desc:'Grade '+r.grade},category_id:'Fruits and Vegetables',price:{currency:'INR',value:priceString(r.price_paise_per_kg)},quantity:{unitized:{measure:{unit:'kilogram',value:'1'}},available:{count:'99'}}});
 }
 return {'bpp/descriptor':{name:'AgriConnect LOCAL TEST ONLY'},'bpp/providers':[...providers.values()].sort((a,b)=>a.id.localeCompare(b.id)).map(p=>({...p,items:p.items.sort((a,b)=>a.id.localeCompare(b.id))}))};
}
