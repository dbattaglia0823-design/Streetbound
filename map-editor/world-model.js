import {distance, polygonArea, roadAt, scatterPoints, stringSeed} from './world-geometry.js';
import {placeBesideRoad,placeSiteMarker,roadwayClearance,placementFootprint} from './world-road-placement.js';

export const WORLD_FORMAT='gdt.racing-world';
export const WORLD_VERSION=2;
export const SURFACES=Object.freeze(['asphalt','concrete','dirt','gravel','track']);
export const ROAD_CLASSES=Object.freeze(['city','highway','country','mountain','track','service']);
export const BIOMES=Object.freeze(['grass','forest','mountain','rock','beach','ocean','lake','city','desert','farmland']);
export const PROPS=Object.freeze(['oak','pine','palm','bush','rock','boulder','house','building','warehouse','garage','gas_station','streetlight','sign','barrier','dock','parking']);
export const MARKERS=Object.freeze(['player_spawn','race_start','checkpoint','finish','garage','dealership','fuel','mission','fast_travel','traffic_spawn','custom']);
const LIM={roads:180,regions:220,props:4000,markers:400,assets:12,roadPoints:100,regionPoints:180};
const idOk=value=>typeof value==='string'&&/^[a-z][a-z0-9_-]{0,55}$/.test(value);
const title=(value, fallback)=> typeof value==='string' ? (value.trim().slice(0,80)||fallback):fallback;
const integer=(n,min,max,label)=>{if(!Number.isInteger(n)||n<min||n>max)throw new RangeError('Invalid '+label);return n;};
const real=(n,min,max,label)=>{if(typeof n!=='number'||!Number.isFinite(n)||n<min||n>max)throw new RangeError('Invalid '+label);return n;};
const oneOf=(n,values,label)=>{if(!values.includes(n))throw new TypeError('Invalid '+label);return n;};
const point=(p,w,h)=> {
  if(!p||typeof p!=='object')throw new TypeError('Invalid geometry point');
  return {x:real(p.x,0,w,'point x'),y:real(p.y,0,h,'point y')};
};
const polygon=(points,w,h,min,max,label)=>{
  if(!Array.isArray(points)||points.length<min||points.length>max)throw new RangeError('Invalid '+label+' control points');
  return points.map(p=>point(p,w,h));
};
function validateMetadata(input){
  if(!input||typeof input!=='object'||Array.isArray(input))throw new TypeError('Marker properties must be a JSON object');
  const encoded=JSON.stringify(input);
  if(!encoded||encoded.length>6000)throw new RangeError('Marker properties exceed 6 KB');
  const decoded=JSON.parse(encoded);
  if(Object.keys(decoded).some(k=>['__proto__','constructor','prototype'].includes(k)))throw new TypeError('Unsupported marker property key');
  return decoded;
}
const unique=(prefix,values)=>{
  const used=new Set(values.map(item=>item.id));let n=1;
  while(used.has(prefix+'-'+n))n++;
  return prefix+'-'+n;
};
function validEntity(item,type,w,h){
  if(!item||typeof item!=='object'||!idOk(item.id))throw new TypeError('Invalid entity ID');
  if(type==='roads'){
    const points=polygon(item.points,w,h,2,LIM.roadPoints,'road');
    if(points.every(p=>distance(p,points[0])<1))throw new RangeError('Road must have length');
    return {id:item.id,name:title(item.name,'Road'),roadClass:oneOf(item.roadClass,ROAD_CLASSES,'road class'),
      surface:oneOf(item.surface,SURFACES,'road surface'),width:real(item.width,6,160,'road width'),
      lanes:integer(item.lanes,1,6,'lanes'),shoulder:real(item.shoulder,0,16,'shoulder'),
      smooth:typeof item.smooth==='boolean'?item.smooth:true,
      markings:typeof item.markings==='boolean'?item.markings:true,
      points};
  }
  if(type==='regions'){
    const points=polygon(item.points,w,h,3,LIM.regionPoints,'terrain');
    if(polygonArea(points)<25)throw new RangeError('Terrain area is too small');
    return {id:item.id,name:title(item.name,'Region'),biome:oneOf(item.biome,BIOMES,'biome'),
      elevation:real(item.elevation,0,2000,'elevation'),points};
  }
  if(type==='props'){
    const entity={id:item.id,name:title(item.name,'Scenery'),type:oneOf(item.type,PROPS,'prop type'),
      x:real(item.x,0,w,'prop x'),y:real(item.y,0,h,'prop y'),
      rotation:real(item.rotation,-360,360,'prop rotation'),
      scale:real(item.scale,.25,5,'prop scale'),assetId:!item.assetId?'':(idOk(item.assetId)?item.assetId:(()=>{throw new TypeError('Invalid asset ID');})())};
    if(entity.type==='parking'){
      entity.stallWidth=real(item.stallWidth??3.2,2.6,5.2,'parking stall width');
      entity.occupancy=real(item.occupancy??.4,0,1,'parking occupancy');
      entity.entranceWidth=real(item.entranceWidth??8,6,10,'parking entrance width');
    }
    return entity;
  }
  if(type==='markers'){
    return {id:item.id,name:title(item.name,'Marker'),type:oneOf(item.type,MARKERS,'marker type'),
      x:real(item.x,0,w,'marker x'),y:real(item.y,0,h,'marker y'),
      rotation:real(item.rotation,-360,360,'marker rotation'),
      properties:validateMetadata(item.properties??{})};
  }
  throw new TypeError('Unsupported entity type');
}
export function createWorld({name='New racing world',width=3200,height=2200,seed=1847,base='grass'}={}){
  integer(width,600,24000,'world width');integer(height,600,24000,'world height');
  integer(seed,0,2147483647,'world seed');oneOf(base,BIOMES,'base biome');
  return {format:WORLD_FORMAT,version:WORLD_VERSION,name:title(name,'Untitled world'),
    world:{width,height,seed,base},roads:[],regions:[],props:[],markers:[],assets:[]};
}
export function normalizeWorld(raw){
  if(!raw||typeof raw!=='object'||raw.format!==WORLD_FORMAT||raw.version!==WORLD_VERSION)
    throw new TypeError('Unsupported world file. Use the Legacy Tile Editor for v1 tile maps.');
  if(!raw.world||typeof raw.world!=='object')throw new TypeError('Missing world bounds');
  const width=integer(raw.world.width,600,24000,'world width');
  const height=integer(raw.world.height,600,24000,'world height');
  const seed=integer(raw.world.seed,0,2147483647,'world seed');
  const base=oneOf(raw.world.base,BIOMES,'base biome');
  const result={format:WORLD_FORMAT,version:WORLD_VERSION,name:title(raw.name,'Untitled world'),
    world:{width,height,seed,base},roads:[],regions:[],props:[],markers:[],assets:[]};
  const ids=new Set();
  const allAssets=raw.assets??[];
  if(!Array.isArray(allAssets)||allAssets.length>LIM.assets)throw new RangeError('Invalid sprite asset count');
  let assetBytes=0;
  for(const asset of allAssets){
    if(!asset||typeof asset!=='object'||!idOk(asset.id)||ids.has(asset.id))throw new TypeError('Invalid/duplicate sprite asset ID');
    if(typeof asset.src!=='string'||!/^data:image\/(?:png|webp);base64,[A-Za-z0-9+/=]+$/.test(asset.src)||asset.src.length>1_400_000)throw new TypeError('Only embedded PNG/WebP sprite assets under 1 MB are supported');
    assetBytes+=asset.src.length;
    if(assetBytes>7_000_000)throw new RangeError('Sprite artwork exceeds 7 MB');
    result.assets.push({id:asset.id,name:title(asset.name,'Custom sprite'),src:asset.src,
      width:integer(asset.width,1,2048,'sprite width'),height:integer(asset.height,1,2048,'sprite height')});
    ids.add(asset.id);
  }
  for(const type of ['roads','regions','props','markers']){
    if(!Array.isArray(raw[type])||raw[type].length>LIM[type])throw new RangeError('Invalid '+type+' count');
    result[type]=raw[type].map(item=>{
      const checked=validEntity(item,type,width,height);
      if(ids.has(checked.id))throw new TypeError('Duplicate entity ID: '+checked.id);
      ids.add(checked.id);return checked;
    });
  }
  for(const prop of result.props)if(prop.assetId && !result.assets.some(a=>a.id===prop.assetId))throw new TypeError('Unknown sprite asset: '+prop.assetId);
  return result;
}
export const parseWorld = raw => {
  if(typeof raw!=='string'||raw.length>8_000_000)throw new RangeError('World JSON must be under 8 MB');
  return normalizeWorld(JSON.parse(raw));
};
export const serializeWorld = world => JSON.stringify(normalizeWorld(world),null,2)+'\n';
export function getEntity(doc,id){
  for(const type of ['roads','regions','props','markers']){
    const item=doc[type].find(item=>item.id===id);
    if(item)return {type,item};
  }
  return null;
}
export function createEntity(doc,type,input){
  if(!['roads','regions','props','markers'].includes(type))throw new TypeError('Unsupported entity collection');
  if(doc[type].length>=LIM[type])throw new RangeError('Maximum '+type+' reached');
  const id=unique(type==='roads'?'road':type==='regions'?'region':type==='props'?'prop':'marker',
    ['roads','regions','props','markers'].flatMap(t=>doc[t]));
  let item=validEntity({id,...input},type,doc.world.width,doc.world.height);
  if(type==='props'){
    if(item.assetId&&!doc.assets.some(a=>a.id===item.assetId))throw new TypeError('Unknown sprite asset');
    item=validEntity(placeBesideRoad(doc,item),type,doc.world.width,doc.world.height);
  }else if(type==='markers'){
    item=validEntity(placeSiteMarker(doc,item),type,doc.world.width,doc.world.height);
  }
  return {...doc,[type]:[...doc[type],item]};
}
/** Keep imported artwork embedded in versioned world JSON; no external image hosts. */
export function addSpriteAsset(doc,{name,src,width,height}){
  if(doc.assets.length>=LIM.assets)throw new RangeError('Maximum of 12 custom sprite assets');
  const id=unique('asset',[...doc.assets,...doc.roads,...doc.regions,...doc.props,...doc.markers]);
  return normalizeWorld({...doc,assets:[...doc.assets,{id,name,src,width,height}]});
}
export function updateEntity(doc,id,patch){
  const found=getEntity(doc,id);
  if(!found)return doc;
  const {type,item}=found;
  let updated=validEntity({...item,...patch,id},type,doc.world.width,doc.world.height);
  if(type==='props'){
    if(updated.assetId&&!doc.assets.some(a=>a.id===updated.assetId))throw new TypeError('Unknown sprite asset');
    // Hand-authored rotation remains editable. Position, type and scale edits
    // recalculate the curb setback and local road tangent automatically.
    if(['x','y','scale','type','assetId'].some(key=>Object.hasOwn(patch,key))){
      updated=validEntity(placeBesideRoad(doc,updated),type,doc.world.width,doc.world.height);
    }else if(roadwayClearance(doc,updated,placementFootprint(doc,updated))<0){
      updated=validEntity(placeBesideRoad(doc,updated,{snap:false,align:false}),type,doc.world.width,doc.world.height);
    }
  }else if(type==='markers'&&['x','y','type'].some(key=>Object.hasOwn(patch,key))){
    updated=validEntity(placeSiteMarker(doc,updated),type,doc.world.width,doc.world.height);
  }
  return {...doc,[type]:doc[type].map(value=>value.id===id?updated:value)};
}
export function removeEntity(doc,id){
  const found=getEntity(doc,id);
  if(!found)return doc;
  return {...doc,[found.type]:doc[found.type].filter(item=>item.id!==id)};
}
export function reorderEntity(doc,id,delta){
  const found=getEntity(doc,id);
  if(!found)return doc;
  const items=doc[found.type].slice(),from=items.findIndex(item=>item.id===id),to=from+delta;
  if(to<0||to>=items.length)return doc;
  [items[from],items[to]]=[items[to],items[from]];
  return {...doc,[found.type]:items};
}
export function moveControlPoint(doc,id,index,pos){
  const found=getEntity(doc,id);
  if(!found||!['roads','regions'].includes(found.type))return doc;
  if(index<0||index>=found.item.points.length)throw new RangeError('Invalid control point index');
  const points=found.item.points.slice();
  points[index]=point(pos,doc.world.width,doc.world.height);
  return updateEntity(doc,id,{points});
}
export function insertControlPoint(doc,id,index,pos){
  const found=getEntity(doc,id);
  if(!found||!['roads','regions'].includes(found.type))return doc;
  const points=found.item.points.slice();
  if(points.length>=LIM[found.type==='roads'?'roadPoints':'regionPoints'])throw new RangeError('Too many control points');
  if(!Number.isInteger(index)||index<0||index>points.length)throw new RangeError('Invalid insertion index');
  points.splice(index,0,point(pos,doc.world.width,doc.world.height));
  return updateEntity(doc,id,{points});
}
export function deleteControlPoint(doc,id,index){
  const found=getEntity(doc,id);
  if(!found||!['roads','regions'].includes(found.type))return doc;
  if(found.item.points.length<=(found.type==='roads'?2:3))throw new RangeError('Too few control points');
  const points=found.item.points.filter((_,i)=>i!==index);
  return updateEntity(doc,id,{points});
}
/** Continuous vegetation placement with collision-aware road clearance. */
export function scatterVegetation(doc,regionId,count=50,type='auto'){
  const region=doc.regions.find(r=>r.id===regionId);
  if(!region)throw new TypeError('Select a terrain region to scatter');
  integer(count,1,350,'scatter count');
  const preferred={forest:'pine',grass:'oak',beach:'palm',desert:'rock',mountain:'pine',
    rock:'boulder',city:'streetlight',farmland:'bush',ocean:'',lake:''}[region.biome];
  const propType=type==='auto'?preferred:oneOf(type,PROPS,'scatter prop');
  if(!propType)throw new TypeError('Cannot scatter vegetation on open water');
  if(doc.props.length+count>LIM.props)throw new RangeError('Too many props');
  const seed=stringSeed(region.id+'-'+region.biome+'-'+doc.world.seed+'-'+doc.props.length);
  const points=scatterPoints(region.points,count*6,seed,p=>!roadAt(doc,p));
  const newProps=[],occupied=new Set([...doc.props].map(p=>p.id));
  let n=doc.props.length+1;
  for(const p of points){
    if(newProps.length>=count)break;
    while(occupied.has('prop-'+n))n++;
    const id='prop-'+n++;occupied.add(id);
    const initial=validEntity({id,name:propType.replace(/_/g,' '),type:propType,x:p.x,y:p.y,
      rotation:(seed+n*71)%360,scale:.65+((seed+n*197)%115)/100},'props',doc.world.width,doc.world.height);
    try{
      const placed=placeBesideRoad({...doc,props:[...doc.props,...newProps]},initial);
      // Sampling a point in a terrain region must not teleport objects outside it.
      if(roadwayClearance(doc,placed,placementFootprint(doc,placed))>=0 &&
          newProps.every(other=>distance(other,placed)>=Math.min(25,placementFootprint(doc,placed))))
        newProps.push(validEntity(placed,'props',doc.world.width,doc.world.height));
    }catch{/* Skip unavailable curb space; never place a prop into a road. */}
  }
  return {...doc,props:[...doc.props,...newProps]};
}
export function demoWorld(){
  const doc=createWorld({name:'Coastal Ridge · Open World',width:3400,height:2300,seed:4319});
  let regionId=0,roadId=0,propId=0,markerId=0;
  const region=(biome,name,xy,elevation=0)=>({id:'region-'+(++regionId),biome,name,
    elevation,points:xy.map(([x,y])=>({x,y}))});
  doc.regions.push(
    region('mountain','Highland cliffs',[[0,0],[1450,0],[1280,240],[800,440],[400,770],[0,690]],540),
    region('rock','Rocky foothills',[[0,610],[420,520],[710,790],[1150,840],[970,1280],[250,1440],[0,1160]],155),
    region('forest','Pinewood preserve',[[0,1140],[380,1220],[730,1410],[1100,1740],[1250,2250],[0,2300]],45),
    region('city','Harbor city',[[1170,560],[2410,390],[2880,840],[2810,1650],[1970,1940],[1110,1480]],22),
    region('beach','Coastline',[[2750,0],[3050,0],[2960,500],[3020,900],[2890,1410],[3100,1950],[3400,2200],[3400,2300],[2990,2300],[2750,1740],[2650,1080]],2),
    region('ocean','Open ocean',[[3060,0],[3400,0],[3400,2300],[3290,2300],[3060,1960],[2960,1580],[3010,1020],[3000,680]],0),
    region('lake','Mountain reservoir',[[410,230],[770,190],[1000,340],[950,550],[670,620],[400,490]],95),
    region('grass','Coastal park',[[1980,1530],[2470,1480],[2840,1710],[2920,2110],[2550,2300],[2110,2110]],13)
  );
  const road=(name,roadClass,surface,width,lanes,xy,shoulder=5,markings=true)=>({
    id:'road-'+(++roadId),name,roadClass,surface,width,lanes,shoulder,markings,smooth:true,
    points:xy.map(([x,y])=>({x,y}))
  });
  doc.roads.push(
    road('Coastal Parkway','highway','asphalt',46,2,[[1080,240],[1500,390],[1970,450],[2480,560],[2650,780],[2720,1180],[2570,1650],[2380,2090],[2120,2290]],7),
    road('Ridge Pass','mountain','asphalt',30,2,[[110,1180],[410,1050],[580,770],[900,720],[1150,520],[1260,300],[1060,180],[780,210]],4),
    road('Old Forest Road','country','asphalt',32,2,[[0,1780],[380,1690],[730,1590],[1070,1440],[1390,1290],[1660,1130],[1970,1050],[2250,930],[2700,950]],5),
    road('Downtown Avenue','city','asphalt',40,2,[[1420,730],[1760,820],[2100,880],[2460,970],[2720,1180]],4),
    road('Harbor Boulevard','city','concrete',38,2,[[1610,1780],[1740,1500],[1930,1190],[2100,880],[2250,540]],3),
    road('Cedar Street','city','asphalt',28,2,[[1220,1100],[1590,1190],[1930,1190],[2300,1320],[2630,1440]],3),
    road('Mountain access','country','gravel',23,1,[[410,1050],[300,790],[150,540],[290,360],[480,240]],3,false),
    road('Beach approach','service','dirt',20,1,[[2570,1650],[2820,1800],[2950,1960],[3100,2070]],2,false),
    road('Factory access','service','concrete',23,1,[[1760,820],[1690,620],[1550,540]],2,false)
  );
  const prop=(type,x,y,scale=1,rotation=0,name)=>({id:'prop-'+(++propId),name:name||type.replace(/_/g,' '),type,x,y,scale,rotation});
  for(let i=0;i<28;i++)for(let j=0;j<2;j++){
    const x=1410+i%7*165+j*65,y=680+Math.floor(i/7)*280+j*85;
    if(x<2530&&y<1680 && !roadAt(doc,{x,y}))doc.props.push(prop(i%5===0?'warehouse':i%3===0?'building':'house',x,y,.75+(i%4)*.14,i%2?90:0));
  }
  doc.props.push(prop('garage',1620,580,1.6),prop('gas_station',2290,1160,1.35,12),
    prop('parking',2100,1430,2,0),prop('dock',3180,1690,2.2,95),
    prop('streetlight',1960,890,.8),prop('streetlight',2020,910,.8),prop('streetlight',2080,930,.8));
  for(const r of doc.regions.filter(r=>['forest','mountain','rock','beach','grass'].includes(r.biome))){
    const sample=scatterPoints(r.points,r.biome==='forest'?160:r.biome==='mountain'?95:r.biome==='beach'?47:65,stringSeed(r.name+doc.world.seed));
    for(let i=0;i<sample.length;i++){
      const p=sample[i];
      if(roadAt(doc,p))continue;
      const type=r.biome==='beach'?'palm':r.biome==='mountain'?(i%5?'pine':'rock'):r.biome==='rock'?(i%3?'boulder':'bush'):r.biome==='forest'?(i%5?'pine':'oak'):(i%3?'oak':'bush');
      doc.props.push(prop(type,p.x,p.y,.58+(i%7)*.13,i*67%360));
    }
  }
  const marker=(type,name,x,y,properties={})=>({id:'marker-'+(++markerId),type,name,x,y,rotation:0,properties});
  doc.markers.push(marker('player_spawn','Player start',1530,720),
    marker('garage','Motorsport workshop',1600,570),
    marker('race_start','Coastal sprint start',1870,440),
    marker('checkpoint','Harbor checkpoint',2650,825),
    marker('finish','Coastal sprint finish',2600,1600),
    marker('fuel','Harbor fuel station',2300,1190),
    marker('fast_travel','Pinewood lookout',650,1040));
  return normalizeWorld(doc);
}
