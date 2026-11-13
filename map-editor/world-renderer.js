import {boundsOf,clamp,pointInPolygon,sampleRoad,scatterPoints,stringSeed,seeded} from './world-geometry.js';
import {buildRoadJunctions} from './world-junctions.js';
import {roadPieces,isLoose} from './world-road-priority.js';
import {getEntity} from './world-model.js';
import {BASE_SIZE,drawAtlas,drawGameVectorProp,gameArtKind,drawRuntimeScenery,drawRuntimeExpansion,drawRuntimeTerrain,drawNative} from './morrow-runtime-preview.js';
import {roadInsertCandidate,regionInsertCandidate} from './world-edit-tools.js';

/** Original illustrated vector preview. The map data contains geometry, not artwork copies. */
export const BIOME_COLORS={
  grass:'#728e61',forest:'#456d50',mountain:'#838578',rock:'#9e9580',
  beach:'#d9c28d',ocean:'#417f9a',lake:'#5b9aa9',city:'#95958b',desert:'#bd9e71',farmland:'#9b9d68'
};
export const ROAD_COLORS={asphalt:'#3d4550',concrete:'#777a7c',dirt:'#a18359',gravel:'#888476',track:'#4b505a'};
/** Real Godot baked terrain colors. World Forge's standalone demo palette is
 * intentionally different and must not recolor the Morrow Coast shoreline. */
export const GAME_BIOME_COLORS={
  grass:'#a3b789',forest:'#718d70',mountain:'#9baba0',rock:'#9e9580',
  beach:'#e3d4aa',ocean:'#82b5b5',lake:'#82b5b5',city:'#b1b6a0',
  desert:'#bd9e71',farmland:'#b4bd8a'
};
const stroke=(ctx,points,closed=false)=>{
  if(!points?.length)return;
  ctx.beginPath();ctx.moveTo(points[0].x,points[0].y);
  for(let i=1;i<points.length;i++)ctx.lineTo(points[i].x,points[i].y);
  if(closed)ctx.closePath();
};
const circle=(ctx,x,y,r,color)=>{
  ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();
};
const rect=(ctx,x,y,w,h,color)=>{ctx.fillStyle=color;ctx.fillRect(x,y,w,h);};
const expand=(a,n)=>({minX:a.minX-n,minY:a.minY-n,maxX:a.maxX+n,maxY:a.maxY+n});
const visible=(a,b)=>!b||a.maxX>=b.minX&&a.minX<=b.maxX&&a.maxY>=b.minY&&a.minY<=b.maxY;
const decoCache=new WeakMap();
const spriteCache=new Map();
function getSprite(asset){
  if(!asset)return null;
  const cached=spriteCache.get(asset.id);
  if(cached&&cached.src===asset.src)return cached.image;
  const image=new Image();
  image.onload=()=>document.dispatchEvent(new Event('gdt-world-asset-ready'));
  spriteCache.set(asset.id,{image,src:asset.src});
  image.src=asset.src;
  return image;
}
function regionDetails(region,seed){
  const existing=decoCache.get(region);
  if(existing)return existing;
  const extent=boundsOf(region.points),area=(extent.maxX-extent.minX)*(extent.maxY-extent.minY);
  const count=clamp(Math.round(area/3000),65,390);
  const dots=scatterPoints(region.points,count,stringSeed(region.id+seed));
  decoCache.set(region,dots);
  return dots;
}
function drawRuntimeEditedRegion(ctx,region,bounds,sourceTerrain=null){
  // Editing a shoreline must retain the real game's colors and avoid the
  // stylized water-edge strokes used by standalone World Forge examples.
  if(!visible(boundsOf(region.points),bounds))return;
  stroke(ctx,region.points,true);
  const originalBiome=sourceTerrain?.kind==='water'?'lake':
    sourceTerrain?.kind==='town'?'grass':sourceTerrain?.kind;
  const sourceColor=sourceTerrain?.color;
  ctx.fillStyle=originalBiome===region.biome&&/^[0-9a-f]{6}$/i.test(sourceColor||'')
    ? '#'+sourceColor:GAME_BIOME_COLORS[region.biome]||GAME_BIOME_COLORS.grass;
  ctx.fill();
}
function drawRegion(ctx,region,seed,quality,bounds){
  const a=boundsOf(region.points);
  if(!visible(a,bounds))return;
  stroke(ctx,region.points,true);
  ctx.fillStyle=BIOME_COLORS[region.biome]||BIOME_COLORS.grass;ctx.fill();
  if(region.biome==='ocean'||region.biome==='lake'){
    stroke(ctx,region.points,true);
    ctx.strokeStyle=region.biome==='ocean'?'#acd9cb':'#b6d7c0';ctx.lineWidth=12;ctx.globalAlpha=.5;ctx.stroke();
    ctx.lineWidth=34;ctx.globalAlpha=.15;ctx.stroke();ctx.globalAlpha=1;
  }
  if(region.biome==='beach'){
    stroke(ctx,region.points,true);ctx.lineWidth=7;ctx.strokeStyle='#f1dfac';ctx.stroke();
  }
  if(quality===0)return;
  ctx.save();stroke(ctx,region.points,true);ctx.clip();
  const dots=regionDetails(region,seed),rand=seeded(stringSeed(seed+'-'+region.id+'-decor'));
  for(let i=0;i<dots.length;i++){
    const p=dots[i];if(bounds && !visible({minX:p.x,minY:p.y,maxX:p.x,maxY:p.y},bounds))continue;
    const r=2+rand()*7;
    if(region.biome==='ocean'||region.biome==='lake'){
      ctx.strokeStyle=i%3?'#b4dfde75':'#23658855';ctx.lineWidth=.9+rand()*1.9;
      ctx.beginPath();ctx.moveTo(p.x-8,p.y);ctx.quadraticCurveTo(p.x,p.y-4,p.x+6+rand()*8,p.y);ctx.stroke();
    }else if(region.biome==='mountain'||region.biome==='rock'){
      ctx.fillStyle=i%2?'#e2d7bd55':'#3b414044';
      ctx.beginPath();ctx.moveTo(p.x-2*r,p.y+r);ctx.lineTo(p.x+1*r,p.y-r);ctx.lineTo(p.x+2*r,p.y+2*r);ctx.closePath();ctx.fill();
      if(i%7===0){
        ctx.strokeStyle='#e7e4cd55';ctx.lineWidth=1.8;
        ctx.beginPath();ctx.moveTo(p.x-25,p.y+8);ctx.bezierCurveTo(p.x-12,p.y-6,p.x+15,p.y-9,p.x+30,p.y+3);ctx.stroke();
      }
    }else if(region.biome==='city'){
      rect(ctx,p.x,p.y,r*2,2,'#e0dfd014');
    }else{
      ctx.fillStyle=i%2?'#274d3c38':'#e4d6a03d';
      ctx.beginPath();ctx.ellipse(p.x,p.y,r*1.2,r*.4,rand()*Math.PI,0,Math.PI*2);ctx.fill();
    }
  }
  ctx.restore();
}
function drawRoadStroke(ctx,points,width,color,dash=[],cap='round'){
  if(points.length<2)return;
  ctx.lineJoin='round';ctx.lineCap=cap;ctx.lineWidth=width;ctx.strokeStyle=color;
  ctx.setLineDash(dash);stroke(ctx,points);ctx.stroke();ctx.setLineDash([]);
}
function traceOffset(points,offset){
  const output=[];
  for(let i=0;i<points.length;i++){
    const prev=points[Math.max(i-1,0)],next=points[Math.min(i+1,points.length-1)];
    const dx=next.x-prev.x,dy=next.y-prev.y,len=Math.hypot(dx,dy)||1;
    output.push({x:points[i].x-dy/len*offset,y:points[i].y+dx/len*offset});
  }
  return output;
}
function drawRoadBase(ctx,road,points){
  const w=road.width,s=road.shoulder,cap=isLoose(road)?'butt':'round';
  drawRoadStroke(ctx,points,w+s*2,road.surface==='dirt'?'#baa27a':road.surface==='gravel'?'#a99f8a':'#6b6760',[],cap);
  drawRoadStroke(ctx,points,w+3,isLoose(road)?'#796d56bb':'#242a2e99',[],cap);
  drawRoadStroke(ctx,points,w,ROAD_COLORS[road.surface],[],cap);
  if(road.surface==='track')drawRoadStroke(ctx,points,w+5,'#c94e42', [18,18]);
  if(road.roadClass==='mountain'&&w>22){
    drawRoadStroke(ctx,traceOffset(points,w/2+s+5),2.6,'#c3b19a');
  }
}
function drawRoadLines(ctx,road,points){
  if(!road.markings || road.surface==='dirt'||road.surface==='gravel')return;
  const w=road.width;
  if(road.lanes===1){
    drawRoadStroke(ctx,points,1.5,road.surface==='track'?'#f7f3df':'#ecdfba',[19,16]);
  }else{
    const dash=road.surface==='track'?[]:[16,15];
    if(road.roadClass==='highway'){
      drawRoadStroke(ctx,traceOffset(points,-1.5),1.7,'#e9c46e');
      drawRoadStroke(ctx,traceOffset(points,1.5),1.7,'#e9c46e');
    }else drawRoadStroke(ctx,points,1.7,'#f8d9a0',dash);
    if(road.lanes>=4){
      for(let line=1;line<road.lanes;line++)if(line!==road.lanes/2)
        drawRoadStroke(ctx,traceOffset(points,(line/road.lanes-.5)*w),1.1,'#c9d2cb',[16,15]);
    }
  }
  drawRoadStroke(ctx,traceOffset(points,-w/2+2.8),1.5,'#dce0d5b8');
  drawRoadStroke(ctx,traceOffset(points,w/2-2.8),1.5,'#dce0d5b8');
}
function drawRoads(ctx,roads,bounds,options){
  // A shared derived surface plan drives preview AND road-network export.
  // Clipped dirt/gravel sections are drawn before paved roads regardless of
  // creation order, preventing the loose shoulders covering asphalt.
  const pieces=roadPieces(roads);
  const order=[...roads].sort((a,b)=>Number(isLoose(b))-Number(isLoose(a)));
  const displayPaths=road=>{
    const baked=options?.runtimePreview?.roads?.get(road.id);
    // Render the precise Godot-baked centerline until the user changes any
    // control point or surface. Edited roads immediately use the live spline.
    if(!baked||isLoose(road)||road.points.length!==baked.anchors.length||
      Math.abs(road.width-baked.width)>.001 ||
      road.surface.toUpperCase()!==baked.surface ||
      !road.points.every((p,i)=>Math.abs(p.x-baked.anchors[i][0])<.005&&
        Math.abs(p.y-baked.anchors[i][1])<.005))
      return pieces.get(road.id)||[];
    return [baked.points];
  };
  for(const road of order){
    if(!visible(expand(boundsOf(road.points),road.width/2+20),bounds))continue;
    for(const path of displayPaths(road))drawRoadBase(ctx,road,path);
  }
  // Erase continuous center/edge markings at crossing mouths, as in the
  // game's clipped road-paint pass. A clip mask is NOT drawn as a junction
  // shape: asphalt is the real overlap of road strokes rendered above.
  const junctions=options?.junctions===false?[]:buildRoadJunctions(roads)
    .filter(j=>j.kind!=='endpoint'&&j.roads.length>=2);
  ctx.save();
  if(junctions.length){
    ctx.beginPath();
    // Even-odd exclusion: the outer rectangle remains visible, and the
    // circular holes remove lines without painting artificial pavement.
    const b=bounds||{minX:-10000,minY:-10000,maxX:30000,maxY:30000};
    ctx.rect(b.minX-300,b.minY-300,b.maxX-b.minX+600,b.maxY-b.minY+600);
    for(const j of junctions){
      if(!visible({minX:j.x-j.radius,minY:j.y-j.radius,
        maxX:j.x+j.radius,maxY:j.y+j.radius},bounds))continue;
      const width=Math.min(roads.filter(r=>j.roads.includes(r.id))
        .reduce((max,r)=>Math.max(max,r.width),0),160);
      ctx.moveTo(j.x+Math.min(64,width*.65+4),j.y);
      ctx.arc(j.x,j.y,Math.min(64,width*.65+4),0,Math.PI*2);
    }
    ctx.clip('evenodd');
  }
  for(const road of order){
    if(!visible(expand(boundsOf(road.points),road.width/2+20),bounds))continue;
    for(const path of displayPaths(road))drawRoadLines(ctx,road,path);
  }
  ctx.restore();
  // Game-style pavement: road surfaces overlap naturally, without convex
  // hulls or artificial asphalt blobs. Clear road markings only inside the
  // actual junction mouths. The exact Godot-baked apron is drawn below when
  // all participating roads are still identical to the saved game geometry.
  // Reuse the real baked game junctions only for unchanged roads. The
  // live-edit fallback above deliberately avoids convex polygon aprons.
  if(options?.junctions!==false && options?.runtimePreview?.junctions){
    const preview=options.runtimePreview;
    const unchanged=id=>{
      const road=roads.find(item=>item.id===id);
      const baked=preview.roads.get(id);
      return Boolean(road&&baked&&road.points.length===baked.anchors.length&&
        Math.abs(road.width-baked.width)<.001 &&
        road.surface.toUpperCase()===baked.surface &&
        road.points.every((p,i)=>Math.abs(p.x-baked.anchors[i][0])<.005&&
          Math.abs(p.y-baked.anchors[i][1])<.005));
    };
    if(options.quality!==0)for(const j of preview.junctions){
      if(!j.roads.length||!j.roads.every(unchanged)||
        !visible({minX:j.at.x-j.radius,minY:j.at.y-j.radius,
          maxX:j.at.x+j.radius,maxY:j.at.y+j.radius},bounds))continue;
      ctx.save();
      // Exact saved junction pavement, matching the game's coast_roads.gd
      // fill before curb fillets and stop/yield markings. Do not reuse baked
      // polygons after a participating road has been moved or reshaped.
      if(j.polygon?.length>=3){
        stroke(ctx,j.polygon.map(([x,y])=>({x,y})),true);
        ctx.fillStyle='#58656c';
        ctx.fill();
      }
      ctx.strokeStyle='#eee7d5';
      ctx.lineWidth=.3;
      for(const curb of j.curbs){
        if(curb.length<2)continue;
        ctx.beginPath();
        ctx.moveTo(curb[0][0],curb[0][1]);
        for(const p of curb.slice(1))ctx.lineTo(p[0],p[1]);
        ctx.stroke();
      }
      for(const arm of j.approaches){
        if(!['stop','yield'].includes(arm.control))continue;
        const p=arm.p,d=arm.direction;
        if(!Array.isArray(p)||!Array.isArray(d))continue;
        const n={x:-d[1],y:d[0]},w=(arm.width||9)/2;
        ctx.beginPath();
        ctx.moveTo(p[0]-n.x*(w-.5),p[1]-n.y*(w-.5));
        ctx.lineTo(p[0]-n.x*.5,p[1]-n.y*.5);
        ctx.lineWidth=.4;ctx.strokeStyle='#f2ebd4';ctx.stroke();
      }
      ctx.restore();
    }
  }
}
function drawTree(ctx,type,seed){
  const rng=seeded(seed);
  ctx.save();
  if(type==='palm'){
    circle(ctx,0,0,4,'#6e4a30');
    for(let i=0;i<7;i++){
      ctx.save();ctx.rotate(i*Math.PI*2/7);
      ctx.fillStyle=i%2?'#2b8065':'#479b6a';
      ctx.beginPath();ctx.moveTo(-2,0);ctx.quadraticCurveTo(15,-10,31,-3);ctx.quadraticCurveTo(13,1,4,4);ctx.closePath();ctx.fill();
      ctx.restore();
    }
    circle(ctx,0,0,4,'#bd9862');
  }else if(type==='pine'){
    ctx.fillStyle='#274c3c';
    for(let i=0;i<3;i++){
      const y=13-i*13,w=23-i*4;
      ctx.beginPath();ctx.moveTo(0,-33+i*2);ctx.lineTo(w,y+7);ctx.lineTo(-w,y+7);ctx.closePath();ctx.fill();
      ctx.fillStyle=i%2?'#316d50':'#3e7e59';
    }
    ctx.strokeStyle='#a3b98a55';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(0,-24);ctx.lineTo(0,19);ctx.stroke();
  }else{
    for(let i=0;i<6;i++){
      const a=i*Math.PI/3,rad=13+rng()*12,r=16+rng()*8;
      circle(ctx,Math.cos(a)*rad,Math.sin(a)*rad,r,i%2?'#356b43':'#4c8952');
    }
    circle(ctx,-5,-7,22,'#599a5d');
    circle(ctx,-12,-14,11,'#70a76a');
  }
  ctx.restore();
}
function drawBuilding(ctx,kind,prop={}){
  const size={house:[66,54],building:[76,87],warehouse:[116,72],garage:[96,75],gas_station:[92,63],parking:[135,100]}[kind]||[76,62];
  const [w,h]=size;
  if(kind==='parking'){
    rect(ctx,-w/2,-h/2,w,h,'#50585a');
    const spaces=Math.max(3,Math.floor(38*prop.scale*.84/(prop.stallWidth??3.2)));
    const occupied=prop.occupancy??.4;
    ctx.strokeStyle='#ddd9c3';ctx.lineWidth=1.3;
    for(const side of [-1,1]){
      for(let i=0;i<=spaces;i++){
        const x=-w*.42+w*.84*i/spaces;
        ctx.beginPath();ctx.moveTo(x,side*h*.44);ctx.lineTo(x,side*h*.22);ctx.stroke();
      }
      for(let i=0;i<spaces;i++){
        const seed=(i*37+(side>0?23:0)+stringSeed(prop.id||'lot')%97)%100;
        if(seed>=occupied*100)continue;
        const x=-w*.42+w*.84*(i+.5)/spaces;
        rect(ctx,x-4,side*h*.33-11,8,22,side>0?'#b6c3bc':'#9caead');
      }
    }
    const opening=(prop.entranceWidth??8)*h/28;
    rect(ctx,-w*.5-1,-opening*.5,10,opening,'#50585a');
    return;
  }
  if(kind==='gas_station'){
    rect(ctx,-w/2,-h/2,w,h,'#dad9c6');rect(ctx,-w/2,-h/2,w,10,'#c35045');rect(ctx,-w/2+8,-h/2+25,w-16,10,'#b45242');
    return;
  }
  rect(ctx,-w/2,-h/2,w,h,'#c2bbae');
  rect(ctx,-w/2+6,-h/2+5,w-12,h-10,kind==='house'?'#ab6d53':kind==='building'?'#8d9698':'#8a9a95');
  ctx.strokeStyle='#e0dace';ctx.lineWidth=3;ctx.strokeRect(-w/2+6,-h/2+5,w-12,h-10);
  if(kind==='house'){
    ctx.strokeStyle='#744e4d';ctx.lineWidth=5;
    ctx.beginPath();ctx.moveTo(0,-h/2+5);ctx.lineTo(0,h/2-5);ctx.stroke();
    rect(ctx,-w/2+16,-h/2+14,12,9,'#c8d6d0');
  }else{
    ctx.fillStyle='#d7d8c4aa';
    for(let x=-w/2+13;x<w/2-7;x+=18)for(let y=-h/2+13;y<h/2-8;y+=19)ctx.fillRect(x,y,10,8);
    rect(ctx,-w/2+8,-h/2+7,w-16,5,'#596772');
  }
}
export function drawProp(ctx,prop,assets=[],gameArt=false){
  // Adopted world props use the game's own rendering code so dragging or
  // rotating a baked car, lot, field or street fixture does not replace it
  // with an unrelated generic placeholder.
  if(gameArt&&prop.replaces&&BASE_SIZE[prop.type]){
    const [w,h]=BASE_SIZE[prop.type];
    drawNative(ctx,{
      kind:prop.replaces.kind,p:[prop.x,prop.y],
      size:[w*prop.scale,h*prop.scale],
      angle:prop.rotation*Math.PI/180,
      seed:prop.replaces.seed,solid:!['garden','field','planter','forecourt'].includes(prop.type),
      stall_width:prop.stallWidth,occupancy:prop.occupancy,
      entrance_width:prop.entranceWidth
    },1);
    return;
  }
  if(gameArt&&['parked_car','planter','garden','field','island','forecourt'].includes(prop.type)){
    const [w,h]=BASE_SIZE[prop.type];
    drawNative(ctx,{kind:prop.type,p:[prop.x,prop.y],
      size:[w*prop.scale,h*prop.scale],angle:prop.rotation*Math.PI/180,
      seed:stringSeed(prop.id),solid:prop.type==='parked_car'||prop.type==='island'},1);
    return;
  }
  const size=!gameArt&&(prop.type==='building'||prop.type==='warehouse')?1.2:1;
  ctx.save();ctx.translate(prop.x,prop.y);ctx.rotate(prop.rotation*Math.PI/180);ctx.scale(prop.scale*size,prop.scale*size);
  const type=prop.type;
  if(gameArt){
    // Real metre-scale footprints, directly matching the production baker.
    const kind=gameArtKind(prop);
    const size=BASE_SIZE[prop.type];
    if(size&&drawAtlas(ctx,kind,size,stringSeed(prop.id))){
      ctx.restore();return;
    }
    if(drawGameVectorProp(ctx,prop)){
      ctx.restore();return;
    }
  }
  const asset=prop.assetId?assets.find(item=>item.id===prop.assetId):null;
  if(asset){
    const image=getSprite(asset);
    if(image?.complete && image.naturalWidth){
      const maxSide=['building','warehouse','garage','gas_station','parking'].includes(type)?132:65;
      const ratio=maxSide/Math.max(asset.width,asset.height);
      ctx.drawImage(image,-asset.width*ratio/2,-asset.height*ratio/2,asset.width*ratio,asset.height*ratio);
      ctx.restore();return;
    }
  }
  if(['oak','pine','palm','bush'].includes(type)){
    if(type==='bush'){circle(ctx,0,0,18,'#3c7650');circle(ctx,-8,-5,11,'#549461');}
    else drawTree(ctx,type,stringSeed(prop.id));
  }else if(['house','building','warehouse','garage','gas_station','parking'].includes(type))drawBuilding(ctx,type,prop);
  else if(type==='rock'||type==='boulder'){
    const r=type==='boulder'?26:15;
    ctx.fillStyle='#8b918d';ctx.beginPath();ctx.moveTo(-r,3);ctx.lineTo(-r*.6,-r*.7);ctx.lineTo(r*.4,-r);ctx.lineTo(r,r*.4);ctx.lineTo(0,r*.7);ctx.closePath();ctx.fill();
    ctx.fillStyle='#c6c5b4';ctx.beginPath();ctx.moveTo(-r*.6,-r*.7);ctx.lineTo(r*.4,-r);ctx.lineTo(0,0);ctx.closePath();ctx.fill();
  }else if(type==='streetlight'){
    circle(ctx,0,0,4,'#4e5857');circle(ctx,-1,-2,2,'#ffedb3');
  }else if(type==='sign'){rect(ctx,-3,0,6,23,'#6d6050');rect(ctx,-18,-15,36,17,'#e4d8ab');rect(ctx,-15,-11,30,3,'#8b7c66');}
  else if(type==='barrier'){rect(ctx,-28,-7,56,14,'#e7e1d0');for(let x=-28;x<25;x+=15)rect(ctx,x,-7,8,14,'#c65c4d');}
  else if(type==='dock'){rect(ctx,-21,-64,42,128,'#6e5237');for(let y=-59;y<64;y+=19)rect(ctx,-18,y,36,4,'#b18d57');}
  ctx.restore();
}
function drawMarkers(ctx,markers,bounds){
  for(const marker of markers){
    if(!visible({minX:marker.x-22,minY:marker.y-22,maxX:marker.x+22,maxY:marker.y+22},bounds))continue;
    ctx.save();ctx.translate(marker.x,marker.y);
    ctx.rotate(Math.PI/4);rect(ctx,-9,-9,18,18,marker.type==='player_spawn'?'#f5bc65':'#73d7cc');ctx.strokeStyle='#182a38';ctx.lineWidth=2;ctx.strokeRect(-9,-9,18,18);
    ctx.restore();
    ctx.font='bold 13px system-ui,sans-serif';ctx.fillStyle='#f8fff0';ctx.textAlign='center';ctx.strokeStyle='#152331';ctx.lineWidth=3;
    ctx.strokeText(marker.name,marker.x,marker.y-25);ctx.fillText(marker.name,marker.x,marker.y-25);
  }
}
export function drawWorld(ctx,doc,options={}){
  const bounds=options.bounds||null,quality=options.quality??1;
  ctx.save();
  rect(ctx,0,0,doc.world.width,doc.world.height,
    options.runtimePreview?GAME_BIOME_COLORS.grass:BIOME_COLORS[doc.world.base]);
  if(quality&&!options.runtimePreview){
    const rand=seeded(doc.world.seed+17);
    const step=65;
    for(let y=22;y<doc.world.height;y+=step)for(let x=25;x<doc.world.width;x+=step){
      const px=x+(rand()-.5)*step,py=y+(rand()-.5)*step;
      if(bounds && (px<bounds.minX||px>bounds.maxX||py<bounds.minY||py>bounds.maxY))continue;
      circle(ctx,px,py,1+rand()*4,rand()>.5?'#afba8652':'#254d364a');
    }
  }
  if(options.showTerrain!==false){
    const drawEdited=(region,sourceTerrain=null)=>options.runtimePreview
      ? drawRuntimeEditedRegion(ctx,region,bounds,sourceTerrain)
      : drawRegion(ctx,region,doc.world.seed,quality,bounds);
    if(!options.runtimePreview||
      !drawRuntimeTerrain(ctx,options.runtimePreview,doc,drawEdited))
      for(const region of doc.regions)drawEdited(region);
    if(options.runtimePreview)drawRuntimeExpansion(ctx,options.runtimePreview,doc);
  }
  if(options.showRoads!==false)drawRoads(ctx,doc.roads,bounds,options);
  if(options.showScenery!==false){
    if(options.runtimePreview)drawRuntimeScenery(ctx,options.runtimePreview,bounds,doc,options.zoom||1);
    for(const prop of doc.props){
      if(prop.hidden)continue;
      if(visible({minX:prop.x-200,minY:prop.y-200,maxX:prop.x+200,maxY:prop.y+200},bounds))
        drawProp(ctx,prop,doc.assets||[],Boolean(options.runtimePreview));
    }
  }
  if(options.showMarkers!==false)drawMarkers(ctx,doc.markers,bounds);
  ctx.restore();
}
/** Overlays are editor-only; exports intentionally omit editor node handles. */
export function drawEditorOverlay(ctx,doc,{
  selection=null,draft=null,zoom=1,hover=null,insertMode=null,insertHover=null,
  brushPreview=null,roadsidePreview=null,roadSnapPreview=null,
  alignmentPreview=null,showBoundaries=true,auditIssues=[]
}={}){
  const radius=clamp(7/zoom,5,35);
  if(showBoundaries){
    for(const region of doc.regions){
      stroke(ctx,region.points,true);ctx.strokeStyle='#f3e8a03d';ctx.lineWidth=1.3/zoom;ctx.stroke();
    }
  }
  // Checked issue locations are optional, non-exported editor overlays.
  // Radius is in screen pixels so even huge maps keep legible markers.
  for(const issue of auditIssues.slice(0,120)){
    const p=issue.point;
    if(!p)continue;
    const r=clamp(7/zoom,4,50);
    const color=issue.severity==='error'?'#ef6f69':
      issue.severity==='warning'?'#efbb68':'#86cbd3';
    ctx.beginPath();ctx.arc(p.x,p.y,r*1.35,0,Math.PI*2);
    ctx.strokeStyle=color;ctx.lineWidth=Math.max(1.8/zoom,1.3);ctx.stroke();
    ctx.beginPath();ctx.moveTo(p.x-r*.55,p.y-r*.55);ctx.lineTo(p.x+r*.55,p.y+r*.55);
    ctx.moveTo(p.x-r*.55,p.y+r*.55);ctx.lineTo(p.x+r*.55,p.y-r*.55);
    ctx.stroke();
  }
  if(selection){
    const found=getEntity(doc,selection.id);
    if(found){
      const {item,type}=found;
      if(type==='regions'){
        stroke(ctx,item.points,true);ctx.strokeStyle='#fdb979';ctx.lineWidth=3/zoom;ctx.stroke();
      }else if(type==='roads'){
        drawRoadStroke(ctx,sampleRoad(item.points,item.smooth,8),item.width+5/zoom,'#f8ae6350');
      }else{
        ctx.beginPath();ctx.arc(item.x,item.y,radius*2,0,Math.PI*2);
        ctx.strokeStyle='#ffc987';ctx.lineWidth=2/zoom;ctx.stroke();
      }
      if(type==='roads'||type==='regions'){
        // Visible insertion affordances at the center of each editable span.
        if(type==='roads'){
          const sampled=sampleRoad(item.points,item.smooth,9);
          let cursor=0;
          for(let i=0;i<item.points.length-1;i++){
            const length=Math.hypot(item.points[i+1].x-item.points[i].x,item.points[i+1].y-item.points[i].y);
            const steps=item.smooth&&item.points.length>2?clamp(Math.ceil(length/9),2,80):1;
            const midpoint=sampled[cursor+Math.ceil(steps/2)];
            cursor+=steps;
            if(!midpoint)continue;
            const small=clamp(4/zoom,3,18);
            ctx.beginPath();ctx.arc(midpoint.x,midpoint.y,small*1.65,0,Math.PI*2);
            ctx.fillStyle='#213d45bb';ctx.fill();ctx.strokeStyle='#9fd8cc';ctx.lineWidth=1.6/zoom;ctx.stroke();
            ctx.beginPath();ctx.moveTo(midpoint.x-small,midpoint.y);ctx.lineTo(midpoint.x+small,midpoint.y);
            ctx.moveTo(midpoint.x,midpoint.y-small);ctx.lineTo(midpoint.x,midpoint.y+small);
            ctx.strokeStyle='#e6ffee';ctx.lineWidth=1.4/zoom;ctx.stroke();
          }
        }
        item.points.forEach((p,i)=>{
          circle(ctx,p.x,p.y,radius+1/zoom,i===selection.point?'#ffe6bd':'#263c46');
          ctx.beginPath();ctx.arc(p.x,p.y,radius+1/zoom,0,Math.PI*2);ctx.lineWidth=2/zoom;
          ctx.strokeStyle='#ffe1af';ctx.stroke();
        });
      }
      if(insertHover && (type==='roads'||type==='regions') &&
         insertMode?.id===item.id){
        const point=insertMode.mode==='between'
          ?(type==='roads'?roadInsertCandidate(item,insertHover):regionInsertCandidate(item,insertHover))
          :{x:insertHover.x,y:insertHover.y,distance:0};
        const show=point && (insertMode.mode!=='between'||point.distance<clamp(14/zoom,17,75));
        if(show){
          circle(ctx,point.x,point.y,clamp(9/zoom,7,43),'#bff7e7');
          ctx.beginPath();ctx.arc(point.x,point.y,clamp(9/zoom,7,43),0,Math.PI*2);
          ctx.lineWidth=2/zoom;ctx.strokeStyle='#1c4141';ctx.stroke();
          ctx.beginPath();const size=clamp(5/zoom,4,21);
          ctx.moveTo(point.x-size,point.y);ctx.lineTo(point.x+size,point.y);
          ctx.moveTo(point.x,point.y-size);ctx.lineTo(point.x,point.y+size);
          ctx.lineWidth=2.4/zoom;ctx.strokeStyle='#173932';ctx.stroke();
        }
      }
    }
  }
  if(alignmentPreview?.from&&alignmentPreview?.to){
    const from=alignmentPreview.from,to=alignmentPreview.to;
    const u=1/Math.max(.007,zoom);
    ctx.save();
    ctx.beginPath();ctx.moveTo(from.x,from.y);ctx.lineTo(to.x,to.y);
    ctx.strokeStyle='#e7d89dbb';ctx.lineWidth=1.5*u;
    ctx.setLineDash([6*u,4*u]);ctx.stroke();ctx.setLineDash([]);
    ctx.beginPath();ctx.arc(to.x,to.y,alignmentPreview.radius,0,Math.PI*2);
    ctx.strokeStyle='#b4f0ce';ctx.lineWidth=1.5*u;ctx.stroke();
    ctx.restore();
  }
  if(roadSnapPreview?.from&&roadSnapPreview?.to){
    // A road point will move only when the dedicated snapping toggle is on.
    // Show the exact proposed target BEFORE a click commits it.
    ctx.save();
    const from=roadSnapPreview.from,to=roadSnapPreview.to;
    const r=clamp(5/zoom,3,35);
    ctx.beginPath();ctx.moveTo(from.x,from.y);ctx.lineTo(to.x,to.y);
    ctx.strokeStyle='#ffdf9c';ctx.lineWidth=1.8/zoom;
    ctx.setLineDash([5/zoom,3/zoom]);ctx.stroke();ctx.setLineDash([]);
    ctx.beginPath();ctx.arc(to.x,to.y,r,0,Math.PI*2);
    ctx.strokeStyle='#dffde7';ctx.lineWidth=2/zoom;ctx.stroke();
    ctx.restore();
  }
  if(roadsidePreview){
    // Dashed ghost shows the exact manually requested asset footprint.
    const p=roadsidePreview,r=clamp(p.radius,12,200);
    ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.rotation*Math.PI/180);
    ctx.beginPath();ctx.arc(0,0,r,0,Math.PI*2);
    ctx.fillStyle='#a8e6bc16';ctx.fill();
    ctx.setLineDash([Math.max(4/zoom,3),Math.max(2/zoom,2)]);
    ctx.strokeStyle='#b9f3cf';ctx.lineWidth=Math.max(1.6/zoom,1.2);ctx.stroke();
    ctx.setLineDash([]);
    const half=clamp(25/zoom,6,r*.85);
    ctx.strokeStyle='#eeffe7';ctx.lineWidth=2/zoom;
    ctx.beginPath();ctx.moveTo(0,-half);ctx.lineTo(0,half);ctx.moveTo(-half*.5,half*.52);
    ctx.lineTo(0,half);ctx.lineTo(half*.5,half*.52);ctx.stroke();
    ctx.restore();
  }
  if(brushPreview?.position && Number.isFinite(brushPreview.radius)){
    ctx.beginPath();ctx.arc(brushPreview.position.x,brushPreview.position.y,brushPreview.radius,0,Math.PI*2);
    ctx.fillStyle=brushPreview.erase?'#ed69531f':'#82d3a51b';ctx.fill();
    ctx.strokeStyle=brushPreview.erase?'#f29986':'#c1ffd4';
    ctx.lineWidth=Math.max(1.5/zoom,.8);
    ctx.setLineDash([Math.max(4/zoom,3),Math.max(3/zoom,2)]);ctx.stroke();ctx.setLineDash([]);
    circle(ctx,brushPreview.position.x,brushPreview.position.y,clamp(3/zoom,2,16),
      brushPreview.erase?'#f29a86':'#d5ffe0');
  }
  if(draft?.points?.length){
    const pts=hover?[...draft.points,hover]:draft.points;
    if(draft.type==='road'){
      drawRoadStroke(ctx,sampleRoad(pts,true,10),draft.width||34,'#ffcd854d');
      drawRoadStroke(ctx,sampleRoad(pts,true,10),Math.max(2,2/zoom),'#ffefcf');
    }else{
      stroke(ctx,pts,true);ctx.fillStyle='#f4ba6c44';ctx.fill();
      stroke(ctx,pts);ctx.strokeStyle='#ffe0ad';ctx.lineWidth=2/zoom;ctx.stroke();
    }
    for(const p of draft.points)circle(ctx,p.x,p.y,radius*.75,'#fff0cb');
  }
}
