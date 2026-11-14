/** Right-hand directed lane previews, inspired by SUMO's lane/edge model.
 * Not persisted as road paint: the same lane offsets can be regenerated
 * from the full-resolution Morrow road centerlines in the game.
 */
import {distance,sampleRoad} from './world-geometry.js';
import {isLoose} from './world-road-priority.js';

export function lanePatterns(roads,{includeLoose=false}={}){
  const patterns=[];
  for(const road of roads){
    if(['track','service'].includes(road.roadClass)||(!includeLoose&&isLoose(road)))continue;
    const count=Math.max(2,Math.min(6,road.lanes||2));
    const forward=Math.max(1,Math.floor(count/2));
    const reverse=Math.max(1,count-forward);
    const divider=(reverse-forward)*road.width/count*.5;
    const points=sampleRoad(road.points,road.smooth,20);
    if(points.length<2)continue;
    for(const direction of [1,-1]){
      const lanes=direction===1?forward:reverse;
      const polyline=direction===1?points:points.slice().reverse();
      const laneWidth=road.width/count;
      for(let index=0;index<lanes;index++){
        const side=laneWidth*(index+.5)+direction*divider;
        // Road traffic is RIGHT-HAND. Two-way lane offsets must use the
        // direction of travel, not the original authoring direction.
        const result=[];
        for(let i=0;i<polyline.length;i++){
          const p=polyline[i],closed=distance(polyline[0],polyline.at(-1))<.001;
          const a=polyline[i-1]||(closed?polyline.at(-2):p);
          const b=polyline[i+1]||(closed?polyline[1]:p);
          let before={x:p.x-a.x,y:p.y-a.y},after={x:b.x-p.x,y:b.y-p.y};
          if(i===0&&!closed)before=after;
          if(i===polyline.length-1&&!closed)after=before;
          const la=Math.hypot(before.x,before.y)||1,lb=Math.hypot(after.x,after.y)||1;
          const nx=-before.y/la-after.y/lb,ny=before.x/la+after.x/lb;
          const nl=Math.hypot(nx,ny)||1;
          const normal={x:nx/nl,y:ny/nl};
          const miter=1/Math.max(.55,normal.x*(-after.y/lb)+normal.y*(after.x/lb));
          result.push({x:p.x+normal.x*side*miter,y:p.y+normal.y*side*miter});
        }
        patterns.push({roadId:road.id,roadName:road.name,
          lane:index,direction,points:result,kind:road.roadClass,
          speedKph:({highway:90,country:65,mountain:42,city:40,service:25})[road.roadClass]||40});
      }
    }
  }
  return patterns;
}

export function drawLanePreview(ctx,patterns,zoom,bounds){
  ctx.save();
  const width=Math.max(1.25/Math.max(zoom,.001),1.2);
  for(const lane of patterns){
    const points=lane.points;
    if(points.length<2)continue;
    const minX=Math.min(...points.map(p=>p.x)),maxX=Math.max(...points.map(p=>p.x));
    const minY=Math.min(...points.map(p=>p.y)),maxY=Math.max(...points.map(p=>p.y));
    if(bounds&&(maxX<bounds.minX||minX>bounds.maxX||maxY<bounds.minY||minY>bounds.maxY))continue;
    ctx.beginPath();ctx.moveTo(points[0].x,points[0].y);
    for(const p of points.slice(1))ctx.lineTo(p.x,p.y);
    ctx.lineWidth=width;ctx.strokeStyle='#78e7fa99';ctx.stroke();
    let travelled=0;
    for(let i=1;i<points.length;i++){
      const a=points[i-1],b=points[i],segment=distance(a,b);
      travelled+=segment;
      if(travelled<105)continue;
      travelled=0;
      const dx=(b.x-a.x)/(segment||1),dy=(b.y-a.y)/(segment||1);
      const x=(a.x+b.x)*.5,y=(a.y+b.y)*.5,size=Math.max(4,5/Math.max(zoom,.2));
      ctx.beginPath();ctx.moveTo(x+dx*size,y+dy*size);
      ctx.lineTo(x+dy*size*.7-dx*size*.3,y-dx*size*.7-dy*size*.3);
      ctx.lineTo(x-dy*size*.7-dx*size*.3,y+dx*size*.7-dy*size*.3);
      ctx.closePath();
      ctx.fillStyle='#b4f0fa';ctx.fill();
    }
  }
  ctx.restore();
}
