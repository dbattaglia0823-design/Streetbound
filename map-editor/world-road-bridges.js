/** Original automatic water crossing geometry, in metres. Same rules as the
 * Godot runtime and production baker; never adds roads or graph junctions. */
import {sampleRoad} from './world-geometry.js';
const WATER=new Set(['water','lake','ocean','river']),COSMETIC=new Set(['foam','riverbank']);
const CELL=128,APPROACH=3;
const dist=(a,b)=>Math.hypot(b.x-a.x,b.y-a.y);
const lerp=(a,b,t)=>({x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t});
const point=p=>Array.isArray(p)?{x:+p[0],y:+p[1]}:{x:+p.x,y:+p.y};
const bounds=ps=>({x:Math.min(...ps.map(p=>p.x)),y:Math.min(...ps.map(p=>p.y)),
  r:Math.max(...ps.map(p=>p.x)),b:Math.max(...ps.map(p=>p.y))});
const overlap=(a,b)=>a.x<=b.r&&b.x<=a.r&&a.y<=b.b&&b.y<=a.b;
const contains=(b,p)=>p.x>=b.x&&p.x<=b.r&&p.y>=b.y&&p.y<=b.b;
function cells(box){const out=[];for(let y=Math.floor(box.y/CELL);y<=Math.floor(box.b/CELL);y++)
  for(let x=Math.floor(box.x/CELL);x<=Math.floor(box.r/CELL);x++)out.push(x+','+y);return out;}
function inside(p,ps){let hit=false;for(let i=0,j=ps.length-1;i<ps.length;j=i++){
  const a=ps[j],b=ps[i];if((a.y>p.y)!==(b.y>p.y)&&p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x)hit=!hit;
}return hit;}
function cuts(a,b,edges){const out=[0,1],dx=b.x-a.x,dy=b.y-a.y;
  for(const {a:c,b:d} of edges){const wx=d.x-c.x,wy=d.y-c.y,den=dx*wy-dy*wx;
    if(Math.abs(den)<1e-8)continue;
    const rx=c.x-a.x,ry=c.y-a.y,t=(rx*wy-ry*wx)/den,u=(rx*dy-ry*dx)/den;
    if(t>0&&t<1&&u>=-1e-6&&u<=1+1e-6)out.push(t);
  }return out.sort((a,b)=>a-b);
}
export class WaterMask{
  constructor(terrain){this.layers=[];this.waterBounds=[];this.edges=[];this.grid=new Map();this.interior=new Map();let seen=false;
    for(const raw of terrain){const kind=raw.kind??raw.biome;seen ||=WATER.has(kind);
      if(!seen||COSMETIC.has(kind)||raw.points.length<3)continue;
      const ps=raw.points.map(point),box=bounds(ps),layer=this.layers.length;
      this.layers.push({ps,box,wet:WATER.has(kind)});if(WATER.has(kind))this.waterBounds.push(box);
      for(let i=0;i<ps.length;i++){const a=ps[i],b=ps[(i+1)%ps.length];if(dist(a,b)<1e-4)continue;
        const id=this.edges.length;this.edges.push({a,b,layer});
        for(const key of cells(bounds([a,b]))){if(!this.grid.has(key))this.grid.set(key,[]);this.grid.get(key).push(id);}
      }
    }
  }
  _wet(p){const key=Math.floor(p.x/CELL)+','+Math.floor(p.y/CELL);
    for(let i=this.layers.length-1;i>=0;i--){const layer=this.layers[i];
      if(!contains(layer.box,p)||!inside(p,layer.ps))continue;if(!layer.wet)return false;
      for(const id of this.grid.get(key)||[]){const {a,b,layer:owner}=this.edges[id];if(owner!==i)continue;
        const t=Math.max(0,Math.min(1,((p.x-a.x)*(b.x-a.x)+(p.y-a.y)*(b.y-a.y))/Math.max(1e-12,dist(a,b)**2)));
        if(dist(p,lerp(a,b,t))<1e-4)return false;
      }return true;
    }return false;
  }
  isWater(p){const x=Math.floor(p.x/CELL),y=Math.floor(p.y/CELL),key=x+','+y;
    if(this.grid.has(key))return this._wet(p);
    if(!this.interior.has(key))this.interior.set(key,this._wet({x:(x+.5)*CELL,y:(y+.5)*CELL}));
    return this.interior.get(key);
  }
  intervals(path){const result=[];let station=0;
    for(let i=1;i<path.length;i++){const a=path[i-1],b=path[i],length=dist(a,b);if(length<1e-5)continue;
      const box=bounds([a,b]);if(!this.waterBounds.some(w=>overlap(w,box))){station+=length;continue;}
      const ids=new Set(cells(box).flatMap(key=>this.grid.get(key)||[]));
      const ts=cuts(a,b,[...ids].map(id=>this.edges[id]));
      for(let j=1;j<ts.length;j++){const start=ts[j-1],end=ts[j];
        if((end-start)*length<1e-4||!this.isWater(lerp(a,b,(start+end)*.5)))continue;
        const span=[station+start*length,station+end*length];
        if(result.length&&span[0]-result.at(-1)[1]<.001)result.at(-1)[1]=span[1];else result.push(span);
      }station+=length;
    }return result;
  }
  spans(road){const path=road.points.map(point),length=path.slice(1).reduce((sum,p,i)=>sum+dist(path[i],p),0),runs=[];
    for(const [a,b] of this.intervals(path)){if(b-a<.25)continue;
      const start=Math.max(0,a-APPROACH),end=Math.min(length,b+APPROACH);
      if(runs.length&&start<=runs.at(-1).end+.001)Object.assign(runs.at(-1),{end,wet_end:b});
      else runs.push({start,end,wet_start:a,wet_end:b});
    }
    return runs.map(run=>({...run,road:road.id,width:road.width,kind:road.kind||'rural',points:slicePath(path,run.start,run.end)}));
  }
}
function slicePath(path,start,end){let station=0;const out=[];
  for(let i=1;i<path.length;i++){const a=path[i-1],b=path[i],length=dist(a,b);
    if(length>1e-5&&station+length>start+1e-5&&station<end-1e-5){
      const p=lerp(a,b,Math.max(0,Math.min(1,(start-station)/length))),q=lerp(a,b,Math.max(0,Math.min(1,(end-station)/length)));
      if(!out.length)out.push(p);if(dist(out.at(-1),q)>1e-5)out.push(q);
    }station+=length;
  }return out;
}
export function buildBridgeSpans(roads,terrain){const mask=new WaterMask(terrain);return roads.flatMap(r=>mask.spans(r));}

function effectiveTerrain(doc,preview){
  if(!preview?.sourceTerrain)return doc.regions.map(r=>({kind:r.biome,points:r.points}));
  const byId=new Map(doc.regions.map(r=>[r.id,r])),known=new Set();
  const [width,height]=preview.sourceSize;
  const result=preview.sourceTerrain.map(t=>{
    const id=t.editorId||'region-'+t.index,r=byId.get(id);known.add(id);if(!r)return t;
    let ps=t.points.map(p=>({x:Math.max(0,Math.min(width,p.x)),y:Math.max(0,Math.min(height,p.y))}));
    if(ps.length>1&&dist(ps[0],ps.at(-1))<.001)ps.pop();
    if(ps.length>180){const all=ps;ps=Array.from({length:180},(_,i)=>all[Math.floor(i*all.length/180)]);}
    const biome=t.kind==='water'?'lake':t.kind==='town'?'grass':t.kind;
    if(r.biome===biome&&r.points.length===ps.length&&r.points.every((p,i)=>dist(p,ps[i])<.025))return t;
    return {kind:r.biome,points:r.points};
  });
  return result.concat(doc.regions.filter(r=>!known.has(r.id)).map(r=>({kind:r.biome,points:r.points})));
}
const cache=new WeakMap();
export function bridgesForDocument(doc,preview){
  const prior=cache.get(doc);if(prior&&prior.preview===preview)return prior.spans;
  const roads=doc.roads.map(r=>{const baked=preview?.roads?.get(r.id);
    const unchanged=baked&&r.points.length===baked.anchors.length&&Math.abs(r.width-baked.width)<.001&&
      r.surface.toUpperCase()===baked.surface&&r.points.every((p,i)=>dist(p,point(baked.anchors[i]))<.005);
    return {id:r.id,width:r.width,kind:({city:'local',country:'rural',service:'driveway'})[r.roadClass]||r.roadClass,
      points:unchanged?baked.points:sampleRoad(r.points,r.smooth,6)};
  });
  const spans=buildBridgeSpans(roads,effectiveTerrain(doc,preview));cache.set(doc,{preview,spans});return spans;
}
function offsetPath(path,amount){return path.map((p,i)=>{
  const unit=(a,b)=>{const length=dist(a,b);return length?{x:(b.x-a.x)/length,y:(b.y-a.y)/length}:{x:0,y:0};};
  let before=unit(path[Math.max(0,i-1)],p),after=unit(p,path[Math.min(path.length-1,i+1)]);
  if(!i)before=after;if(i===path.length-1)after=before;
  const length=Math.hypot(before.x+after.x,before.y+after.y);
  const normal=length?{x:-(before.y+after.y)/length,y:(before.x+after.x)/length}:{x:-after.y,y:after.x};
  const scale=amount/Math.max(.55,normal.x*-after.y+normal.y*after.x);
  return {x:p.x+normal.x*scale,y:p.y+normal.y*scale};
});}
function stroke(ctx,path,width,color){if(path.length<2)return;ctx.beginPath();ctx.moveTo(path[0].x,path[0].y);
  for(const p of path.slice(1))ctx.lineTo(p.x,p.y);ctx.lineWidth=width;ctx.strokeStyle=color;ctx.lineCap='butt';ctx.lineJoin='round';ctx.stroke();}
export function bridgeRailPieces(bridge,junctions=[]){
  const offset=bridge.width*.5+(['local','arterial'].includes(bridge.kind)?3.8:1.4),result=[];
  for(const side of [-1,1]){const path=offsetPath(bridge.points,side*offset);let station=0;
    for(let i=1;i<path.length;i++){const a=path[i-1],b=path[i],length=dist(a,b);
      const masks=junctions.map(j=>j.polygon||[]).filter(p=>p.length>=3&&overlap(bounds([a,b]),bounds(p)));
      const ts=cuts(a,b,masks.flatMap(ps=>ps.map((p,j)=>({a:p,b:ps[(j+1)%ps.length]}))));
      for(let j=1;j<ts.length;j++){const start=ts[j-1],end=ts[j];
        if((end-start)*length<1e-4||masks.some(ps=>inside(lerp(a,b,(start+end)*.5),ps)))continue;
        result.push({points:[lerp(a,b,start),lerp(a,b,end)],phase:station+start*length});
      }station+=length;
    }
  }return result;
}
export function drawBridge(ctx,bridge,stage,junctions=[]){
  const path=bridge.points,offset=bridge.width*.5+(['local','arterial'].includes(bridge.kind)?3.8:1.4),deck=offset*2+1;
  ctx.save();ctx.setLineDash([]);
  if(stage===0){stroke(ctx,path.map(p=>({x:p.x+2.2,y:p.y+3.5})),deck+1.1,'#10263047');
    stroke(ctx,path,deck+.6,'#52676a');stroke(ctx,path,deck,'#bbc0b2');
  }else for(const piece of bridgeRailPieces(bridge,junctions)){const rail=piece.points;
    stroke(ctx,rail,.95,'#3c5055');stroke(ctx,rail,.6,'#cdd0c1');stroke(ctx,rail,.15,'#f0e9d2');
    let station=piece.phase;for(let i=1;i<rail.length;i++){const a=rail[i-1],b=rail[i],length=dist(a,b);
      for(let at=Math.ceil((station+.001)/4)*4;at<station+length;at+=4){const p=lerp(a,b,(at-station)/length);
        ctx.fillStyle='#74847f';ctx.fillRect(p.x-.3,p.y-.3,.6,.6);}
      station+=length;
    }
  }ctx.restore();
}
