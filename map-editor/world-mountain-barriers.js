/** Solid mountains are an explicit authoring choice; ordinary mountain biomes
 * keep their existing drivable ground. Artwork follows the collision outline. */
import {pointInPolygon,pointSegment,stringSeed} from './world-geometry.js';
import {textureTerrain} from './world-terrain-materials.js';
export const isMountainBarrier=r=>r?.barrier===true&&['mountain','rock'].includes(r.biome??r.kind);
export function validateMountainRegion(r){
  if(r.barrier!==undefined&&typeof r.barrier!=='boolean')throw new TypeError('Invalid mountain barrier setting');
  if(!r.barrier)return;
  if(!isMountainBarrier(r)||!Number.isFinite(r.elevation)||r.elevation<5)throw new RangeError('Mountain barriers need mountain/rock terrain and height of at least 5 m');
  const ps=r.points;
  for(let i=0;i<ps.length;i++)for(let j=i+2;j<ps.length;j++){
    if(!i&&j===ps.length-1)continue;
    const a=ps[i],b=ps[(i+1)%ps.length],c=ps[j],d=ps[(j+1)%ps.length];
    const dx=b.x-a.x,dy=b.y-a.y,wx=d.x-c.x,wy=d.y-c.y,den=dx*wy-dy*wx;
    if(Math.abs(den)<1e-9)continue;
    const t=((c.x-a.x)*wy-(c.y-a.y)*wx)/den,u=((c.x-a.x)*dy-(c.y-a.y)*dx)/den;
    if(t>=0&&t<=1&&u>=0&&u<=1)throw new RangeError('Mountain barrier outline crosses itself');
  }
}
const cache=new Map();
const noise=(x,y,seed)=>{const v=Math.sin(x*127.1+y*311.7+seed*.001)*43758.5453;return v-Math.floor(v);};
function smoothNoise(x,y,seed){const ix=Math.floor(x),iy=Math.floor(y),fx=x-ix,fy=y-iy;
  const u=fx*fx*(3-2*fx),v=fy*fy*(3-2*fy),mix=(a,b,t)=>a+(b-a)*t;
  return mix(mix(noise(ix,iy,seed),noise(ix+1,iy,seed),u),mix(noise(ix,iy+1,seed),noise(ix+1,iy+1,seed),u),v);}
export function mountainPlan(region){
  const x=Math.min(...region.points.map(p=>p.x)),y=Math.min(...region.points.map(p=>p.y));
  const ps=region.points.map(p=>({x:p.x-x,y:p.y-y}));
  const key=JSON.stringify([ps,region.elevation,region.biome??region.kind]);
  const id=region.id??region.authoring_id??key,old=cache.get(id);
  if(old?.key===key)return {...old.plan,x,y};
  const width=Math.max(...ps.map(p=>p.x)),height=Math.max(...ps.map(p=>p.y)),seed=stringSeed(String(id));
  const step=Math.max(24,Math.sqrt(width*height/2100));
  const nx=Math.max(2,Math.min(140,Math.ceil(width/step))),ny=Math.max(2,Math.min(140,Math.ceil(height/step)));
  const peaks=new Map(),triangles=[];
  const vertex=(ix,iy)=>{const k=ix+','+iy;if(peaks.has(k))return peaks.get(k);
    const p={x:ix*width/nx,y:iy*height/ny};let edge=Infinity;
    for(let i=0;i<ps.length;i++)edge=Math.min(edge,pointSegment(p,ps[i],ps[(i+1)%ps.length]).distance);
    const ridge=1-Math.abs(smoothNoise(p.x/95,p.y/95,seed)*2-1);
    p.z=pointInPolygon(p,ps)?Math.min(region.elevation,edge*3.2)*(.40+.60*ridge*ridge):0;
    peaks.set(k,p);return p;};
  for(let iy=0;iy<ny;iy++)for(let ix=0;ix<nx;ix++){
    const a=vertex(ix,iy),b=vertex(ix+1,iy),c=vertex(ix+1,iy+1),d=vertex(ix,iy+1);
    for(const face of [[a,b,c],[a,c,d]]){
      const [p,q,r]=face,ux=q.x-p.x,uy=q.y-p.y,uz=q.z-p.z,vx=r.x-p.x,vy=r.y-p.y,vz=r.z-p.z;
      const normal=[uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx],length=Math.hypot(...normal)||1;
      const light=Math.max(0,Math.min(1,(-.5*normal[0]-.65*normal[1]+.65*normal[2])/length));
      const tint=.51+.55*light,base=(region.biome??region.kind)==='rock'?[150,150,140]:[137,144,128];
      triangles.push({points:face,color:'rgb('+base.map(c=>Math.round(c*tint)).join(',')+')'});
    }
  }
  const plan={outline:ps,triangles,width,height,heightM:region.elevation};
  cache.set(id,{key,plan});if(cache.size>64)cache.delete(cache.keys().next().value);
  return {...plan,x,y};
}
function trace(ctx,ps){ctx.beginPath();ctx.moveTo(ps[0].x,ps[0].y);for(const p of ps.slice(1))ctx.lineTo(p.x,p.y);ctx.closePath();}
export function drawMountainRegion(ctx,region){
  const plan=mountainPlan(region),cast=Math.max(4,Math.min(24,plan.heightM*.13));
  ctx.save();ctx.translate(plan.x,plan.y);
  for(const spread of [1,.65]){ctx.save();ctx.translate(cast*spread,cast*1.4*spread);trace(ctx,plan.outline);ctx.fillStyle='#0b17171f';ctx.fill();ctx.restore();}
  trace(ctx,plan.outline);ctx.fillStyle='#65705c';ctx.fill();ctx.strokeStyle='#424f43';ctx.lineWidth=.8;ctx.stroke();
  ctx.save();trace(ctx,plan.outline);ctx.clip();
  for(const triangle of plan.triangles){trace(ctx,triangle.points);ctx.fillStyle=triangle.color;ctx.fill();}
  ctx.globalAlpha=.18;trace(ctx,plan.outline);textureTerrain(ctx,'rock');ctx.restore();
  trace(ctx,plan.outline);ctx.strokeStyle='#a6a88766';ctx.lineWidth=.2;ctx.stroke();ctx.restore();
}
