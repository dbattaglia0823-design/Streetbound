/** Tiny dependency-free ZIP writer (store method only) for browser-based packages. */
const utf8=new TextEncoder();
const table=new Uint32Array(256);
for(let i=0;i<256;i++){let c=i;for(let j=0;j<8;j++)c=(c&1)?(0xedb88320^(c>>>1)):(c>>>1);table[i]=c>>>0;}
export function crc32(bytes){let c=0xffffffff;for(const b of bytes)c=table[(c^b)&255]^(c>>>8);return (c^0xffffffff)>>>0;}
function write16(view,p,v){view.setUint16(p,v,true);}
function write32(view,p,v){view.setUint32(p,v>>>0,true);}
const concat=chunks=>{const len=chunks.reduce((sum,c)=>sum+c.length,0),out=new Uint8Array(len);let offset=0;for(const c of chunks){out.set(c,offset);offset+=c.length;}return out;};
export function createZip(files,{maxFileSize=2_000_000}={}){
 if(!(files instanceof Map)||!files.size||files.size>150)throw new RangeError('Expected 1–150 files');
 if(!Number.isInteger(maxFileSize)||maxFileSize<1||maxFileSize>8_000_000)throw new RangeError('Invalid ZIP size limit');
 const locals=[],centrals=[];let offset=0;
 for(const [path,content] of files){
  if(typeof path!=='string'||path.length>220||path.startsWith('/')||path.includes('\\')||!path.split('/').every(x=>x&&x!=='.'&&x!=='..')||!/^[-\w./]+$/.test(path))throw new TypeError('Unsafe ZIP filename');
  const name=utf8.encode(path),data=content instanceof Uint8Array?content:utf8.encode(String(content)),crc=crc32(data);
  if(data.length>maxFileSize)throw new RangeError('File too large for browser package');
  const local=new Uint8Array(30+name.length),lv=new DataView(local.buffer);
  write32(lv,0,0x04034b50);write16(lv,4,20);write16(lv,6,0x0800);write16(lv,8,0);
  write32(lv,14,crc);write32(lv,18,data.length);write32(lv,22,data.length);write16(lv,26,name.length);local.set(name,30);
  locals.push(local,data);
  const central=new Uint8Array(46+name.length),cv=new DataView(central.buffer);
  write32(cv,0,0x02014b50);write16(cv,4,20);write16(cv,6,20);write16(cv,8,0x0800);
  write32(cv,16,crc);write32(cv,20,data.length);write32(cv,24,data.length);write16(cv,28,name.length);
  write32(cv,42,offset);central.set(name,46);centrals.push(central);
  offset+=local.length+data.length;
 }
 const cd=concat(centrals),end=new Uint8Array(22),v=new DataView(end.buffer);
 write32(v,0,0x06054b50);write16(v,8,files.size);write16(v,10,files.size);
 write32(v,12,cd.length);write32(v,16,offset);
 return concat([...locals,cd,end]);
}
