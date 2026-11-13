/** Read-only automatic map output, computed from the CURRENT editable world.
 * No derived feature is ever written into authored roads, markers or props.
 * Per-array caches avoid rescanning every time the camera pans or zooms.
 */
import {buildRoadJunctions} from './world-junctions.js';
import {roadPieces,isLoose} from './world-road-priority.js';
import {findEndpointGaps} from './world-safe-edit.js';
import {roadwayClearance,placementFootprint} from './world-road-placement.js';

const roadsCache=new WeakMap(),clearanceCache=new WeakMap();
const inBounds=(p,b,pad=0)=>!b||(p.x>=b.minX-pad&&p.x<=b.maxX+pad&&
  p.y>=b.minY-pad&&p.y<=b.maxY+pad);

export function liveRoadAutomation(roads){
  let cached=roadsCache.get(roads);
  if(cached)return cached;
  const junctions=buildRoadJunctions(roads);
  const pieces=roadPieces(roads);
  const looseEnds=[];
  for(const road of roads){
    if(!isLoose(road))continue;
    const runs=pieces.get(road.id)||[];
    // Only show the clipped ends, not normal endpoints of the source road.
    for(const run of runs){
      if(run.length<2)continue;
      for(const end of [run[0],run.at(-1)]){
        if([road.points[0],road.points.at(-1)].some(p=>
          Math.hypot(p.x-end.x,p.y-end.y)<1))continue;
        looseEnds.push({roadId:road.id,...end});
      }
    }
  }
  const gaps=findEndpointGaps({roads});
  cached={junctions,looseEnds,gaps};
  roadsCache.set(roads,cached);
  return cached;
}
export function liveRoadClearances(doc){
  let cached=clearanceCache.get(doc);
  if(cached)return cached;
  const conflicts=[];
  for(const prop of doc.props){
    if(prop.hidden)continue;
    const radius=placementFootprint(doc,prop);
    const clearance=roadwayClearance(doc,prop,radius);
    if(clearance<0)conflicts.push({id:prop.id,x:prop.x,y:prop.y,
      radius,clearance});
  }
  clearanceCache.set(doc,conflicts);
  return conflicts;
}
export function drawLiveAutomation(ctx,roadState,{
  zoom=1,bounds=null,showJunctions=true,showLoosePriority=true,
  showGaps=true,clearances=[],showClearances=false
}={}){
  if(!roadState)return;
  const safeZoom=Math.max(.007,zoom),unit=1/safeZoom;
  ctx.save();
  if(showJunctions){
    for(const j of roadState.junctions){
      if(!inBounds(j,bounds,12*unit))continue;
      // A small locator is sufficient for editing. Do not outline the
      // diagnostic convex hull: it looks like a fake asphalt intersection,
      // while the underlying road renderer uses real paved road footprints.
      const radius=Math.max(2,4.2*unit);
      ctx.beginPath();ctx.arc(j.x,j.y,radius,0,Math.PI*2);
      ctx.fillStyle='#9ef2ddde';ctx.fill();
      ctx.strokeStyle='#173c43';ctx.lineWidth=1.2*unit;ctx.stroke();
    }
  }
  if(showLoosePriority){
    for(const end of roadState.looseEnds){
      if(!inBounds(end,bounds,12*unit))continue;
      const r=Math.max(2,4*unit);
      ctx.beginPath();ctx.arc(end.x,end.y,r,0,Math.PI*2);
      ctx.strokeStyle='#ffb875';ctx.lineWidth=2*unit;ctx.stroke();
      ctx.beginPath();ctx.moveTo(end.x-r*.65,end.y-r*.65);
      ctx.lineTo(end.x+r*.65,end.y+r*.65);ctx.moveTo(end.x-r*.65,end.y+r*.65);
      ctx.lineTo(end.x+r*.65,end.y-r*.65);ctx.lineWidth=1.1*unit;ctx.stroke();
    }
  }
  if(showGaps){
    for(const item of roadState.gaps){
      if(!inBounds(item.from,bounds,8*unit)&&
        !inBounds(item.to,bounds,8*unit))continue;
      ctx.beginPath();ctx.moveTo(item.from.x,item.from.y);
      ctx.lineTo(item.to.x,item.to.y);
      ctx.strokeStyle='#f9d196aa';ctx.lineWidth=1.8*unit;
      ctx.setLineDash([3*unit,3*unit]);ctx.stroke();ctx.setLineDash([]);
    }
  }
  if(showClearances){
    for(const p of clearances){
      if(!inBounds(p,bounds,p.radius))continue;
      ctx.beginPath();ctx.arc(p.x,p.y,p.radius,0,Math.PI*2);
      ctx.strokeStyle='#ef8b7ddd';ctx.lineWidth=1.5*unit;
      ctx.setLineDash([4*unit,3*unit]);ctx.stroke();ctx.setLineDash([]);
    }
  }
  ctx.restore();
}
