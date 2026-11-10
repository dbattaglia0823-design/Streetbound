/**
 * Reversible Morrow Coast / standalone editor environment presets.
 * All edits use normal world-v2 validation and create a single undo snapshot.
 * Roadside placement enforces shoulder clearance; don't manually put props
 * in an intersection or silently alter the production streamed world.
 */
import {createEntity,scatterVegetation,updateEntity} from './world-model.js';
import {sampleRoad,pointInPolygon,distance} from './world-geometry.js';
import {nearestRoadPlacement,roadwayClearance,placementFootprint} from './world-road-placement.js';

const bounded=(v,min,max)=>Math.max(min,Math.min(max,v));
const pointInside=(doc,p,pad=40)=>p.x>=pad&&p.y>=pad&&
  p.x<=doc.world.width-pad&&p.y<=doc.world.height-pad;
const compatiblePosition=(doc,p)=>pointInside(doc,p,100);
const nearbyObjects=(doc,p,d)=>doc.props.some(a=>distance(a,p)<d);

function addProp(doc,type,name,p,scale=1){
  if(!compatiblePosition(doc,p)||nearbyObjects(doc,p,Math.max(25,scale*27)))return doc;
  const proposed={name,type,x:p.x,y:p.y,rotation:0,scale,assetId:''};
  try{
    const next=createEntity(doc,'props',proposed);
    const placed=next.props.at(-1);
    if(roadwayClearance(next,placed,placementFootprint(next,placed)) < -0.001)return doc;
    if(next.props.slice(0,-1).some(a=>distance(a,placed)<Math.min(26,placementFootprint(next,placed))))
      return doc;
    return next;
  }catch{return doc;}
}
const options=Object.freeze([
  ['street','City street furniture'],
  ['parking','Parking lot + access'],
  ['forest','Forest undergrowth'],
  ['coastal','Coastal landscaping'],
  ['industrial','Industrial roadside']
]);
export const ENVIRONMENT_PRESETS=options.map(([value,label])=>({value,label}));

function placeRoadside(doc,road,density=1){
  if(!road||road.roadClass!=='city'&&road.roadClass!=='country')
    throw new RangeError('Select a city or country road for this street preset.');
  const path=sampleRoad(road.points,road.smooth,12);
  const step=bounded(95/density,44,180);
  let travelled=0,station=step*.7,built=0;
  for(let i=1;i<path.length&&built<32;i++){
    const a=path[i-1],b=path[i],length=distance(a,b);
    if(length<.1)continue;
    while(station<=travelled+length && built<32){
      const t=(station-travelled)/length;
      const pos={x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t};
      const dx=(b.x-a.x)/length,dy=(b.y-a.y)/length;
      const sideways={x:-dy,y:dx};
      const clearance=road.width/2+road.shoulder+25;
      for(const side of [-1,1]){
        const p={x:pos.x+sideways.x*clearance*side,
          y:pos.y+sideways.y*clearance*side};
        const type=built%5===0?'sign':'streetlight';
        const next=addProp(doc,type,type==='sign'?'Street direction':'Curb lamp',p,.72);
        if(next!==doc){doc=next;built++;}
      }
      station+=step;
    }
    travelled+=length;
  }
  return {doc,count:built};
}

function parkingLot(doc,anchor){
  const hit=nearestRoadPlacement(doc,anchor,250);
  if(!hit)throw new RangeError('Place parking within 250 world units of a road.');
  const side=Math.sign((anchor.x-hit.x)*hit.normal.x+(anchor.y-hit.y)*hit.normal.y)||1;
  const outward={x:hit.normal.x*side,y:hit.normal.y*side};
  const depth=hit.width/2+hit.shoulder+105;
  const p={x:hit.x+outward.x*depth,y:hit.y+outward.y*depth};
  if(!pointInside(doc,p,115))throw new RangeError('The parking footprint would cross the world boundary.');
  if(nearbyObjects(doc,p,115))throw new RangeError('Move this parking lot away from other scenery.');
  const start={x:hit.x,y:hit.y};
  const end={x:hit.x+outward.x*(hit.width/2+48),y:hit.y+outward.y*(hit.width/2+48)};
  // A narrow dedicated asphalt access route touches the real street and
  // stops at the first parking bay; it does not extend through parked cars.
  let next=createEntity(doc,'roads',{name:'Parking access',roadClass:'service',
    surface:'asphalt',width:14,lanes:1,shoulder:1,
    smooth:false,markings:false,points:[start,end]});
  next=addProp(next,'parking','Parking lot',p,1);
  if(next.props.length===doc.props.length)
    throw new RangeError('No legal parking footprint here. Try a clearer roadside location.');
  let created=1;
  for(const sideOffset of [-42,42]){
    const sign={x:p.x+hit.tangent.x*sideOffset+outward.x*20,
      y:p.y+hit.tangent.y*sideOffset+outward.y*20};
    const adjusted=addProp(next,'streetlight','Parking lighting',sign,.75);
    if(adjusted!==next){next=adjusted;created++;}
  }
  return {doc:next,count:created,roadsAdded:1};
}

function naturalLandscape(doc,selectedId,coastal,density){
  const region=doc.regions.find(r=>r.id===selectedId);
  if(!region)throw new TypeError('Select a terrain region before applying a biome preset.');
  if(['ocean','lake'].includes(region.biome))
    throw new RangeError('Cannot place land vegetation in open water.');
  const biome=coastal?'beach':'forest';
  let next=updateEntity(doc,region.id,{biome});
  const count=bounded(Math.round(35*density),10,120);
  next=scatterVegetation(next,region.id,count,'auto');
  return {doc:next,count:next.props.length-doc.props.length,regionsUpdated:1};
}

function industry(doc,anchor,density){
  let next=doc,count=0;
  const positions=[
    {x:anchor.x-80,y:anchor.y-65,type:'warehouse'},
    {x:anchor.x+90,y:anchor.y+40,type:'building'},
    {x:anchor.x-22,y:anchor.y+87,type:'sign'},
    {x:anchor.x+130,y:anchor.y-70,type:'streetlight'}
  ];
  for(const item of positions.slice(0,density>.9?4:3)){
    const fresh=addProp(next,item.type,'Industrial '+item.type,{x:item.x,y:item.y},
      item.type==='warehouse'?.8:1);
    if(fresh!==next){next=fresh;count++;}
  }
  if(!count)throw new RangeError('No safe industrial building sites nearby.');
  return {doc:next,count};
}

export function applyEnvironmentPreset(doc,{
  preset,anchor,selectedId=null,density=1
}={}){
  if(!ENVIRONMENT_PRESETS.some(p=>p.value===preset))
    throw new TypeError('Unknown environment preset');
  if(!anchor||!Number.isFinite(anchor.x)||!Number.isFinite(anchor.y))
    throw new TypeError('Choose a map location first.');
  const d=bounded(Number(density)||1,.35,2);
  if(preset==='forest'||preset==='coastal')
    return naturalLandscape(doc,selectedId,preset==='coastal',d);
  if(preset==='parking')return parkingLot(doc,anchor);
  if(preset==='industrial')return industry(doc,anchor,d);
  const road=doc.roads.find(r=>r.id===selectedId)||
    doc.roads.find(r=>r.id===nearestRoadPlacement(doc,anchor,65)?.roadId);
  return placeRoadside(doc,road,d);
}
