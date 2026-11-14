/** Read-only production scenery preview. Baked Morrow Coast has ~19,000
 * scenery instances; they remain in spatial buckets instead of masquerading
 * as 19,000 editable procedural source records.
 *
 * Source artwork and region bounds are shared with scripts/world/coast_art.gd.
 */
import {stringSeed} from './world-geometry.js';
import {textureTerrain,textureTerrainRect} from './world-terrain-materials.js';

export const GAME_ATLAS = '/game-assets/scenery/morrow-atlas-v1.png';
export const GAME_ART = Object.freeze([
  ['game-house','House roof'],['game-coastal_house','Coastal house'],
  ['game-shop','Shop / cafe'],['game-garage','Garage / showroom'],
  ['game-tree','Deciduous tree'],['game-pine','Pine tree'],
  ['game-palm','Palm tree'],['game-rock','Rock formation']
]);
export const GAME_ART_KINDS = Object.freeze({
  oak:['tree','pine','palm'],pine:['tree','pine','palm'],palm:['tree','pine','palm'],
  house:['house','coastal_house'],building:['shop','garage'],
  warehouse:['shop','garage'],garage:['shop','garage'],
  gas_station:['shop','garage'],rock:['rock'],boulder:['rock']
});
export const BASE_SIZE = Object.freeze({
  oak:[7,7],pine:[7,7],palm:[6.5,6.5],bush:[2.5,2.5],
  rock:[3,2.5],boulder:[4.5,3.4],house:[12,17],
  building:[22,29],warehouse:[28,37],garage:[20,21],
  gas_station:[18,17],streetlight:[1.3,1.3],sign:[1.6,1.4],
  barrier:[3,1],parking:[38,28],dock:[3,11],
  parked_car:[1.9,4.6],planter:[2.8,2.8],garden:[8,2.4],
  field:[90,70],island:[23,23],forecourt:[23,16]
});
export const REPLACEABLE_KINDS = Object.freeze({
  tree:'oak',pine:'pine',palm:'palm',rock:'rock',
  house:'house',coastal_house:'house',
  shop:'building',building:'building',warehouse:'warehouse',
  garage:'garage',workshop:'garage',showroom:'building',
  fuel:'gas_station',bush:'bush',lamp:'streetlight',sign:'sign',
  barrier:'barrier',dock:'dock',lot:'parking',forecourt:'forecourt',
  parked_car:'parked_car',planter:'planter',garden:'garden',
  field:'field',island:'island'
});
export function nativeAdoptedRadius(prop){
  if(!prop.replaces)return null;
  const kind=prop.replaces.kind;
  if(['tree','pine','palm'].includes(kind))return .65;
  if(kind==='bush')return 0;
  const size=BASE_SIZE[prop.type]||[3,3];
  return Math.hypot(size[0],size[1])*.5*prop.scale;
}
const ATLAS_REGIONS = [
  [103,28,261,391],[532,14,273,409],[968,26,278,396],
  [1411,21,281,396],[26,477,397,380],[472,467,388,389],
  [910,467,406,387],[1366,500,361,323]
];
const trafficFiles = [
  'ChatGPT Image Nov 8, 2026, 09_28_42 PM-1.png',
  'ChatGPT Image Nov 8, 2026, 09_28_46 PM-2.png',
  'ChatGPT Image Nov 8, 2026, 09_28_47 PM-3.png',
  'ChatGPT Image Nov 8, 2026, 09_28_49 PM-4.png',
  'ChatGPT Image Nov 8, 2026, 09_28_50 PM-5.png',
  'ChatGPT Image Nov 8, 2026, 09_28_51 PM-6.png',
  'ChatGPT Image Nov 8, 2026, 09_28_52 PM-7.png',
  'ChatGPT Image Nov 8, 2026, 09_28_53 PM-8.png',
  'ChatGPT Image Nov 8, 2026, 09_28_55 PM-9.png',
  'ChatGPT Image Nov 8, 2026, 09_28_56 PM-10.png'
];
const images=new Map();
function imageAt(url){
  if(images.has(url))return images.get(url);
  if(typeof Image==='undefined')return null;
  const img=new Image();
  images.set(url,img);
  img.onload=()=>document.dispatchEvent(new Event('gdt-world-asset-ready'));
  img.onerror=()=>document.dispatchEvent(new Event('gdt-world-asset-ready'));
  img.src=url;
  return img;
}
const ready=img=>!!(img?.complete&&img.naturalWidth);
function atlasIndex(kind,seed){
  if(kind==='house'||kind==='lodge')return seed%3===0?1:0;
  if(kind==='coastal_house')return 1;
  if(kind==='shop'||kind==='cafe')return 2;
  if(['garage','workshop','warehouse','showroom','fuel','building'].includes(kind))return 3;
  return {tree:4,pine:5,palm:6,rock:7}[kind]??-1;
}
export function hasGameArt(prop){
  return GAME_ART.some(([id])=>id===prop.assetId);
}
export function gameArtKind(prop){
  if(prop.assetId?.startsWith('game-'))return prop.assetId.slice(5);
  return ({oak:'tree',pine:'pine',palm:'palm',house:'house',
    garage:'garage',building:'building',warehouse:'warehouse',
    gas_station:'fuel',rock:'rock',boulder:'rock'})[prop.type]||'';
}
/** Call within a translation/rotation at the actual footprint and scale. */
export function drawAtlas(ctx,kind,size,seed=0){
  const img=imageAt(GAME_ATLAS),index=atlasIndex(kind,seed);
  if(index<0||!ready(img))return false;
  const [sx,sy,sw,sh]=ATLAS_REGIONS[index];
  ctx.drawImage(img,sx,sy,sw,sh,-size[0]/2,-size[1]/2,size[0],size[1]);
  return true;
}
export function preloadGameArtwork(){
  imageAt(GAME_ATLAS);
  // Traffic files are loaded only as needed by the visible viewport.
}

/** Exact metre-based preview primitives for game props without atlas art. */
export function drawGameVectorProp(ctx,prop){
  const size=BASE_SIZE[prop.type];
  if(!size)return false;
  const [w,h]=size,type=prop.type;
  ctx.save();
  if(type==='parking'){
    ctx.fillStyle='#555e60';ctx.fillRect(-w/2,-h/2,w,h);
    const stalls=Math.max(3,Math.floor(w*.84/(prop.stallWidth||3.2)));
    ctx.strokeStyle='#dedbc8';ctx.lineWidth=.15;
    for(const side of [-1,1])for(let i=0;i<=stalls;i++){
      const x=-w*.42+w*.84*i/stalls;
      ctx.beginPath();ctx.moveTo(x,side*h*.45);ctx.lineTo(x,side*h*.22);ctx.stroke();
    }
    ctx.fillStyle='#5b6466';ctx.fillRect(-w/2-.6,-(prop.entranceWidth||8)/2,
      w*.17,prop.entranceWidth||8);
  }else if(type==='bush'){
    ctx.fillStyle='#4e8154';ctx.beginPath();
    ctx.ellipse(0,0,w/2,h/2,0,0,Math.PI*2);ctx.fill();
  }else if(type==='streetlight'){
    ctx.fillStyle='#d8c9a4';ctx.beginPath();ctx.arc(0,0,.45,0,Math.PI*2);ctx.fill();
  }else if(type==='sign'){
    ctx.fillStyle='#d9d4b9';ctx.fillRect(-w/2,-h/2,w,h);
  }else if(type==='dock'){
    ctx.fillStyle='#78684b';ctx.fillRect(-w/2,-h/2,w,h);
    for(let y=-h/2;y<h/2;y+=1.2){
      ctx.strokeStyle='#b19b70';ctx.lineWidth=.12;
      ctx.beginPath();ctx.moveTo(-w/2,y);ctx.lineTo(w/2,y);ctx.stroke();
    }
  }else if(type==='barrier'){
    ctx.fillStyle='#d9dbd1';ctx.fillRect(-w/2,-h/2,w,h);
    ctx.fillStyle='#c16559';ctx.fillRect(-w*.25,-h/2,w*.18,h);
    ctx.fillRect(w*.12,-h/2,w*.18,h);
  }else{
    ctx.restore();return false;
  }
  ctx.restore();return true;
}
function bucketKey(x,y,cell){return Math.floor(x/cell)+','+Math.floor(y/cell);}
export function buildRuntimePreview(raw){
  if(!raw||raw.format!=='streetbound.streamed-world')throw new TypeError('Invalid streamed world');
  const cell=192,buckets=new Map(),props=raw.props||[],roads=new Map();
  const sourceSize=(raw.size||[6400,4800]).map(Number);
  // Use the exact baked intersection polygons instead of inventing wide
  // convex junction aprons that do not exist in the playable game.
  const junctions=(raw.junctions||[]).map(j=>({
    roads:(j.roads||[]).map(id=>'road-'+id),
    polygon:(j.polygon||[]).map(([x,y])=>({x:+x,y:+y})),
    at:{x:+j.p[0],y:+j.p[1]},
    radius:+j.radius||40,control:String(j.control||'none'),
    approaches:j.approaches||[],curbs:j.curbs||[]
  }));
  const sourceTerrain=(raw.terrain||[]).map((t,index)=>({
    index,editorId:t.authoring_id||'region-'+index,kind:String(t.kind),color:String(t.color||''),barrier:t.barrier===true,elevation:Number(t.elevation)||0,
    generatedExtension:t.generated_extension===true,
    points:(t.points||[]).map(([x,y])=>({x:+x,y:+y}))
  }));
  const extensionTerrain=(raw.terrain||[]).filter(t=>t.generated_extension);
  for(const [index,road] of (raw.roads||[]).entries()){
    roads.set('road-'+index,{anchors:road.anchors||road.points,
      points:(road.points||[]).map(([x,y])=>({x:+x,y:+y})),
      width:+road.width,surface:road.surface});
  }
  for(const item of props){
    if(!item.p||!item.size)continue;
    const key=bucketKey(+item.p[0],+item.p[1],cell);
    if(!buckets.has(key))buckets.set(key,[]);
    buckets.get(key).push(item);
  }
  // The playable map's scenery does not live in the editable authoring
  // document until an object is deliberately adopted. Preserve a separate
  // lightweight, nearby-first browser of the REAL baked assets so the UI
  // never reports "0 objects" for a populated world.
  const spawn=raw.spawn?.position||[sourceSize[0]*.5,sourceSize[1]*.5];
  const assetBrowser=props.filter(item=>Array.isArray(item.p)&&item.p.length>=2&&
    Array.isArray(item.size)&&item.size.length>=2)
    .sort((a,b)=>{
      const dist=item=>(Number(item.p[0])-Number(spawn[0]))**2+
        (Number(item.p[1])-Number(spawn[1]))**2;
      return dist(a)-dist(b);
    });
  const authoredIds=new Set(props.map(prop=>prop.authoring_id).filter(id=>typeof id==='string'));
  preloadGameArtwork();
  return {cell,buckets,roads,junctions,sourceTerrain,propsCount:props.length,
    assetBrowser,authoredIds,sourceSize,extensionTerrain};
}

/** Return a bounded list of the game's REAL scenery without copying the
 * entire procedural world into the source editor. Include protected landmark
 * objects as read-only rows; adopting one would invalidate gameplay sites.
 * This is UI-only metadata and never changes the baked JSON or overlay.
 */
export function browseRuntimeAssets(preview,doc,limit=180){
  if(!preview)return {total:0,rows:[]};
  const ids=new Set((doc.props||[]).map(p=>p.id));
  const replaced=new Set((doc.props||[]).filter(p=>p.replaces)
    .map(p=>sourceKey(p.replaces)));
  const rows=[];
  for(const prop of preview.assetBrowser||[]){
    if((prop.authoring_id&&ids.has(prop.authoring_id))||
        replaced.has(sourceKey(prop)))continue;
    const editable=Boolean(REPLACEABLE_KINDS[prop.kind]&&!prop.poi&&!prop.authoring_id);
    rows.push({source:prop,editable,
      name:String(prop.poi||('Game '+String(prop.kind||'scenery').replaceAll('_',' '))),
      x:Number(prop.p[0]),y:Number(prop.p[1])});
    if(rows.length>=limit)break;
  }
  return {total:preview.propsCount,rows};
}
function hashColor(prop){
  const n=stringSeed(String(prop.kind)+String(prop.seed));
  return ['#819c78','#778c72','#90a481','#6f8670'][n%4];
}
export function drawNative(ctx,prop,scale){
  const kind=String(prop.kind),seed=Number(prop.seed)||0;
  const size=prop.size.map(Number),w=size[0],h=size[1];
  if(scale<.2 && !['house','lodge','garage','shop','showroom',
    'warehouse','building','fuel','lot','forecourt','parked_car'].includes(kind) &&
    seed % (scale<.10?15:6)!==0)return;
  ctx.save();
  ctx.translate(Number(prop.p[0]),Number(prop.p[1]));
  ctx.rotate(Number(prop.angle)||0);
  if(kind==='sidewalk'){
    const points=prop.sidewalk_points||[],factor=prop.sidewalk_scale||[1,1];
    ctx.scale(factor[0],factor[1]);ctx.lineJoin='round';ctx.lineCap='round';
    for(const [extra,color] of [[.3,'#777f79'],[.1,'#d8d5c7'],[-.2,'#bcbdb3']]){
      ctx.beginPath();points.forEach((p,i)=>i?ctx.lineTo(p[0],p[1]):ctx.moveTo(p[0],p[1]));
      ctx.lineWidth=(prop.sidewalk_width||3)+extra;ctx.strokeStyle=color;ctx.stroke();
    }ctx.restore();return;
  }
  if(kind==='lot'||kind==='forecourt'){
    ctx.fillStyle=kind==='lot'?'#525959':'#7e8783';
    ctx.fillRect(-w/2,-h/2,w,h);
    if(kind==='lot'){
      ctx.strokeStyle='#d0ceb0';ctx.lineWidth=.15;
      const stalls=Math.max(3,Math.floor(w*.84/(prop.stall_width||3.2)));
      for(const side of [-1,1])for(let i=0;i<=stalls;i++){
        const x=-w*.42+w*.84*i/stalls;
        ctx.beginPath();ctx.moveTo(x,side*h*.44);
        ctx.lineTo(x,side*h*.22);ctx.stroke();
      }
    }
  }else if(kind==='parked_car'){
    const slot=((seed%trafficFiles.length)+trafficFiles.length)%trafficFiles.length;
    const img=imageAt('/game-assets/Traffic%20Vehicles/'+encodeURIComponent(trafficFiles[slot]));
    ctx.fillStyle='#334449';ctx.fillRect(-w/2,-h/2,w,h);
    if(ready(img))ctx.drawImage(img,-w/2,-h/2,w,h);
  }else if(drawAtlas(ctx,prop.asset_kind||kind,size,seed)){
    if(prop.poi){
      const title=String(prop.poi);
      ctx.font='bold '+Math.max(2,Math.min(3,w*.12))+'px sans-serif';
      ctx.textAlign='center';
      ctx.fillStyle='#eed3a3';
      ctx.fillText(title.slice(0,24),0,h*.33,Math.max(5,w*.86));
    }
  }else if(kind==='field'||kind==='garden'){
    ctx.fillStyle=kind==='field'?'#abb48a':'#67945f';
    ctx.globalAlpha=.7;ctx.fillRect(-w/2,-h/2,w,h);
  }else if(kind==='planter'||kind==='bush'){
    ctx.fillStyle=hashColor(prop);ctx.beginPath();
    ctx.ellipse(0,0,w/2,h/2,0,0,Math.PI*2);ctx.fill();
  }else if(kind==='island'){
    ctx.fillStyle='#688d63';ctx.beginPath();ctx.ellipse(0,0,w/2,h/2,0,0,Math.PI*2);ctx.fill();
  }else if(kind==='lamp'||kind==='sign'||kind==='barrier'){
    ctx.fillStyle=kind==='lamp'?'#e3d7ad':'#d0c6a5';
    ctx.fillRect(-w/2,-h/2,Math.max(w,.5),Math.max(h,.5));
  }else if(kind==='dock'){
    ctx.fillStyle='#876a49';ctx.fillRect(-w/2,-h/2,w,h);
  }else if(['tree','pine','palm'].includes(kind)){
    ctx.fillStyle=hashColor(prop);ctx.beginPath();ctx.arc(0,0,w/2,0,Math.PI*2);ctx.fill();
  }else if(prop.solid){
    ctx.fillStyle='#8b9a8d';ctx.fillRect(-w/2,-h/2,w,h);
  }
  ctx.restore();
}
/** Preserve the full-resolution game coastline and water polygon. Imported
 * editing proxies contain <=180 handles and must not repaint the ocean as a
 * coarse polygon. Only actually edited regions use their editable geometry.
 * Keep the original terrain draw order, including riverbank/foam layers.
 */
export function drawRuntimeTerrain(ctx,preview,doc,drawEdited){
  if(!preview?.sourceTerrain)return false;
  const byId=new Map(doc.regions.map(region=>[region.id,region]));
  const sourceHeight=preview.sourceSize[1],sourceWidth=preview.sourceSize[0];
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
  const simplified=(points,max=180)=>{
    const result=points.map(p=>({x:clamp(p.x,0,sourceWidth),y:clamp(p.y,0,sourceHeight)}));
    if(result.length>1&&Math.hypot(result[0].x-result.at(-1).x,result[0].y-result.at(-1).y)<.001)
      result.pop();
    if(result.length<=max)return result;
    return Array.from({length:max},(_,i)=>result[Math.floor(i*result.length/max)]);
  };
  const colors={forest:'#718d70',mountain:'#9baba0',highland:'#9baba0',
    farmland:'#b4bd8a',city:'#b1b6a0',town:'#a3b789',beach:'#e3d4aa',
    ocean:'#82b5b5',water:'#82b5b5',lake:'#82b5b5',
    riverbank:'#c6d9c9',foam:'#c6d9c9'};
  for(const terrain of preview.sourceTerrain){
    if(terrain.generatedExtension)continue;
    const edited=byId.get(terrain.editorId||'region-'+terrain.index);
    if(edited){
      const source=simplified(terrain.points);
      const sameShape=edited.points.length===source.length&&
        edited.points.every((p,i)=>Math.hypot(p.x-source[i].x,p.y-source[i].y)<.025);
      const sourceBiome=terrain.kind==='water'?'lake':
        terrain.kind==='town'?'grass':terrain.kind;
      if(!sameShape||edited.biome!==sourceBiome||Boolean(edited.barrier)!==Boolean(terrain.barrier)){
        // Changed geometry replaces only this source region in its original
        // draw order; preserve the baked palette for a moved, same-kind coast.
        drawEdited(edited,terrain);
        continue;
      }
    }
    if(terrain.points.length<3)continue;
    ctx.beginPath();
    ctx.moveTo(terrain.points[0].x,terrain.points[0].y);
    for(let i=1;i<terrain.points.length;i++)
      ctx.lineTo(terrain.points[i].x,terrain.points[i].y);
    ctx.closePath();
    ctx.fillStyle=/^[0-9a-f]{6}$/i.test(terrain.color)?'#'+terrain.color:
      colors[terrain.kind]||'#a3b789';
    ctx.fill();
    textureTerrain(ctx,terrain.kind);
  }
  // The ID format alone cannot identify a new region: the editor allocates
  // numeric region-N IDs too. Compare against actual source terrain indices.
  // Derived foam/riverbank/highland are not independent editable regions.
  const sourceIds=new Set(preview.sourceTerrain
    .filter(t=>!t.generatedExtension&&!['foam','riverbank','highland'].includes(t.kind))
    .map(t=>t.editorId||'region-'+t.index));
  for(const region of doc.regions){
    if(!sourceIds.has(region.id))drawEdited(region);
  }
  return true;
}

/** Existing added terrain masks plus a temporary preview of unsaved growth.
 * Only new ground is painted; old world coordinates/polygons are untouched.
 */
export function drawRuntimeExpansion(ctx,preview,doc){
  if(!preview)return;
  const colors={ocean:'#82b5b5',beach:'#e3d4aa',foam:'#c6d9c9'};
  const polygon=(points,color)=>{
    if(points.length<3)return;
    ctx.beginPath();ctx.moveTo(points[0][0],points[0][1]);
    for(let i=1;i<points.length;i++)ctx.lineTo(points[i][0],points[i][1]);
    ctx.closePath();ctx.fillStyle=color;ctx.fill();
    textureTerrain(ctx,Object.keys(colors).find(key=>colors[key]===color)||'grass');
  };
  for(const terrain of preview.extensionTerrain||[])
    polygon(terrain.points,colors[terrain.kind]||'#a3b789');
  const [oldW,oldH]=preview.sourceSize||[6400,4800];
  const width=doc.world.width,height=doc.world.height;
  if(width>oldW){
    ctx.fillStyle=colors.ocean;
    ctx.fillRect(oldW,0,width-oldW,height);
    textureTerrainRect(ctx,'ocean',oldW,0,width-oldW,height);
  }
  if(height>oldH){
    const shore=y=>5190+115*Math.sin((y-4800)/560);
    const coast=[[shore(oldH),oldH]];
    for(let y=oldH+5;y<=height;y+=5)coast.push([shore(y),y]);
    if(coast.at(-1)[1]<height)coast.push([shore(height),height]);
    polygon([...coast,[oldW,height],[oldW,oldH]],colors.ocean);
    polygon(coast.map(([x,y])=>[x-65,y]).concat([...coast].reverse()),colors.beach);
  }
}

/** Draw the real baked props (including city, parking and forest details).
 * Authored prop IDs are rendered using live editor state instead to avoid
 * overlapping old and new positions before the next bake.
 */
function sourceKey(prop){
  return String(prop.kind)+'|'+String(prop.seed)+'|'+Number(prop.p[0]).toFixed(3)+','+
    Number(prop.p[1]).toFixed(3);
}
/** Pick an unadopted native game object by its rotated visible footprint.
 * The previous small-center radius rejected clicks on most of a house roof.
 * Prefer the nearest candidate when objects have overlapping silhouettes.
 */
export function pickRuntimeProp(preview,doc,point,radius=12){
  if(!preview)return null;
  const excluded=new Set(doc.props.filter(p=>p.replaces).map(p=>sourceKey(p.replaces)));
  let winner=null,best=Infinity,bestLayer=Infinity;
  const cell=preview.cell,x=Math.floor(point.x/cell),y=Math.floor(point.y/cell);
  for(let ix=x-1;ix<=x+1;ix++)for(let iy=y-1;iy<=y+1;iy++)
    for(const prop of preview.buckets.get(ix+','+iy)||[]){
      if(!REPLACEABLE_KINDS[prop.kind]||prop.poi||prop.authoring_id||
          excluded.has(sourceKey(prop))||!prop.size||!prop.p)continue;
      const dx=point.x-Number(prop.p[0]),dy=point.y-Number(prop.p[1]);
      const width=Number(prop.size[0]),height=Number(prop.size[1]);
      if(!(width>0&&height>0))continue;
      const angle=Number(prop.angle)||0,c=Math.cos(angle),s=Math.sin(angle);
      const localX=dx*c+dy*s,localY=-dx*s+dy*c;
      const padding=Math.min(8,Math.max(0,radius)*.2);
      if(Math.abs(localX)>width/2+padding ||
          Math.abs(localY)>height/2+padding)continue;
      const distance=Math.hypot(dx,dy);
      // Houses/shops sit on top of large terrain-like props (fields, gardens,
      // lots). Never make a ground-cover center hide a visible house roof.
      const layer=['house','coastal_house','shop','building','warehouse',
        'garage','workshop','showroom','fuel'].includes(prop.kind)?0:
        ['field','garden','forecourt','lot','island'].includes(prop.kind)?2:1;
      if(layer<bestLayer||(layer===bestLayer&&distance<best)){
        winner=prop;best=distance;bestLayer=layer;
      }
    }
  return winner;
}
export function drawRuntimeScenery(ctx,preview,bounds,doc,scale=1){
  if(!preview)return;
  const ids=new Set(doc.props.map(p=>p.id));
  const replaced=new Set(doc.props.filter(p=>p.replaces).map(p=>sourceKey(p.replaces)));
  const cell=preview.cell,area=bounds||{minX:0,minY:0,maxX:doc.world.width,maxY:doc.world.height};
  const x0=Math.max(0,Math.floor(area.minX/cell)-1),y0=Math.max(0,Math.floor(area.minY/cell)-1);
  const x1=Math.min(Math.ceil(doc.world.width/cell),Math.floor(area.maxX/cell)+1);
  const y1=Math.min(Math.ceil(doc.world.height/cell),Math.floor(area.maxY/cell)+1);
  for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++){
    for(const prop of preview.buckets.get(x+','+y)||[]){
      if((prop.authoring_id&&ids.has(prop.authoring_id))||replaced.has(sourceKey(prop)))continue;
      const px=Number(prop.p[0]),py=Number(prop.p[1]);
      const pad=Math.max(+prop.size[0],+prop.size[1])*.75+3;
      if(px+pad<area.minX||px-pad>area.maxX||py+pad<area.minY||py-pad>area.maxY)continue;
      drawNative(ctx,prop,scale);
    }
  }
}
