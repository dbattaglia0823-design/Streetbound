/**
 * Streetbound road precedence. Editable source roads never change when a
 * junction is derived: paved roads remain continuous; dirt/gravel are clipped
 * at the paved footprint and split into separate traversable branches.
 * This prevents fake AI junction links and avoids order-dependent painting.
 */
import {distance,pointSegment,sampleRoad,clamp} from './world-geometry.js';

export const isLoose=road=>road?.surface==='dirt'||road?.surface==='gravel';
export const pavedVsLoose=(a,b)=>isLoose(a)!==isLoose(b);

/** Uniformly sample even two-point (perfectly straight) roads so a narrow
 * pavement crossing cannot be skipped between distant control points. */
export function denseRoadPath(road,spacing=12){
  const raw=sampleRoad(road.points,road.smooth,spacing),out=[];
  if(!raw.length)return out;
  out.push(raw[0]);
  for(let i=1;i<raw.length;i++){
    const a=raw[i-1],b=raw[i],steps=Math.max(1,Math.ceil(distance(a,b)/spacing));
    for(let j=1;j<=steps;j++){
      const t=j/steps;
      out.push({x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t});
    }
  }
  return out;
}
const CELL=128;
const cellKey=(x,y)=>x+','+y;
const range=(low,high)=>[Math.floor(low/CELL),Math.floor(high/CELL)];
const cache=new WeakMap();

function indexPaved(roads){
  const cells=new Map(),all=[];
  for(const road of roads){
    if(isLoose(road))continue;
    const points=denseRoadPath(road,16);
    for(let i=1;i<points.length;i++){
      const a=points[i-1],b=points[i];
      if(distance(a,b)<.001)continue;
      const radius=road.width*.5+(road.shoulder||0)+20;
      const segment={a,b,road};
      all.push(segment);
      const [minX,maxX]=range(Math.min(a.x,b.x)-radius,Math.max(a.x,b.x)+radius);
      const [minY,maxY]=range(Math.min(a.y,b.y)-radius,Math.max(a.y,b.y)+radius);
      for(let x=minX;x<=maxX;x++)for(let y=minY;y<=maxY;y++){
        const key=cellKey(x,y);
        if(!cells.has(key))cells.set(key,[]);
        cells.get(key).push(segment);
      }
    }
  }
  return {cells,all};
}
function blocked(p,road,index){
  const key=cellKey(Math.floor(p.x/CELL),Math.floor(p.y/CELL));
  for(const seg of index.cells.get(key)||[]){
    const margin=seg.road.width*.5+(seg.road.shoulder||0)*.5+
      Math.min(road.width*.16,6)+2;
    if(pointSegment(p,seg.a,seg.b).distance<=margin)return true;
  }
  return false;
}
const almost=(a,b)=>distance(a,b)<.01;
function insert(path,p){
  if(!path.length||!almost(path.at(-1),p))path.push(p);
}
function border(a,b,blockedAtA,road,index){
  // Find a clean termination to sub-pixel precision; in particular, avoid
  // the scattered block appearance of equal-length cut fragments.
  let lo=a,hi=b;
  for(let i=0;i<11;i++){
    const mid={x:(lo.x+hi.x)*.5,y:(lo.y+hi.y)*.5};
    if(blocked(mid,road,index)===blockedAtA)lo=mid;
    else hi=mid;
  }
  return {x:(lo.x+hi.x)*.5,y:(lo.y+hi.y)*.5};
}
function splitLoose(road,index){
  const path=denseRoadPath(road,3);
  if(path.length<2)return [];
  const paths=[];
  let section=[];
  let wasBlocked=blocked(path[0],road,index);
  if(!wasBlocked)insert(section,path[0]);
  for(let i=1;i<path.length;i++){
    const p=path[i],q=path[i-1];
    const hidden=blocked(p,road,index);
    if(wasBlocked!==hidden){
      const edge=border(q,p,wasBlocked,road,index);
      if(!wasBlocked){
        insert(section,edge);
        if(section.length>1&&section.some((point,j)=>j>0&&distance(point,section[j-1])>.01))
          paths.push(section);
        section=[];
      }else{
        section=[edge];
      }
    }
    if(!hidden)insert(section,p);
    wasBlocked=hidden;
  }
  if(section.length>1&&section.some((point,j)=>j>0&&distance(point,section[j-1])>.01))
    paths.push(section);
  return paths;
}

/** Cached by immutable document.roads array; called from preview and export. */
export function roadPieces(roads){
  if(cache.has(roads))return cache.get(roads);
  const index=indexPaved(roads);
  const result=new Map();
  for(const road of roads){
    result.set(road.id,isLoose(road)?splitLoose(road,index):
      [denseRoadPath(road,11)]);
  }
  cache.set(roads,result);
  return result;
}

/** Convenience access for generated road-network and runtime export. */
export function visiblePieces(roads,road){
  return roadPieces(roads).get(road.id)||[];
}
