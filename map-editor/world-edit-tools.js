/** Focused geometry-edit and scenery-brush operations for World Forge v2.
 * All operations are immutable. The editor groups many brush samples into one undo step.
 */
import {getEntity,createEntity,updateEntity} from './world-model.js';
import {boundsOf,clamp,distance,pointSegment,regionAt,roadAt,sampleRoad} from './world-geometry.js';
import {placeBesideRoad,placementFootprint,roadwayClearance} from './world-road-placement.js';

const shapeType = type => type==='roads'||type==='regions';
const bounded = (v,min,max)=>clamp(v,min,max);
const inWorld=(doc,p)=>p.x>=0&&p.y>=0&&p.x<=doc.world.width&&p.y<=doc.world.height;

/** Associate each sampled centerline segment with the original editable control span.
 * Unlike nearestOnPath(), this remains correct for a strongly curved spline.
 */
export function roadInsertCandidate(road,position) {
  if(!road || !Array.isArray(road.points) || road.points.length<2)return null;
  const sampled=sampleRoad(road.points,road.smooth,9);
  let cursor=0, best=null;
  for(let i=0;i<road.points.length-1;i++){
    const length=distance(road.points[i],road.points[i+1]);
    const steps=road.smooth&&road.points.length>2 ? clamp(Math.ceil(length/9),2,80):1;
    for(let j=0;j<steps;j++){
      const hit=pointSegment(position,sampled[cursor+j],sampled[cursor+j+1]);
      if(!best||hit.distance<best.distance) best={index:i+1,x:hit.x,y:hit.y,distance:hit.distance};
    }
    cursor+=steps;
  }
  return best;
}
/** Terrain edges include their closing segment. */
export function regionInsertCandidate(region,position){
  if(!region||region.points.length<3)return null;
  const path=region.points;let best=null;
  for(let i=0;i<path.length;i++){
    const hit=pointSegment(position,path[i],path[(i+1)%path.length]);
    if(!best||hit.distance<best.distance)best={index:i+1,x:hit.x,y:hit.y,distance:hit.distance};
  }
  return best;
}
export function insertShapePoint(doc,id,pos,{mode='between',maxDistance=24}={}){
  const found=getEntity(doc,id);
  if(!found||!shapeType(found.type))throw new TypeError('Select a road or terrain region');
  if(!inWorld(doc,pos))throw new RangeError('Point must be inside the world');
  let index,point=pos;
  if(mode==='start'||mode==='end'){
    if(found.type!=='roads')throw new TypeError('Only roads have extendable endpoints');
    index=mode==='start'?0:found.item.points.length;
  }else{
    if(mode!=='between')throw new TypeError('Unknown insertion mode');
    const near=found.type==='roads'?roadInsertCandidate(found.item,pos):regionInsertCandidate(found.item,pos);
    if(!near||near.distance>maxDistance)throw new RangeError('Click close to the selected road or region edge');
    index=near.index;point={x:near.x,y:near.y};
  }
  const points=found.item.points.slice();
  const max=found.type==='roads'?100:180;
  if(points.length>=max)throw new RangeError('Too many control points');
  points.splice(index,0,point);
  return {doc:updateEntity(doc,id,{points}),index,point};
}
/** Translate an entire road/region without changing curve/area, constrained to world bounds. */
export function translateEntity(doc,id,dx,dy){
  const found=getEntity(doc,id);
  if(!found)return doc;
  if(!Number.isFinite(dx)||!Number.isFinite(dy))throw new TypeError('Invalid movement');
  const {type,item}=found;
  if(shapeType(type)){
    const b=boundsOf(item.points);
    const tx=bounded(dx,-b.minX,doc.world.width-b.maxX);
    const ty=bounded(dy,-b.minY,doc.world.height-b.maxY);
    if(!tx&&!ty)return doc;
    return updateEntity(doc,id,{points:item.points.map(p=>({x:p.x+tx,y:p.y+ty}))});
  }
  const x=bounded(item.x+dx,0,doc.world.width),y=bounded(item.y+dy,0,doc.world.height);
  return x===item.x&&y===item.y?doc:updateEntity(doc,id,{x,y});
}
export function duplicateEntity(doc,id,offset=40){
  const found=getEntity(doc,id);
  if(!found)throw new TypeError('Select an entity to duplicate');
  if(!Number.isFinite(offset)||offset<0||offset>500)throw new RangeError('Invalid duplicate offset');
  const {type,item}=found;
  const clone={...item,name:(item.name+' copy').slice(0,80)};
  if(shapeType(type)){
    const b=boundsOf(item.points);
    const dx=b.maxX+offset<=doc.world.width?offset:(b.minX-offset>=0?-offset:0);
    const dy=b.maxY+offset<=doc.world.height?offset:(b.minY-offset>=0?-offset:0);
    clone.points=item.points.map(p=>({x:p.x+dx,y:p.y+dy}));
  }else{
    clone.x=bounded(item.x+(item.x+offset<=doc.world.width?offset:-offset),0,doc.world.width);
    clone.y=bounded(item.y+(item.y+offset<=doc.world.height?offset:-offset),0,doc.world.height);
    if(type==='markers')clone.properties=structuredClone(item.properties);
  }
  // Copies of adopted procedural scenery become new authored placements,
  // never a second claim on the same source object.
  if(type==='props'){delete clone.replaces;delete clone.hidden;}
  delete clone.id;
  const next=createEntity(doc,type,clone);
  return {doc:next,id:next[type].at(-1).id};
}
const validateBrush=(doc,opts)=>{
  const allowed=['oak','pine','palm','bush','rock','boulder','house','building','warehouse',
    'garage','gas_station','streetlight','sign','barrier','dock','parking'];
  if(!allowed.includes(opts.type))throw new TypeError('Unsupported scenery type');
  const radius=opts.radius??50,spacing=opts.spacing??32,count=opts.count??3;
  if(!Number.isFinite(radius)||radius<8||radius>250)throw new RangeError('Brush radius must be 8–250');
  if(!Number.isFinite(spacing)||spacing<5||spacing>200)throw new RangeError('Minimum spacing must be 5–200');
  if(!Number.isInteger(count)||count<1||count>24)throw new RangeError('Brush density must be 1–24');
  const assetId=opts.assetId||'';
  if(assetId&&!doc.assets.some(a=>a.id===assetId))throw new TypeError('Unknown scenery artwork');
  return {radius,spacing,count,assetId};
};
/** Paint random objects in a continuous circular footprint, keeping configurable
 * spacing, keeping roads clear and optionally excluding bodies of water.
 * No mutation of existing props or world format.
 */
export function paintSceneryBrush(doc,center,opts,random=Math.random){
  const {radius,spacing,count,assetId}=validateBrush(doc,opts);
  if(!inWorld(doc,center))return doc;
  let next=doc;
  const variation=opts.variation!==false;
  const avoidRoads=opts.avoidRoads!==false,avoidWater=opts.avoidWater!==false;
  let painted=0;
  for(let attempt=0;attempt<count*12&&painted<count&&next.props.length<4000;attempt++){
    const angle=random()*2*Math.PI,extent=radius*Math.sqrt(random());
    const p={x:center.x+Math.cos(angle)*extent,y:center.y+Math.sin(angle)*extent};
    if(!inWorld(next,p))continue;
    const rotation=variation?Math.round((random()*360-180)*10)/10:0;
    const scale=variation?Math.round((.75+random()*.55)*100)/100:1;
    const proposed={type:opts.type,assetId,name:opts.type.replaceAll('_',' '),
      x:+p.x.toFixed(2),y:+p.y.toFixed(2),rotation,scale};
    let placed;
    try{placed=placeBesideRoad(next,proposed);}
    catch{continue;}
    if(avoidRoads&&roadwayClearance(next,placed,placementFootprint(next,placed))<0)continue;
    const region=avoidWater?regionAt(next,placed):null;
    if(region&&(region.biome==='ocean'||region.biome==='lake'))continue;
    if(distance(placed,center)>radius+placementFootprint(next,placed)*.5)continue;
    if(next.props.some(other=>Math.abs(other.x-placed.x)<spacing&&Math.abs(other.y-placed.y)<spacing&&
      distance(other,placed)<spacing))continue;
    next=createEntity(next,'props',placed);
    painted++;
  }
  return next;
}
export function eraseSceneryBrush(doc,center,radius=50){
  if(!Number.isFinite(radius)||radius<8||radius>250)throw new RangeError('Invalid eraser radius');
  const props=doc.props.filter(p=>distance(center,p)>radius);
  return props.length===doc.props.length?doc:{...doc,props};
}
