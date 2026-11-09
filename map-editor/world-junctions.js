/**
 * Derived, editable-road-safe junctions. v2 world JSON remains unchanged.
 * Detects centerline crosses, T-junction endpoints touching another road's
 * entire paved footprint, and endpoint joins. Parallel nearby streets are not
 * silently connected just because their wide shoulders touch.
 */
import {clamp,distance,pointSegment,roadIntersections,sampleRoad} from './world-geometry.js';
import {pavedVsLoose} from './world-road-priority.js';
const gridSize=160,MAX_WIDTH=160,MAX_SHOULDER=16;
const junctionCache=new WeakMap();
const gridKey=(x,y)=>x+','+y;
const norm=v=>Math.hypot(v.x,v.y)||1;
const unit=(a,b)=>{const n=norm({x:b.x-a.x,y:b.y-a.y});return {x:(b.x-a.x)/n,y:(b.y-a.y)/n};};
const dot=(a,b)=>a.x*b.x+a.y*b.y;
const cross=(a,b)=>a.x*b.y-a.y*b.x;
const bounds=(seg,extra=0)=>({
  minX:Math.min(seg.a.x,seg.b.x)-extra,maxX:Math.max(seg.a.x,seg.b.x)+extra,
  minY:Math.min(seg.a.y,seg.b.y)-extra,maxY:Math.max(seg.a.y,seg.b.y)+extra
});
const cells=b=>{
  const keys=[];
  for(let x=Math.floor(b.minX/gridSize);x<=Math.floor(b.maxX/gridSize);x++)
    for(let y=Math.floor(b.minY/gridSize);y<=Math.floor(b.maxY/gridSize);y++)keys.push(gridKey(x,y));
  return keys;
};
function roadSegmentIndex(roads){
  const grid=new Map(),paths=new Map();
  roads.forEach(road=>{
    const path=sampleRoad(road.points,road.smooth,18);
    paths.set(road.id,path);
    for(let i=1;i<path.length;i++){
      const a=path[i-1],b=path[i];
      if(distance(a,b)<1e-6)continue;
      const segment={a,b,road,tangent:unit(a,b)};
      for(const key of cells(bounds(segment))){
        if(!grid.has(key))grid.set(key,[]);
        grid.get(key).push(segment);
      }
    }
  });
  return {grid,paths};
}
function candidates(index,p,radius){
  const found=new Set();
  const area={minX:p.x-radius,minY:p.y-radius,maxX:p.x+radius,maxY:p.y+radius};
  for(const k of cells(area))for(const s of index.grid.get(k)||[])found.add(s);
  return found;
}
function tangentAt(index,road,p){
  let best=null;
  const search=Math.max(250,road.width*4);
  for(const s of candidates(index,p,search)){
    if(s.road!==road)continue;
    const hit=pointSegment(p,s.a,s.b);
    if(!best||hit.distance<best.distance)best={distance:hit.distance,tangent:s.tangent};
  }
  if(best)return best.tangent;
  const pts=index.paths.get(road.id)||road.points;
  return unit(pts[0],pts[1]);
}
function convexHull(points){
  const sorted=points.slice().sort((a,b)=>a.x-b.x||a.y-b.y);
  const product=(o,a,b)=>(a.x-o.x)*(b.y-o.y)-(a.y-o.y)*(b.x-o.x);
  const lower=[],upper=[];
  for(const p of sorted){
    while(lower.length>=2&&product(lower.at(-2),lower.at(-1),p)<=0)lower.pop();
    lower.push(p);
  }
  for(let i=sorted.length-1;i>=0;i--){
    const p=sorted[i];
    while(upper.length>=2&&product(upper.at(-2),upper.at(-1),p)<=0)upper.pop();
    upper.push(p);
  }
  lower.pop();upper.pop();
  return [...lower,...upper];
}
function polygonFor(j,index,byId){
  const involved=j.roads.map(id=>byId.get(id)).filter(Boolean);
  const center={x:j.x,y:j.y};
  const corners=[],roadsInfo=[];
  for(const road of involved){
    const tangent=tangentAt(index,road,center);
    roadsInfo.push({id:road.id,roadClass:road.roadClass,markings:road.markings,
      width:road.width,shoulder:road.shoulder,tangent,
      normal:{x:-tangent.y,y:tangent.x},lanes:road.lanes,surface:road.surface});
  }
  // The corners of the union of each pair of intersecting road strips form
  // a true pavement-shaped, bevelled junction instead of a circular blob.
  for(let i=0;i<roadsInfo.length;i++)for(let k=i+1;k<roadsInfo.length;k++){
    const a=roadsInfo[i],b=roadsInfo[k],det=cross(a.normal,b.normal);
    if(Math.abs(det)<.22)continue; // Collinear joins use the fallback apron.
    const aw=a.width/2+2.5,bw=b.width/2+2.5;
    const limit=Math.min(185,Math.max(a.width,b.width)*2+22);
    for(const sa of [-1,1])for(const sb of [-1,1]){
      const va=sa*aw,vb=sb*bw;
      const x=(va*b.normal.y-a.normal.y*vb)/det;
      const y=(a.normal.x*vb-va*b.normal.x)/det;
      const length=Math.hypot(x,y),factor=Math.min(1,limit/(length||1));
      corners.push({x:center.x+x*factor,y:center.y+y*factor});
    }
  }
  if(corners.length<3){
    const width=Math.max(20,...roadsInfo.map(x=>x.width));
    const radius=width*.62+6,segments=12;
    for(let i=0;i<segments;i++){
      const angle=i*Math.PI*2/segments;
      corners.push({x:j.x+Math.cos(angle)*radius,y:j.y+Math.sin(angle)*radius});
    }
  }
  // Match the dominant roadway rather than allowing object ordering to control
  // the visible asphalt color across crossings.
  const priority=r=>(r.surface==='track'?2:r.surface==='concrete'?3:r.surface==='asphalt'?4:1);
  const dominant=roadsInfo.slice().sort((a,b)=>priority(b)-priority(a)||b.width-a.width)[0];
  return {...j,kind:j.kind||'crossing',polygon:convexHull(corners),approaches:roadsInfo,
    surface:dominant?.surface||'asphalt',width:Math.max(...roadsInfo.map(r=>r.width)),
    radius:Math.max(...corners.map(p=>distance(p,center)))};
}
const keyPair=roads=>roads.slice().sort().join(':');
/** Returns a stable, deterministic set of merged intersection nodes. */
export function buildRoadJunctions(roads){
  if(!Array.isArray(roads)||!roads.length)return [];
  const cached=junctionCache.get(roads);
  if(cached)return cached;
  const index=roadSegmentIndex(roads),byId=new Map(roads.map(r=>[r.id,r]));
  const raw=roadIntersections(roads)
    .filter(j=>!pavedVsLoose(byId.get(j.roads[0]),byId.get(j.roads[1])))
    .map(j=>({...j,kind:'crossing'}));
  const byPair=new Map();
  for(const j of raw){
    const pair=keyPair(j.roads);
    if(!byPair.has(pair))byPair.set(pair,[]);
    byPair.get(pair).push(j);
  }
  // Add endpoints close enough for the two road footprints to physically
  // overlap, including T junctions that stop before reaching the centerline.
  // Suppress side-by-side lanes, whose shoulders may touch but do not join.
  for(const road of roads){
    const path=index.paths.get(road.id);
    if(!path||path.length<2)continue;
    for(const [p,ownTangent] of [[path[0],unit(path[0],path[1])],
      [path.at(-1),unit(path.at(-2),path.at(-1))]]){
      const bestByRoad=new Map();
      for(const s of candidates(index,p,MAX_WIDTH+MAX_SHOULDER*2+24)){
        if(s.road.id===road.id || pavedVsLoose(road,s.road))continue;
        const hit=pointSegment(p,s.a,s.b);
        const other=s.road,ends=index.paths.get(other.id);
        const isEnd=distance(p,ends[0])<=20||distance(p,ends.at(-1))<=20;
        const overlap=road.width/2+road.shoulder+other.width/2+other.shoulder+4;
        const angle=Math.abs(cross(ownTangent,s.tangent));
        if(hit.distance>overlap||(!isEnd&&angle<.27))continue;
        const prev=bestByRoad.get(other.id);
        if(!prev||hit.distance<prev.distance)
          bestByRoad.set(other.id,{x:(p.x+hit.x)/2,y:(p.y+hit.y)/2,roadId:other.id,
            distance:hit.distance,kind:isEnd?'endpoint':'tee'});
      }
      for(const hit of bestByRoad.values()){
        const pair=keyPair([road.id,hit.roadId]);
        const existing=byPair.get(pair)||[];
        const maxClose=Math.max(20,Math.min(road.width,byId.get(hit.roadId).width)*.65);
        if(existing.some(j=>distance(j,hit)<maxClose))continue;
        const j={x:hit.x,y:hit.y,roads:[road.id,hit.roadId],kind:hit.kind};
        raw.push(j);existing.push(j);byPair.set(pair,existing);
      }
    }
  }
  // Paved streets whose edges physically intersect but centerlines narrowly
  // miss also receive a real junction apron. Parallel neighboring lanes
  // stay separate; only angled overlaps are navigable merges.
  const examined=new Set();
  for(const road of roads){
    if(road.surface==='dirt'||road.surface==='gravel')continue;
    const path=index.paths.get(road.id);
    for(let i=1;i<path.length;i++){
      const a=path[i-1],b=path[i],mid={x:(a.x+b.x)*.5,y:(a.y+b.y)*.5};
      const here=unit(a,b);
      for(const other of candidates(index,mid,MAX_WIDTH+MAX_SHOULDER*2)){
        if(other.road===road || pavedVsLoose(road,other.road) ||
          other.road.surface==='dirt'||other.road.surface==='gravel')continue;
        const pair=keyPair([road.id,other.road.id]);
        const segmentKey=pair+':'+Math.floor(mid.x/12)+':'+Math.floor(mid.y/12);
        if(examined.has(segmentKey))continue;
        examined.add(segmentKey);
        if(Math.abs(cross(here,other.tangent))<.29)continue;
        const candidates2=[pointSegment(a,other.a,other.b),pointSegment(b,other.a,other.b)];
        const pOther=pointSegment(other.a,a,b),qOther=pointSegment(other.b,a,b);
        const nearest=[
          {p:a,q:candidates2[0],d:candidates2[0].distance},
          {p:b,q:candidates2[1],d:candidates2[1].distance},
          {p:other.a,q:pOther,d:pOther.distance},
          {p:other.b,q:qOther,d:qOther.distance}
        ].sort((x,y)=>x.d-y.d)[0];
        const overlap=road.width*.5+other.road.width*.5;
        if(nearest.d>overlap*.88)continue;
        const at={x:(nearest.p.x+nearest.q.x)*.5,y:(nearest.p.y+nearest.q.y)*.5};
        const prior=byPair.get(pair)||[];
        const separation=Math.max(18,Math.min(road.width,other.road.width)*.7);
        if(prior.some(node=>distance(node,at)<separation))continue;
        const joint={...at,roads:[road.id,other.road.id],kind:'overlap'};
        raw.push(joint);prior.push(joint);byPair.set(pair,prior);
      }
    }
  }
  // Combine nodes from several road pairs when their paving meets at one
  // physical junction. Nearby but separated junctions retain separate IDs.
  const nodes=[];
  for(const rawNode of raw){
    const threshold=Math.max(12,Math.min(...rawNode.roads.map(id=>byId.get(id)?.width||24))*.47);
    const nearby=nodes.find(j=>distance(j,rawNode)<=threshold);
    if(!nearby){
      nodes.push({x:rawNode.x,y:rawNode.y,roads:rawNode.roads.slice(),
        kind:rawNode.kind,_count:1});
    }else{
      const n=nearby._count;
      nearby.x=(nearby.x*n+rawNode.x)/(n+1);
      nearby.y=(nearby.y*n+rawNode.y)/(n+1);
      nearby._count++;
      for(const id of rawNode.roads)if(!nearby.roads.includes(id))nearby.roads.push(id);
      if(rawNode.kind==='crossing'||rawNode.kind==='overlap')nearby.kind='crossing';
      else if(rawNode.kind==='tee'&&nearby.kind==='endpoint')nearby.kind='tee';
    }
  }
  const detailed=nodes.map(j=>{
    const junction=polygonFor(j,index,byId);
    delete junction._count;
    junction.roads.sort();
    junction.id='junction-'+Math.round(junction.x*100)+'-'+Math.round(junction.y*100);
    return junction;
  }).sort((a,b)=>a.x-b.x||a.y-b.y);
  junctionCache.set(roads,detailed);
  return detailed;
}
