/** Continuous world geometry. Coordinates are world units, never tile indices. */
export const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
export const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
export const lerp = (a, b, t) => a + (b - a) * t;
export const pointSegment = (p, a, b) => {
  const dx = b.x - a.x, dy = b.y - a.y, len = dx * dx + dy * dy;
  const t = len ? clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / len, 0, 1) : 0;
  const x = a.x + dx * t, y = a.y + dy * t;
  return {x, y, t, distance: Math.hypot(p.x - x, p.y - y)};
};
export function pointInPolygon(p, points) {
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const a = points[i], b = points[j];
    if (((a.y > p.y) !== (b.y > p.y)) &&
        p.x < ((b.x - a.x) * (p.y - a.y)) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}
export function polygonArea(points) {
  let sum = 0;
  for (let i = 0; i < points.length; i++) {
    const j = (i + 1) % points.length;
    sum += points[i].x * points[j].y - points[j].x * points[i].y;
  }
  return Math.abs(sum / 2);
}
export function boundsOf(points) {
  if (!points.length) return {minX:0,minY:0,maxX:0,maxY:0};
  return points.reduce((r,p)=>({
    minX:Math.min(r.minX,p.x), minY:Math.min(r.minY,p.y),
    maxX:Math.max(r.maxX,p.x), maxY:Math.max(r.maxY,p.y)
  }),{minX:Infinity,minY:Infinity,maxX:-Infinity,maxY:-Infinity});
}
/** Catmull-Rom interpolation through control points, with capped adaptive sampling.
 * The sampled polyline is used identically for rendering, road queries and export.
 * Passing smooth=false generates strict straight segments.
 */
export function sampleRoad(points, smooth = true, spacing = 9) {
  if (!Array.isArray(points) || points.length < 2) return [];
  const out = [{x:points[0].x,y:points[0].y}];
  for (let i = 0; i < points.length - 1; i++) {
    const p0=points[Math.max(0,i-1)],p1=points[i],p2=points[i+1],p3=points[Math.min(points.length-1,i+2)];
    const length=distance(p1,p2);
    const steps=smooth && points.length > 2 ? clamp(Math.ceil(length / Math.max(spacing,2)),2,80) : 1;
    for(let j=1;j<=steps;j++){
      const t=j/steps;
      if (!smooth || points.length === 2) {
        out.push({x:lerp(p1.x,p2.x,t),y:lerp(p1.y,p2.y,t)});
        continue;
      }
      // Hermite form of Catmull-Rom with centripetal chord weighting.
      const d01=Math.max(1e-5,Math.sqrt(distance(p0,p1)));
      const d12=Math.max(1e-5,Math.sqrt(length));
      const d23=Math.max(1e-5,Math.sqrt(distance(p2,p3)));
      const m1x=(p2.x-p0.x)*d12/(d01+d12), m1y=(p2.y-p0.y)*d12/(d01+d12);
      const m2x=(p3.x-p1.x)*d12/(d12+d23), m2y=(p3.y-p1.y)*d12/(d12+d23);
      const t2=t*t,t3=t2*t;
      const h00=2*t3-3*t2+1,h10=t3-2*t2+t,h01=-2*t3+3*t2,h11=t3-t2;
      out.push({x:h00*p1.x+h10*m1x+h01*p2.x+h11*m2x,
                y:h00*p1.y+h10*m1y+h01*p2.y+h11*m2y});
    }
  }
  return out;
}
export function pathLength(points) {
  let len=0;
  for(let i=1;i<points.length;i++)len+=distance(points[i-1],points[i]);
  return len;
}
export function nearestOnPath(p, points) {
  let best={distance:Infinity,segment:-1,x:0,y:0,t:0};
  for(let i=1;i<points.length;i++){
    const hit=pointSegment(p,points[i-1],points[i]);
    if(hit.distance<best.distance)best={...hit,segment:i-1};
  }
  return best;
}
export function roadAt(doc, point) {
  let hit=null;
  for (let i=doc.roads.length-1;i>=0;i--){
    const road=doc.roads[i], nearest=nearestOnPath(point,sampleRoad(road.points,road.smooth,12));
    if (nearest.distance <= road.width/2 && (!hit || nearest.distance < hit.distance)) {
      hit={id:road.id, surface:road.surface, lanes:road.lanes, width:road.width, distance:nearest.distance};
    }
  }
  return hit;
}
export function regionAt(doc, point) {
  for(let i=doc.regions.length-1;i>=0;i--)
    if(pointInPolygon(point,doc.regions[i].points))return doc.regions[i];
  return null;
}
/** Intersection between two segment centerlines, used for snapping/roadway editing. */
export function segmentIntersection(a,b,c,d){
  const rx=b.x-a.x,ry=b.y-a.y,sx=d.x-c.x,sy=d.y-c.y;
  const cross=rx*sy-ry*sx;
  if (Math.abs(cross)<1e-7)return null;
  const px=c.x-a.x,py=c.y-a.y;
  const t=(px*sy-py*sx)/cross,u=(px*ry-py*rx)/cross;
  if(t<0||t>1||u<0||u>1)return null;
  return {x:a.x+rx*t,y:a.y+ry*t};
}
/** Spatially indexed road intersections. In large open-world maps, comparing every
 * sampled segment against every other sampled segment is prohibitively expensive.
 * Only previously indexed roads are checked; nearby crossing points for the same
 * road pair are de-duplicated within 8 world units. Separate road pairs retain
 * distinct navigation connections even at shared junctions.
 */
export function roadIntersections(roads) {
  const intersections=[],grid=new Map(),perPair=new Map(),size=120;
  const bucketKey=(x,y)=>x+','+y;
  const cells=({minX,minY,maxX,maxY})=>{
    const out=[];
    for(let x=Math.floor(minX/size);x<=Math.floor(maxX/size);x++)
      for(let y=Math.floor(minY/size);y<=Math.floor(maxY/size);y++)
        out.push(bucketKey(x,y));
    return out;
  };
  for(let i=0;i<roads.length;i++){
    const points=sampleRoad(roads[i].points,roads[i].smooth,18),newSegments=[];
    for(let j=1;j<points.length;j++){
      const a=points[j-1],b=points[j],segment={
        a,b,road:i,minX:Math.min(a.x,b.x),maxX:Math.max(a.x,b.x),
        minY:Math.min(a.y,b.y),maxY:Math.max(a.y,b.y)
      };
      const visited=new Set();
      for(const key of cells(segment)){
        for(const other of grid.get(key)||[]){
          if(visited.has(other))continue;
          visited.add(other);
          if(other.maxX<segment.minX||other.minX>segment.maxX||
            other.maxY<segment.minY||other.minY>segment.maxY)continue;
          const crossing=segmentIntersection(other.a,other.b,a,b);
          if(!crossing)continue;
          const pair=other.road+':'+i,near=perPair.get(pair)||[];
          if(near.some(old=>distance(old,crossing)<8))continue;
          near.push(crossing);perPair.set(pair,near);
          intersections.push({...crossing,roads:[roads[other.road].id,roads[i].id],
            width:Math.max(roads[other.road].width,roads[i].width),surface:roads[i].surface});
        }
      }
      newSegments.push(segment);
    }
    // Index only after finishing this road, so bends never connect to themselves.
    for(const segment of newSegments){
      for(const key of cells(segment)){
        if(!grid.has(key))grid.set(key,[]);
        grid.get(key).push(segment);
      }
    }
  }
  return intersections;
}
export function seeded(seed) {
  let value=(Number(seed)|0) || 1;
  return ()=>{value^=value<<13;value^=value>>>17;value^=value<<5;return (value>>>0)/4294967296;};
}
export function stringSeed(value){
  let hash=2166136261;
  for(const c of String(value)){hash=Math.imul(hash^c.charCodeAt(0),16777619);}
  return hash>>>0;
}
export function scatterPoints(polygon,count,seed,accept=()=>true){
  const b=boundsOf(polygon),rand=seeded(seed),points=[];
  let attempts=0;
  while(points.length<count && attempts<Math.max(100,count*32)){
    attempts++;
    const p={x:lerp(b.minX,b.maxX,rand()),y:lerp(b.minY,b.maxY,rand())};
    if(pointInPolygon(p,polygon) && accept(p))points.push(p);
  }
  return points;
}
