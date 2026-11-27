/** Road-topology editing operations. Preserve the v2 road schema, stable IDs,
 * world bounds and undo/redo by returning immutable documents.
 * Only unambiguous end-to-end connections with matching road design are joined.
 * T junctions and crossings remain separate roads and retain their branches.
 */
import {createEntity,updateEntity,removeEntity} from './world-model.js';
import {junctionLayer,roadElevation} from './world-road-elevation.js';
import {distance} from './world-geometry.js';
import {roadInsertCandidate} from './world-edit-tools.js';

const EPS=1e-5;
const roadLength=points=>points.slice(1).reduce((total,p,i)=>total+distance(p,points[i]),0);
const closed=road=>road.points.length>2&&distance(road.points[0],road.points.at(-1))<EPS;
const flatLayer=road=>{
  const {start_layer,end_layer}=roadElevation(road);
  return !road.elevation?.point_layers&&start_layer===end_layer?start_layer:null;
};
const compatible=(a,b)=>!a.jump&&!b.jump&&flatLayer(a)!==null&&flatLayer(a)===flatLayer(b)&&a.roadClass===b.roadClass&&a.surface===b.surface&&
  a.lanes===b.lanes&&a.smooth===b.smooth&&a.markings===b.markings&&
  Math.abs(a.width-b.width)<EPS&&Math.abs(a.shoulder-b.shoulder)<EPS;
const endpoints=(road)=>[
  {road,index:0,point:road.points[0]},
  {road,index:road.points.length-1,point:road.points.at(-1)}
];

/** Join a selected road with a compatible road when exactly two endpoints
 * participate at the join. Keep the selected road's ID and all other entities.
 * Never merge branches or already-closed road loops.
 */
export function joinRoadEndpoints(doc,roadId,{radius=1}={}){
  const target=doc.roads.find(r=>r.id===roadId);
  if(!target)throw new TypeError('Select a road to join');
  if(closed(target)||target.junctionStart||target.junctionEnd||target.roadClass==='onramp')return {doc,joined:false,roadId};
  if(!Number.isFinite(radius)||radius<0||radius>40)throw new RangeError('Invalid snap radius');
  const possibilities=[];
  for(const a of endpoints(target)){
    for(const road of doc.roads){
      if(road.id===target.id||closed(road)||road.junctionStart||road.junctionEnd||road.roadClass==='onramp'||!compatible(target,road))continue;
      for(const b of endpoints(road)){
        const gap=distance(a.point,b.point);
        if(gap>radius)continue;
        // A point shared with three or more road ends is a genuine junction,
        // never a single editable road; don't accidentally delete its branches.
        const participants=doc.roads.flatMap(other=>endpoints(other).filter(end=>
          junctionLayer(other,end.point)===flatLayer(target)&&
          (distance(end.point,a.point)<=radius||distance(end.point,b.point)<=radius)));
        if(new Set(participants.map(end=>end.road.id)).size!==2)continue;
        possibilities.push({a,b,gap});
      }
    }
  }
  // A new connector can touch separate roads at BOTH ends, or bridge two
  // ends of the same road into a closed circuit. Join one end at a time; the
  // editor may call this again to combine its remaining endpoint. A genuine
  // 3-way junction is rejected by the participant check above.
  const distinct=new Map();
  for(const match of possibilities){
    const key=match.a.index+':'+match.b.road.id+':'+match.b.index;
    if(!distinct.has(key))distinct.set(key,match);
  }
  const matches=[...distinct.values()].sort((x,y)=>x.a.index-y.a.index||x.gap-y.gap);
  if(!matches.length)return {doc,joined:false,roadId};
  if(matches.filter(m=>m.a.index===matches[0].a.index).length!==1)
    return {doc,joined:false,roadId};
  const {a,b}=matches[0];
  const left=a.index===0?[...target.points].reverse():target.points.slice();
  const right=b.index===0?b.road.points.slice():[...b.road.points].reverse();
  const shared=left.at(-1);
  const combined=[...left,...right.slice(1)];
  if(combined.length>100)
    throw new RangeError('Joined road exceeds 100 control points. Simplify or split it first.');
  // Use the existing endpoint exactly. The second road's first segment starts
  // from this same coordinate even when its authoring direction is reversed.
  const updated=updateEntity(doc,target.id,{points:combined});
  const next=removeEntity(updated,b.road.id);
  return {doc:next,joined:true,roadId:target.id,removedRoadId:b.road.id,
    point:shared};
}

/** Split a road at any on-curve position, or precisely at an existing interior
 * control point. Both resulting roads share one endpoint; either can be edited
 * or joined again. Existing road ID is retained for the first half.
 */
export function splitRoadAt(doc,roadId,at,{maxDistance=24}={}){
  const road=doc.roads.find(r=>r.id===roadId);
  if(!road)throw new TypeError('Select a road to split');
  if(road.jump)throw new RangeError('Remove the jump before splitting its road');
  if(doc.roads.length>=180)throw new RangeError('Maximum 180 roads reached');
  if(road.junctionStart||road.junctionEnd||road.roadClass==='onramp')throw new RangeError('Reset junction modes to Automatic before splitting this road');
  if(flatLayer(road)===null)throw new RangeError('Set the ramp to a flat layer before splitting it');
  if(closed(road))throw new RangeError('Open the loop by deleting its closing point before splitting');
  let points=road.points.slice(),index;
  if(typeof at==='number'){
    if(!Number.isInteger(at)||at<=0||at>=points.length-1)
      throw new RangeError('Choose an interior road point');
    index=at;
  }else{
    if(!at||!Number.isFinite(at.x)||!Number.isFinite(at.y))
      throw new TypeError('Invalid split position');
    if(at.x<0||at.y<0||at.x>doc.world.width||at.y>doc.world.height)
      throw new RangeError('Split point outside world');
    const existing=points.findIndex((p,i)=>i>0&&i<points.length-1&&distance(p,at)<=Math.min(maxDistance,2));
    if(existing>=0)index=existing;
    else{
      const candidate=roadInsertCandidate(road,at);
      if(!candidate||candidate.distance>maxDistance)
        throw new RangeError('Click on the selected road to split it');
      index=candidate.index;
      points.splice(index,0,{x:candidate.x,y:candidate.y});
    }
  }
  const first=points.slice(0,index+1),second=points.slice(index);
  if(first.length<2||second.length<2||
    roadLength(first)<1||roadLength(second)<1)
    throw new RangeError('Split must leave a usable road on both sides');
  const base={...road};delete base.id;
  const updated=updateEntity(doc,road.id,{points:first});
  const next=createEntity(updated,'roads',{...base,name:road.name+' (2)',points:second});
  return {doc:next,roadId:road.id,newRoadId:next.roads.at(-1).id,
    point:first.at(-1),index};
}


/** Editable point heights use the same signed layers as existing ramps.
 * A persistent profile stays on the same authored road; the production
 * bake derives its runtime grade sections.
 */
export function pointElevationLayers(road){
  const {start_layer,end_layer}=roadElevation(road);
  if(road.elevation?.point_layers)return [...road.elevation.point_layers];
  const total=roadLength(road.points);
  let station=0;
  return road.points.map((p,i)=>{
    if(i)station+=distance(road.points[i-1],p);
    return Math.round(start_layer+(end_layer-start_layer)*station/Math.max(total,.001));
  });
}

export function applyPointElevations(doc,roadId,layers){
  const road=doc.roads.find(r=>r.id===roadId);
  if(!road)throw new TypeError('Select a road');
  if(!Array.isArray(layers)||layers.length!==road.points.length||
      layers.some(n=>!Number.isInteger(n)||Math.abs(n)>2))
    throw new RangeError('Choose a layer from -2 to +2 for every road point');
  if(road.jump)throw new RangeError('Remove the stunt jump before applying point elevations');
  if(closed(road)&&layers.some(n=>n!==layers[0]))
    throw new RangeError('Open the road loop before assigning different point elevations');
  if(road.roadClass==='onramp'&&layers.length>2&&layers.some(v=>v!==layers[0]))
    throw new RangeError('Use a regular road for a multi-grade on-ramp');
  return updateEntity(doc,roadId,{elevation:{start_layer:layers[0],end_layer:layers.at(-1),point_layers:[...layers]}});
}

/** Convert a single ground-level paved road to a covered tunnel.
 * Preserve original anchors, endpoints, road ID, lane count and materials.
 * The production grade compiler derives the connected approach sections.
 */
export function convertRoadToTunnel(doc,roadId){return convertRoadToGrade(doc,roadId,-1);}

function convertRoadToGrade(doc,roadId,deckLayer){
  const road=doc.roads.find(r=>r.id===roadId);
  if(!road)throw new TypeError('Select a road');
  if(road.jump||road.autoGuardrails)throw new RangeError('Remove legacy jumps and auto guardrails before converting to a tunnel');
  if(road.elevation)throw new RangeError('Reset existing road elevations before converting to a tunnel');
  if(road.roadClass==='onramp'||!['asphalt','concrete'].includes(road.surface))
    throw new RangeError('Select a regular paved road for a tunnel');
  const points=[...road.points],start=points[0],finish=points.at(-1);
  if(distance(start,finish)<.12)throw new RangeError('Open a closed road before converting to a tunnel');
  const firstLength=distance(start,points[1]),lastLength=distance(finish,points.at(-2));
  if(firstLength<50||lastLength<50)throw new RangeError('Each road end needs a control-point span of at least 50 m');
  let firstRamp=Math.min(75,Math.max(50,firstLength-5)),lastRamp=Math.min(75,Math.max(50,lastLength-5));
  if(points.length===2){
    if(firstLength<110)throw new RangeError('A tunnel needs at least 110 m for both ramps and the covered road');
    firstRamp=lastRamp=Math.min(75,(firstLength-10)/2);
  }
  const interpolate=(a,b,t)=>({x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t});
  const entry=interpolate(start,points[1],firstRamp/firstLength);
  const exit=interpolate(finish,points.at(-2),lastRamp/lastLength);
  if(points.length===2)points.splice(1,0,entry,exit);
  else{
    if(firstLength-firstRamp>.001)points.splice(1,0,entry);
    if(lastLength-lastRamp>.001)points.splice(points.length-1,0,exit);
  }
  if(points.length<4||points.length>100||roadLength(points.slice(1,-1))<4)
    throw new RangeError('Tunnel needs distinct portals, at least 4 m of covered road and at most 100 control points');
  const layers=points.map((_,i)=>i===0||i===points.length-1?0:deckLayer);
  return updateEntity(doc,roadId,{points,elevation:{start_layer:0,end_layer:0,point_layers:layers}});
}


export function roadStructure(road){
  const profile=road.elevation;
  if(!profile)return 'regular';
  const {start_layer:a,end_layer:b,point_layers:layers=[]}=profile;
  if(a===-1&&b===-1&&layers.every(v=>v===-1))return 'underground';
  if(a===0&&b===0&&layers.includes(-1)&&!layers.includes(1))return 'tunnel';
  if(a===0&&b===0&&layers.includes(1)&&!layers.includes(-1))return 'overpass';
  if(a===1&&b===1&&layers.every(v=>v===1))return 'overpass';
  return 'legacy';
}

export function setRoadStructure(doc,roadId,kind){
  const road=doc.roads.find(r=>r.id===roadId);
  if(!road||!['regular','tunnel','underground','overpass'].includes(kind))throw new RangeError('Select a road structure');
  const previous=roadStructure(road);
  if(kind===previous)return doc;
  if(kind==='regular')return updateEntity(doc,roadId,{elevation:undefined});
  if(road.jump||road.autoGuardrails||road.roadClass==='onramp'||!['asphalt','concrete'].includes(road.surface))
    throw new RangeError('Use a regular paved road without a legacy jump or auto guardrails');
  if(kind==='underground')return updateEntity(doc,roadId,{width:Math.max(36,road.width),elevation:{start_layer:-1,end_layer:-1}});
  if(['tunnel','overpass'].includes(previous)&&road.elevation.point_layers&&road.elevation.start_layer===0&&road.elevation.end_layer===0)
    return updateEntity(doc,roadId,{elevation:{start_layer:0,end_layer:0,point_layers:road.elevation.point_layers.map(v=>-v)}});
  return convertRoadToGrade(updateEntity(doc,roadId,{elevation:undefined}),roadId,kind==='tunnel'?-1:1);
}
