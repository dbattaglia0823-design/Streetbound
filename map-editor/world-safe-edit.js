/** Non-destructive editing helpers used by the Streetbound map builder.
 * These never connect loose surfaces (dirt/gravel) with paved surfaces.
 * A candidate is intentionally conservative: only nearby ROAD ENDPOINTS
 * are auto-repaired; mid-curve T junctions remain editable manually.
 */
import {distance,pointSegment,sampleRoad,clamp} from './world-geometry.js';
import {normalizeWorld} from './world-model.js';

export const looseSurface=surface=>surface==='dirt'||surface==='gravel';
const sameNetwork=(a,b)=>looseSurface(a.surface)===looseSurface(b.surface);
const pathEndpoints=doc=>doc.roads.flatMap(road=>[
  {road,endpoint:0,point:road.points[0]},
  {road,endpoint:road.points.length-1,point:road.points.at(-1)}
]);

/** Pair candidates for intentional, same-network, endpoint-to-endpoint snaps.
 * Ambiguous clusters (equally near several ends) remain for manual repair.
 */
export function findEndpointGaps(doc,{min=2,max=24}={}){
  const ends=pathEndpoints(doc),proposals=[];
  for(let i=0;i<ends.length;i++){
    const from=ends[i],neighbors=[];
    for(let j=0;j<ends.length;j++){
      if(i===j)continue;
      const target=ends[j];
      if(from.road.id===target.road.id||!sameNetwork(from.road,target.road))continue;
      const gap=distance(from.point,target.point);
      if(gap>min&&gap<=max)neighbors.push({target,gap});
    }
    neighbors.sort((a,b)=>a.gap-b.gap||a.target.road.id.localeCompare(b.target.road.id));
    if(!neighbors.length)continue;
    const best=neighbors[0];
    if(neighbors[1]&&neighbors[1].gap<best.gap*1.35+1)continue;
    proposals.push({roadId:from.road.id,endpoint:from.endpoint,
      targetRoadId:best.target.road.id,targetEndpoint:best.target.endpoint,
      from:from.point,to:best.target.point,distance:best.gap});
  }
  // Deduplicate symmetric pairs. For a pair, move the later road's endpoint
  // toward the earlier road's endpoint; the target is never simultaneously moved.
  const pairs=new Map();
  for(const c of proposals){
    const a=c.roadId+':'+c.endpoint,b=c.targetRoadId+':'+c.targetEndpoint;
    const key=[a,b].sort().join('|');
    if(!pairs.has(key)||a>b)pairs.set(key,c);
  }
  return [...pairs.values()].sort((a,b)=>a.distance-b.distance||
    a.roadId.localeCompare(b.roadId));
}

export function snapSafeEndpoints(doc,{max=24}={}){
  const candidates=findEndpointGaps(doc,{max}),used=new Set(),changed=new Map(),applied=[];
  for(const item of candidates){
    const a=item.roadId+':'+item.endpoint,b=item.targetRoadId+':'+item.targetEndpoint;
    if(used.has(a)||used.has(b))continue;
    used.add(a);used.add(b);
    // Each endpoint can be moved only once, preventing chain reactions.
    const road=changed.get(item.roadId)||doc.roads.find(r=>r.id===item.roadId);
    if(!road)continue;
    const points=road.points.slice();
    points[item.endpoint]={x:item.to.x,y:item.to.y};
    changed.set(item.roadId,{...road,points});
    applied.push(item);
  }
  if(!applied.length)return {doc,count:0,applied};
  const next=normalizeWorld({...doc,roads:doc.roads.map(r=>changed.get(r.id)||r)});
  return {doc:next,count:applied.length,applied};
}

/** Remove adjacent duplicate control points without changing valid loops or
 * smoothing unrelated spans. Requires at least two distinct points per road.
 */
export function cleanDuplicateRoadPoints(doc,{threshold=0.75}={}){
  let removed=0;
  const roads=doc.roads.map(road=>{
    const points=[road.points[0]];
    for(const p of road.points.slice(1)){
      if(distance(points.at(-1),p)<threshold){removed++;continue;}
      points.push(p);
    }
    return points.length>=2?{...road,points}:road;
  });
  return {doc:removed?normalizeWorld({...doc,roads}):doc,removed};
}

/** Smart *draw-time* snapping never joins dirt to pavement. Prefer existing
 * endpoints (reliable network IDs) before the interior of a centerline.
 */
export function smartRoadSnap(doc,point,surface,{radius=22,includeMidpoints=true}={}){
  const within=clamp(radius,4,40),same=doc.roads.filter(road=>
    looseSurface(surface)===looseSurface(road.surface));
  let best=null;
  for(const road of same){
    for(const end of [road.points[0],road.points.at(-1)]){
      const gap=distance(point,end);
      if(gap<=within&&(!best||gap<best.distance))
        best={x:end.x,y:end.y,kind:'endpoint',roadId:road.id,roadName:road.name,distance:gap};
    }
  }
  if(best||!includeMidpoints)return best;
  const midRadius=Math.min(within,14);
  for(const road of same){
    const points=sampleRoad(road.points,road.smooth,15);
    for(let i=1;i<points.length;i++){
      const hit=pointSegment(point,points[i-1],points[i]);
      if(hit.distance<=midRadius&&(!best||hit.distance<best.distance))
        best={x:hit.x,y:hit.y,kind:'centerline',roadId:road.id,
          roadName:road.name,distance:hit.distance};
    }
  }
  return best;
}

/** Inform before a destructive-looking drag, without changing source state. */
export function largeDragDistance(before,after,roadId){
  const prior=before.roads.find(r=>r.id===roadId);
  const newer=after.roads.find(r=>r.id===roadId);
  if(!prior||!newer||prior.points.length!==newer.points.length)return 0;
  return Math.max(0,...prior.points.map((p,i)=>distance(p,newer.points[i])));
}
