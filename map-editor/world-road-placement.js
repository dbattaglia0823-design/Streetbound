/**
 * Collision-aware freeform roadside placement for World Forge v2.
 * No tiles and no changes to the persisted world schema.
 *
 * A spatial index follows the immutable roads array. Geometry is sampled with the
 * same Catmull-Rom road function used to draw/export curves. Props are represented
 * by conservative circular footprint bounds; passing this check guarantees their
 * approximate sprite bounds cannot extend onto a roadway or its shoulder.
 */
import {clamp, distance, pointSegment, sampleRoad} from './world-geometry.js';

const CELL=160, BUFFER=9, MAX_ROAD_HALF_WIDTH=100;
const roadIndexes=new WeakMap();
const key=(x,y)=>x+','+y;
const buildingTypes=new Set(['house','building','warehouse','garage','gas_station','parking','dock']);
const alignedTypes=new Set(['house','building','warehouse','garage','gas_station','parking',
  'barrier','sign','streetlight','dock']);
const footprints={
  oak:[96,96],pine:[56,72],palm:[72,72],bush:[40,40],
  rock:[34,32],boulder:[58,58],house:[66,54],building:[92,104],
  warehouse:[139,86],garage:[100,80],gas_station:[95,70],parking:[139,106],
  streetlight:[16,16],sign:[40,27],barrier:[60,18],dock:[44,130]
};
const inside=(doc,p,r=0)=>p.x>=r&&p.y>=r&&p.x<=doc.world.width-r&&p.y<=doc.world.height-r;
export const normalizeAngle=angle=>((angle+180)%360+360)%360-180;
export function placementFootprint(doc,prop){
  let [w,h]=footprints[prop.type]||[70,70];
  if(prop.assetId){
    const asset=doc.assets.find(a=>a.id===prop.assetId);
    if(asset){
      const longest=buildingTypes.has(prop.type)||prop.type==='gas_station'?132:65;
      const factor=longest/Math.max(asset.width,asset.height);
      w=asset.width*factor;h=asset.height*factor;
    }
  }
  // Conservative radius: safe for any rotation, including later manual rotation.
  const scale=(prop.scale??1)*(prop.type==='building'||prop.type==='warehouse'?1.2:1);
  return Math.ceil(Math.hypot(w,h)*scale/2)+2;
}
function getIndex(doc){
  let cached=roadIndexes.get(doc.roads);
  if(cached)return cached;
  const grid=new Map();
  let highest=0;
  for(const road of doc.roads){
    highest=Math.max(highest,road.width/2+road.shoulder);
    const centerline=sampleRoad(road.points,road.smooth,9);
    for(let i=1;i<centerline.length;i++){
      const a=centerline[i-1],b=centerline[i],dx=b.x-a.x,dy=b.y-a.y;
      const length=Math.hypot(dx,dy);
      if(length<1e-6)continue;
      const seg={a,b,road,tx:dx/length,ty:dy/length};
      const minX=Math.floor(Math.min(a.x,b.x)/CELL),maxX=Math.floor(Math.max(a.x,b.x)/CELL);
      const minY=Math.floor(Math.min(a.y,b.y)/CELL),maxY=Math.floor(Math.max(a.y,b.y)/CELL);
      for(let x=minX;x<=maxX;x++)for(let y=minY;y<=maxY;y++){
        const k=key(x,y);
        if(!grid.has(k))grid.set(k,[]);
        grid.get(k).push(seg);
      }
    }
  }
  cached={grid,highest:Math.min(MAX_ROAD_HALF_WIDTH,highest)};
  roadIndexes.set(doc.roads,cached);
  return cached;
}
function nearby(doc,p,radius){
  const index=getIndex(doc),found=new Set();
  for(let x=Math.floor((p.x-radius)/CELL);x<=Math.floor((p.x+radius)/CELL);x++)
    for(let y=Math.floor((p.y-radius)/CELL);y<=Math.floor((p.y+radius)/CELL);y++)
      for(const seg of index.grid.get(key(x,y))||[])found.add(seg);
  return found;
}
export function nearestRoadPlacement(doc,p,maxDistance=500){
  if(!doc.roads.length)return null;
  let best=null;
  for(const seg of nearby(doc,p,maxDistance)){
    const hit=pointSegment(p,seg.a,seg.b);
    if(hit.distance<=maxDistance&&(!best||hit.distance<best.distance)){
      best={x:hit.x,y:hit.y,distance:hit.distance,roadId:seg.road.id,
        width:seg.road.width,shoulder:seg.road.shoulder,
        tangent:{x:seg.tx,y:seg.ty},normal:{x:-seg.ty,y:seg.tx}};
    }
  }
  return best;
}
/** Minimum conservative clearance from the nearest roadway shoulder.
 * >= 0 is safe. A negative result means part of the footprint occupies road.
 */
export function roadwayClearance(doc,p,radius=0,excludedRoadIds=null){
  if(!doc.roads.length)return Infinity;
  if(!Number.isFinite(radius)||radius<0)throw new RangeError('Invalid footprint radius');
  const search=radius+getIndex(doc).highest+BUFFER;
  let result=Infinity;
  for(const seg of nearby(doc,p,search)){
    if(excludedRoadIds?.has(seg.road.id))continue;
    const gap=pointSegment(p,seg.a,seg.b).distance-
      (seg.road.width/2+seg.road.shoulder+radius+BUFFER);
    if(gap<result)result=gap;
  }
  return result;
}
function round2(n){return Math.round(n*100)/100;}
/** Snap structural props to the curb and rotate their authored top-down
 * "front" toward the road. Organic nature is only moved if it obstructs a road,
 * retaining its random rotation and forest spacing elsewhere.
 *
 * If a nearby intersection blocks the desired side, look along the road and
 * slightly farther out. Never fall back to a colliding position.
 */
export function placeBesideRoad(doc,input,{snap=true,align=true,maxSnapDistance=null,offsetRotation=0}={}){
  const prop={...input};
  if(!Number.isFinite(prop.x)||!Number.isFinite(prop.y)||!Number.isFinite(prop.scale??1))
    throw new TypeError('Invalid object position or scale');
  const radius=placementFootprint(doc,prop);
  const structural=alignedTypes.has(prop.type);
  const maxDistance=maxSnapDistance??(buildingTypes.has(prop.type)?520:structural?280:105);
  const original={x:prop.x,y:prop.y};
  const obstruction=roadwayClearance(doc,original,radius)<0;
  const near=nearestRoadPlacement(doc,original,Math.max(maxDistance,radius+MAX_ROAD_HALF_WIDTH+30));
  if(!near){
    if(obstruction)throw new RangeError('No safe roadside position could be found');
    return prop;
  }
  const shouldSnap=obstruction||(snap&&near.distance<=maxDistance);
  if(!shouldSnap){
    if(!inside(doc,original,0))throw new RangeError('Object outside world');
    return prop;
  }
  const projected=(original.x-near.x)*near.normal.x+(original.y-near.y)*near.normal.y;
  const primarySide=projected < 0?-1:1;
  const targetOffset=near.width/2+near.shoulder+radius+BUFFER+3;
  const normal=near.normal,tangent=near.tangent;
  let best=null;
  const candidates=[0,1,-1,2,-2,3,-3];
  // Prioritize the requested side; alternate if it is outside the map or blocked.
  search: for(const side of [primarySide,-primarySide]){
    for(const along of candidates){
      for(const extra of [0,20,50,95,150,230]){
        const p={
          x:round2(near.x+normal.x*side*(targetOffset+extra)+tangent.x*along*(radius*1.25+28)),
          y:round2(near.y+normal.y*side*(targetOffset+extra)+tangent.y*along*(radius*1.25+28))
        };
        if(!inside(doc,p,radius)||roadwayClearance(doc,p,radius)<0)continue;
        const dist=distance(p,original);
        const penalty=side===primarySide?0:45;
        const score=dist+penalty;
        if(!best||score<best.score)best={...p,side,score};
        if(along===0&&extra===0&&side===primarySide)break search;
      }
    }
  }
  if(!best)throw new RangeError('No open roadside location: try a wider area away from intersections');
  prop.x=best.x;prop.y=best.y;
  if(align&&structural){
    // Built-in facades face local +Y. Make them face across the street from
    // their side of the road, using the local spline segment tangent.
    const angle=Math.atan2(tangent.y,tangent.x)*180/Math.PI+(best.side>0?180:0);
    prop.rotation=round2(normalizeAngle(angle+offsetRotation));
  }
  return prop;
}
/** Kept as a backwards-compatible helper for existing integrations.
 * All gameplay markers are free overlays, never automatically repositioned.
 */
export function placeSiteMarker(_doc,marker){return marker;}
/** Reflow only props that overlap a newly edited road, or optionally align all
 * roadside buildings as part of an explicit repair operation. Never delete props.
 */
export function repairRoadsideObjects(doc,{alignAll=false}={}){
  let moved=0,rotated=0,failed=0;
  const props=doc.props.map(old=>{
    const radius=placementFootprint(doc,old);
    if(!alignAll&&roadwayClearance(doc,old,radius)>=0)return old;
    try{
      const next=placeBesideRoad(doc,old,{snap:true,align:alignAll,
        maxSnapDistance:alignAll?620:0});
      if(next.x===old.x&&next.y===old.y&&next.rotation===old.rotation)return old;
      if(next.x!==old.x||next.y!==old.y)moved++;
      else rotated++;
      return next;
    }catch{failed++;return old;}
  });
  // Marker positions are intentionally independent of all scenery repair.
  // Neither a road edit nor "Fix all overlaps" should silently move a marker.
  return {doc:moved||rotated?{...doc,props}:doc,
    moved,rotated,adjustedMarkers:0,failed};
}
  }):doc.markers;
  return {doc:moved||rotated||adjustedMarkers?{...doc,props,markers:nextMarkers}:doc,
    moved,rotated,adjustedMarkers,failed};
}
