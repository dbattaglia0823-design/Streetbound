/** Road-topology editing operations. Preserve the v2 road schema, stable IDs,
 * world bounds and undo/redo by returning immutable documents.
 * Only unambiguous end-to-end connections with matching road design are joined.
 * T junctions and crossings remain separate roads and retain their branches.
 */
import {createEntity,updateEntity,removeEntity} from './world-model.js';
import {distance} from './world-geometry.js';
import {roadInsertCandidate} from './world-edit-tools.js';

const EPS=1e-5;
const roadLength=points=>points.slice(1).reduce((total,p,i)=>total+distance(p,points[i]),0);
const closed=road=>road.points.length>2&&distance(road.points[0],road.points.at(-1))<EPS;
const compatible=(a,b)=>a.roadClass===b.roadClass&&a.surface===b.surface&&
  a.lanes===b.lanes&&a.smooth===b.smooth&&a.markings===b.markings&&
  Math.abs(a.width-b.width)<EPS&&Math.abs(a.shoulder-b.shoulder)<EPS;
const endpoints=(road)=>[
  {road,index:0,point:road.points[0]},
  {road,index:road.points.length-1,point:road.points.at(-1)}
];
const chooseId=(doc,desired)=>doc.roads.some(r=>r.id===desired)?desired:doc.roads.at(-1)?.id;

/** Join a selected road with ONE matching road when exactly two compatible
 * endpoints meet. Snap the shared endpoint, keep the selected road's ID and
 * all other entities untouched. Never merge branches or closed road loops.
 */
export function joinRoadEndpoints(doc,roadId,{radius=1}={}){
  const target=doc.roads.find(r=>r.id===roadId);
  if(!target)throw new TypeError('Select a road to join');
  if(closed(target))return {doc,joined:false,roadId};
  if(!Number.isFinite(radius)||radius<0||radius>40)throw new RangeError('Invalid snap radius');
  const possibilities=[];
  for(const a of endpoints(target)){
    for(const road of doc.roads){
      if(road.id===target.id||closed(road)||!compatible(target,road))continue;
      for(const b of endpoints(road)){
        const gap=distance(a.point,b.point);
        if(gap>radius)continue;
        // A point shared with three or more road ends is a genuine junction,
        // never a single editable road; don't accidentally delete its branches.
        const participants=doc.roads.flatMap(other=>endpoints(other).filter(end=>
          distance(end.point,a.point)<=radius||distance(end.point,b.point)<=radius));
        if(new Set(participants.map(end=>end.road.id)).size!==2)continue;
        possibilities.push({a,b,gap});
      }
    }
  }
  // Two distinct joins on the same selected road are ambiguous (possible ring
  // or parallel streets). Require the operator to split/rearrange them first.
  if(possibilities.length!==1)return {doc,joined:false,roadId};
  const {a,b}=possibilities[0];
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
  if(doc.roads.length>=180)throw new RangeError('Maximum 180 roads reached');
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
