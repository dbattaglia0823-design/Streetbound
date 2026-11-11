/**
 * Reversible Morrow Coast / standalone editor environment presets.
 * All edits use normal world-v2 validation and create a single undo snapshot.
 * Roadside placement enforces shoulder clearance; don't manually put props
 * in an intersection or silently alter the production streamed world.
 */
import {createEntity,scatterVegetation,updateEntity} from './world-model.js';
import {sampleRoad,pointInPolygon,distance} from './world-geometry.js';
import {nearestRoadPlacement,roadwayClearance,placementFootprint,placeBesideRoad} from './world-road-placement.js';

const bounded=(v,min,max)=>Math.max(min,Math.min(max,v));
const pointInside=(doc,p,pad=40)=>p.x>=pad&&p.y>=pad&&
  p.x<=doc.world.width-pad&&p.y<=doc.world.height-pad;
const compatiblePosition=(doc,p)=>pointInside(doc,p,100);
const nearbyObjects=(doc,p,d)=>doc.props.some(a=>distance(a,p)<d);

function addProp(doc,type,name,p,scale=1){
  if(!compatiblePosition(doc,p)||nearbyObjects(doc,p,Math.max(25,scale*27)))return doc;
  const proposed={name,type,x:p.x,y:p.y,rotation:0,scale,assetId:''};
  try{
    // Preset generation explicitly chooses a safe road-aligned placement.
    // Manual creation/dragging elsewhere in the editor never uses this path.
    const next=createEntity(doc,'props',placeBesideRoad(doc,proposed));
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

function parkingLot(doc,anchor,{size=1,stallWidth=3.2,occupancy=.4,entranceWidth=8}={}){
  const hit=nearestRoadPlacement(doc,anchor,250);
  if(!hit)throw new RangeError('Place parking within 250 world units of a road.');
  const side=Math.sign((anchor.x-hit.x)*hit.normal.x+(anchor.y-hit.y)*hit.normal.y)||1;
  const outward={x:hit.normal.x*side,y:hit.normal.y*side};
  const requested={x:hit.x+outward.x*(hit.width/2+hit.shoulder+105*size),
    y:hit.y+outward.y*(hit.width/2+hit.shoulder+105*size)};
  if(!pointInside(doc,requested,115*size))
    throw new RangeError('The parking footprint would cross the world boundary.');
  if(nearbyObjects(doc,requested,110*size))
    throw new RangeError('Move this parking lot away from other scenery.');
  if(doc.name==='Morrow Coast'&&doc.props.length>=196)
    throw new RangeError('Morrow Coast supports at most 200 editor-authored scenery props.');
  // Place the lot before making its access road so it isn't pushed away
  // from the asphalt connection by the safety-placement system.
  let next=createEntity(doc,'props',{name:'Parking lot',type:'parking',
    x:requested.x,y:requested.y,rotation:0,scale:size,assetId:'',
    stallWidth,occupancy,entranceWidth});
  const original=next.props.at(-1);
  const near=nearestRoadPlacement(doc,original,300)||hit;
  const roadSide=Math.sign((original.x-near.x)*near.normal.x+
    (original.y-near.y)*near.normal.y)||side;
  const facing={x:near.normal.x*roadSide,y:near.normal.y*roadSide};
  // Parking artwork has its curb opening on local -X.
  next=updateEntity(next,original.id,{rotation:Math.atan2(facing.y,facing.x)*180/Math.PI});
  const lot=next.props.at(-1);
  const mouth={x:lot.x-facing.x*(19*size-1.4),
    y:lot.y-facing.y*(19*size-1.4)};
  const entrance={x:near.x,y:near.y};
  if(distance(entrance,mouth)<8)
    throw new RangeError('Parking access is too short.');
  next=createEntity(next,'roads',{name:'Parking access',roadClass:'service',
    surface:'asphalt',width:entranceWidth,lanes:1,shoulder:1,
    smooth:false,markings:false,points:[entrance,mouth]});
  let count=1;
  const lateral=near.tangent;
  for(const direction of [-1,1]){
    const lamp={x:lot.x+lateral.x*direction*(24*size)+facing.x*8,
      y:lot.y+lateral.y*direction*(24*size)+facing.y*8};
    const lit=addProp(next,'streetlight','Parking lighting',lamp,.75);
    if(lit!==next){next=lit;count++;}
    const landscape={x:lot.x+lateral.x*direction*(31*size)+facing.x*(13*size),
      y:lot.y+lateral.y*direction*(31*size)+facing.y*(13*size)};
    const planted=addProp(next,'bush','Parking landscaping',landscape,.9);
    if(planted!==next){next=planted;count++;}
  }
  const stalls=Math.max(3,Math.floor(38*size*.84/stallWidth));
  return {doc:next,count,roadsAdded:1,stallCapacity:stalls*2};
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
  preset,anchor,selectedId=null,density=1,parkingSize=1,stallWidth=3.2,
  occupancy=.4,entranceWidth=8
}={}){
  if(!ENVIRONMENT_PRESETS.some(p=>p.value===preset))
    throw new TypeError('Unknown environment preset');
  if(!anchor||!Number.isFinite(anchor.x)||!Number.isFinite(anchor.y))
    throw new TypeError('Choose a map location first.');
  const d=bounded(Number(density)||1,.35,2);
  if(preset==='forest'||preset==='coastal')
    return naturalLandscape(doc,selectedId,preset==='coastal',d);
  if(preset==='parking'){
    for(const [value,min,max,label] of [
      [parkingSize,.75,1.35,'lot size'],[stallWidth,2.6,5.2,'stall width'],
      [occupancy,0,1,'occupancy'],[entranceWidth,6,10,'entrance width']]){
      if(typeof value!=='number'||!Number.isFinite(value)||value<min||value>max)
        throw new RangeError('Invalid parking '+label+'.');
    }
    return parkingLot(doc,anchor,{size:parkingSize,stallWidth,occupancy,entranceWidth});
  }
  if(preset==='industrial')return industry(doc,anchor,d);
  const road=doc.roads.find(r=>r.id===selectedId)||
    doc.roads.find(r=>r.id===nearestRoadPlacement(doc,anchor,65)?.roadId);
  return placeRoadside(doc,road,d);
}
