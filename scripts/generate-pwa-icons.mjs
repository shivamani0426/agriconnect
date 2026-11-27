// Deterministic PNG generation using Node built-ins; no extra dependency.
// A golden sun over two green leaves, on the existing forest-green background.
import {mkdirSync,writeFileSync} from 'node:fs';
import {deflateSync} from 'node:zlib';
const crc=b=>{let c=0xffffffff;for(const x of b){c^=x;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0)}return (c^0xffffffff)>>>0};
function chunk(type,data){const name=Buffer.from(type),len=Buffer.alloc(4),sum=Buffer.alloc(4);len.writeUInt32BE(data.length);sum.writeUInt32BE(crc(Buffer.concat([name,data])));return Buffer.concat([len,name,data,sum])}
const rgb=(r,g,b)=>[r,g,b];
function pixel(x,y){
 const bg=rgb(25+Math.round(7*(1-y)),60+Math.round(8*(1-y)),49+Math.round(5*(1-y)));
 const sun=(x-.5)**2+(y-.345)**2<.126**2;
 const leaf=(cx,cy,angle)=>{const dx=x-cx,dy=y-cy,u=dx*Math.cos(angle)+dy*Math.sin(angle),v=-dx*Math.sin(angle)+dy*Math.cos(angle);return (u/.153)**2+(v/.071)**2<1};
 if(leaf(.405,.58,.63))return rgb(167,202,111);
 if(leaf(.595,.50,-.63))return rgb(220,233,145);
 if(Math.abs(x-.5)<.018&&y>.50&&y<.75)return rgb(220,233,145);
 if(sun)return rgb(249,210,115);
 return bg;
}
mkdirSync('public/icons',{recursive:true});
for(const [size,name] of [[192,'icon-192'],[512,'icon-512'],[180,'apple-touch-icon']]){
 const raw=Buffer.alloc((size*3+1)*size);
 for(let y=0;y<size;y++){let offset=y*(size*3+1)+1;for(let x=0;x<size;x++){const sum=[0,0,0];for(const dy of [.25,.75])for(const dx of [.25,.75]){const c=pixel((x+dx)/size,(y+dy)/size);for(let k=0;k<3;k++)sum[k]+=c[k]}for(let k=0;k<3;k++)raw[offset++]=Math.round(sum[k]/4)}}
 const header=Buffer.alloc(13);header.writeUInt32BE(size,0);header.writeUInt32BE(size,4);header[8]=8;header[9]=2;
 writeFileSync('public/icons/'+name+'.png',Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]));
}
