import {distance, polygonArea, roadAt, scatterPoints, stringSeed} from './world-geometry.js';
import {placeBesideRoad,roadwayClearance,placementFootprint} from './world-road-placement.js';
import {GAME_ART_KINDS} from './morrow-runtime-preview.js';
import {projectArtwork,projectAssetId} from './world-project-assets.js';
import {normalizeRoadJump} from './world-road-jump.js';
import {normalizeRoadElevation} from './world-road-elevation.js';
import {validateMountainRegion} from './world-mountain-barriers.js';

export const WORLD_FORMAT='gdt.racing-world';
export const WORLD_VERSION=2;
export const SURFACES=Object.freeze(['asphalt','concrete','dirt','gravel','track']);
export const ROAD_CLASSES=Object.freeze(['city','highway','country','mountain','track','service','alley','onramp']);
export const BIOMES=Object.freeze(['grass','forest','mountain','rock','beach','ocean','lake','city','desert','farmland','dirt','asphalt']);
export const PROPS=Object.freeze(['oak','pine','palm','bush','rock','boulder','house','building','warehouse','garage','gas_station','streetlight','sign','barrier','dock','parking','parked_car','planter','garden','field','island','forecourt','sidewalk','guardrail','industrial_prop','road_prop','ground_decal']);
export const MARKERS=Object.freeze(['player_spawn','race_start','checkpoint','finish','home','garage','dealership','fuel','mission','fast_travel','traffic_spawn','contract','contract_dropoff','contract_contact','robbery_target','custom']);
const LIM={roads:180,regions:220,props:4000,markers:400,assets:12,roadPoints:100,regionPoints:180};
export const entityLimit=(doc,type)=>doc.customMap===true&&type==='roads'?360:doc.customMap===true&&type==='props'?8000:LIM[type];
const idOk=value=>typeof value==='string'&&/^[a-z][a-z0-9_-]{0,55}$/.test(value);
const gameAssetOk=(assetId,type)=>typeof assetId==='string'&&assetId.startsWith('game-')&&
  (GAME_ART_KINDS[type]||[]).includes(assetId.slice(5));
const assetOk=(doc,prop)=>!prop.assetId||gameAssetOk(prop.assetId,prop.type)||
  Boolean(projectArtwork(prop))||
  doc.assets.some(a=>a.id===prop.assetId);
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
  const {dealer_inventory:inventory,...ordinary}=input;
  if(inventory!==undefined&&(!Array.isArray(inventory)||inventory.length>1000||inventory.some(id=>typeof id!=='string'||!id.length||id.length>100)||new Set(inventory).size!==inventory.length))throw new TypeError('Invalid marker dealership inventory');
  const encoded=JSON.stringify(input);
  if(!encoded||JSON.stringify(ordinary).length>6000)throw new RangeError('Marker properties exceed 6 KB');
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
    if(item.roadClass==='onramp'&&(!['asphalt','concrete'].includes(item.surface)||item.lanes!==1))throw new RangeError('On-ramp must be paved and have one lane');
    const elevation=normalizeRoadElevation(item.elevation,points);
    if(item.roadClass==='onramp'&&elevation?.point_layers?.length>2&&elevation.point_layers.some(l=>l!==elevation.point_layers[0]))throw new RangeError('Use a regular road for a multi-grade on-ramp');
    const road={id:item.id,name:title(item.name,'Road'),roadClass:oneOf(item.roadClass,ROAD_CLASSES,'road class'),
      surface:oneOf(item.surface,SURFACES,'road surface'),width:real(item.width,6,160,'road width'),
      lanes:integer(item.lanes,1,6,'lanes'),shoulder:real(item.shoulder,0,16,'shoulder'),
      smooth:typeof item.smooth==='boolean'?item.smooth:true,
      markings:typeof item.markings==='boolean'?item.markings:true,
      ...(item.independentEnds===true?{independentEnds:true}:{}),
      ...(item.junctionStart!==undefined&&item.junctionStart!=='auto'?{junctionStart:oneOf(item.junctionStart,['intersection','merge'],'start junction mode')}:{}),
      ...(item.junctionEnd!==undefined&&item.junctionEnd!=='auto'?{junctionEnd:oneOf(item.junctionEnd,['intersection','merge'],'end junction mode')}:{}),
      ...(elevation?{elevation}:{}),
      points};
    if(item.autoGuardrails!==undefined){
      const rails=item.autoGuardrails;
      if(!rails||typeof rails!=='object'||Array.isArray(rails)||Object.keys(rails).some(k=>!['left','right'].includes(k)))throw new TypeError('Invalid auto guardrail sides');
      const layers=elevation?.point_layers??[elevation?.start_layer??0,elevation?.end_layer??0];
      if(layers.some(l=>l!==0))throw new RangeError('Auto guardrails require a ground-level road');
      road.autoGuardrails={};
      for(const [side,range] of Object.entries(rails)){
        if(!Array.isArray(range)||range.length!==2)throw new RangeError('Invalid auto guardrail interval');
        const a=real(range[0],0,100,'guardrail start'),b=real(range[1],0,100,'guardrail end');
        if(b<=a)throw new RangeError('Guardrail end must follow start');
        road.autoGuardrails[side]=[a,b];
      }
    }
    const jump=normalizeRoadJump(road,item.jump);
    return jump?{...road,jump}:road;
  }
  if(type==='regions'){
    let points=polygon(item.points,w,h,3,LIM.regionPoints,'terrain');
    if(item.barrier===true){
      points=points.filter((p,i)=>!i||distance(p,points[i-1])>.05);
      if(points.length>2&&distance(points[0],points.at(-1))<.05)points.pop();
      if(points.length<3)throw new RangeError('Mountain barrier needs three distinct outline points');
    }
    if(polygonArea(points)<25)throw new RangeError('Terrain area is too small');
    const region={id:item.id,name:title(item.name,'Region'),biome:oneOf(item.biome,BIOMES,'biome'),
      elevation:real(item.elevation,0,2000,'elevation'),points};
    validateMountainRegion({...region,barrier:item.barrier});
    if(item.barrier===true)region.barrier=true;
    return region;
  }
  if(type==='props'){
    const entity={id:item.id,name:title(item.name,'Scenery'),type:oneOf(item.type,PROPS,'prop type'),
      x:real(item.x,0,w,'prop x'),y:real(item.y,0,h,'prop y'),
      rotation:real(item.rotation,-360,360,'prop rotation'),
      scale:real(item.scale,.2,5,'prop scale'),assetId:!item.assetId?'':(idOk(item.assetId)?item.assetId:(()=>{throw new TypeError('Invalid asset ID');})())};
    for(const axis of ['scaleX','scaleY'])if(item[axis]!==undefined)entity[axis]=real(item[axis],.2,5,'prop axis scale');
    if(item.roadFacing!==undefined){
      if(typeof item.roadFacing!=='boolean')throw new TypeError('Invalid road-facing preference');
      entity.roadFacing=item.roadFacing;
    }
    if(item.roadFront!==undefined)entity.roadFront=oneOf(item.roadFront,[0,90,180,270],'building artwork front');
    if(entity.type==='sidewalk'){
      if(!Array.isArray(item.assetSize)||item.assetSize.length!==2)throw new TypeError('Missing sidewalk footprint');
      entity.assetSize=item.assetSize.map(v=>real(v,.1,12000,'sidewalk footprint'));
      entity.sidewalkWidth=real(item.sidewalkWidth,.8,12,'sidewalk width');
      if(!Array.isArray(item.sidewalkPoints)||item.sidewalkPoints.length<2||item.sidewalkPoints.length>100)throw new TypeError('Invalid sidewalk path');
      entity.sidewalkPoints=item.sidewalkPoints.map(p=>[real(p[0],-12000,12000,'sidewalk x'),real(p[1],-12000,12000,'sidewalk y')]);
    }
    if(entity.type==='guardrail'){
      if(entity.assetId)throw new TypeError('Guardrails use continuous path geometry, not prop sprites');
      if(!Array.isArray(item.assetSize)||item.assetSize.length!==2)throw new TypeError('Missing guardrail bounds');
      entity.assetSize=item.assetSize.map(v=>real(v,.1,12000,'guardrail bounds'));
      entity.guardrailWidth=real(item.guardrailWidth,.35,2.5,'guardrail collision width');
      if(!Array.isArray(item.guardrailPoints)||item.guardrailPoints.length<2||item.guardrailPoints.length>100)
        throw new TypeError('Guardrail requires 2–100 editable points');
      entity.guardrailPoints=item.guardrailPoints.map(p=>{
        if(!Array.isArray(p)||p.length!==2)throw new TypeError('Invalid guardrail control point');
        return [real(p[0],-12000,12000,'rail x'),real(p[1],-12000,12000,'rail y')];
      });
      const ax=entity.scale*(entity.scaleX??1),ay=entity.scale*(entity.scaleY??1),angle=entity.rotation*Math.PI/180;
      const cos=Math.cos(angle),sin=Math.sin(angle);
      let prev=null;
      for(const [x,y] of entity.guardrailPoints){
        const pt={x:entity.x+x*ax*cos-y*ay*sin,y:entity.y+x*ax*sin+y*ay*cos};
        if(pt.x<0||pt.x>w||pt.y<0||pt.y>h)throw new RangeError('Guardrail extends outside map');
        if(prev&&Math.hypot(pt.x-prev.x,pt.y-prev.y)<.5)throw new RangeError('Guardrail points too close');
        prev=pt;
      }
    }
    if(projectAssetId(entity.assetId)){
      const art=projectArtwork({...entity,assetPath:item.assetPath,assetSize:item.assetSize});
      if(!art)throw new TypeError('Missing or invalid project building artwork');
      entity.assetPath=art.path;entity.assetSize=[...art.size];
      if(art.region)entity.assetRegion=[...art.region];
      entity.assetCollision=art.collision;
    }
    if(item.replaces){
      if(item.assetSize)entity.assetSize=item.assetSize.map(v=>real(v,.001,1000,'original footprint'));
      if(item.sourceAppearance)entity.sourceAppearance=validateMetadata(item.sourceAppearance);
      const source=item.replaces;
      if(!source||typeof source!=='object'||Array.isArray(source)||
         typeof source.kind!=='string'||!/^[a-z_]{2,25}$/.test(source.kind)||
         !Number.isInteger(source.seed)||source.seed<0||source.seed>2147483647||
         !Array.isArray(source.p)||source.p.length!==2)
        throw new TypeError('Invalid original game-object reference.');
      entity.replaces={kind:source.kind,seed:source.seed,
        p:[real(source.p[0],0,w,'source x'),real(source.p[1],0,h,'source y')]};
      entity.hidden=item.hidden===true;
    }
    if(entity.type==='parking'){
      entity.stallWidth=real(item.stallWidth??3.2,2.6,5.2,'parking stall width');
      entity.occupancy=real(item.occupancy??.4,0,1,'parking occupancy');
      entity.entranceWidth=real(item.entranceWidth??8,6,10,'parking entrance width');
    }
    return entity;
  }
  if(type==='markers'){
    const properties=validateMetadata(item.properties??{});
    if(properties.dealer_inventory!==undefined&&(item.type!=='dealership'||properties.dealer_id))throw new TypeError('Stock requires an unlinked dealership marker');
    const layer=properties.road_layer??0;
    if(!Number.isInteger(layer)||Math.abs(layer)>2)throw new RangeError('Invalid marker road layer');
    if(layer&&!['contract','contract_contact','contract_dropoff','robbery_target','race_start','checkpoint','finish','mission','custom'].includes(item.type))
      throw new RangeError('Marker type requires ground level');
    return {id:item.id,name:title(item.name,'Marker'),type:oneOf(item.type,MARKERS,'marker type'),
      x:real(item.x,0,w,'marker x'),y:real(item.y,0,h,'marker y'),
      rotation:real(item.rotation,-360,360,'marker rotation'),
      properties};
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
  // Preserve custom-map identity when loading presets in the browser editor.
  // Otherwise an exported starter silently becomes an unpublished demo and
  // cannot be imported for native Test Drive / production publishing.
  if(raw.customMap===true)result.customMap=true;
  // Native gameplay controls must survive browser import/export unchanged.
  if(raw.gameplayZones!==undefined){
    if(!Array.isArray(raw.gameplayZones)||raw.gameplayZones.length>32)throw new RangeError('Invalid gameplay districts');
    result.gameplayZones=raw.gameplayZones.map(z=>{
      if(!z||typeof z.name!=='string'||!z.name.trim()||!['all','passenger','commercial'].includes(z.models))throw new RangeError('Invalid district');
      const x=real(z.x,0,width,'district x'),y=real(z.y,0,height,'district y');
      return {name:z.name,x,y,w:real(z.w,1,width-x,'district width'),h:real(z.h,1,height-y,'district height'),density:real(z.density,0,200,'density'),speed:real(z.speed,0,160,'speed cap'),patrol:real(z.patrol,0,30,'patrol interval'),response:real(z.response,50,150,'response capacity'),models:z.models};
    });
  }
  if(raw.junctionControls!==undefined){
    if(!Array.isArray(raw.junctionControls)||raw.junctionControls.length>128)throw new RangeError('Invalid intersection rules');
    result.junctionControls=raw.junctionControls.map(j=>{
      if(!j||!['stop','yield','signal','uncontrolled'].includes(j.control)||!Array.isArray(j.turns)||!j.turns.length||j.turns.some(t=>!['left','straight','right'].includes(t)))throw new RangeError('Invalid intersection rule');
      const record={x:real(j.x,0,width,'intersection x'),y:real(j.y,0,height,'intersection y'),layer:integer(j.layer,-2,2,'road level'),control:j.control,turns:[...j.turns]};
      if(j.approach!==undefined)record.approach=integer(j.approach,-1,31,'approach index');
      if(j.lane!==undefined)record.lane=integer(j.lane,-1,5,'lane index');
      if((record.lane??-1)>=0&&(record.approach??-1)<0)throw new RangeError('Lane rule requires an approach');
      return record;
    });
  }
  if(raw.editorLayers!==undefined){
    const layers=raw.editorLayers,seen=new Set(),names=new Set();
    if(!result.customMap||!Array.isArray(layers)||layers.length>64)throw new RangeError("Invalid editor layers");
    result.editorLayers=layers.map(l=>{
      if(!l||typeof l.name!=="string"||!l.name.trim()||l.name.length>60||names.has(l.name)||typeof l.visible!=="boolean"||typeof l.locked!=="boolean"||!Array.isArray(l.ids)||l.ids.length>10000)throw new RangeError("Invalid editor layer");
      names.add(l.name);
      for(const id of l.ids){if(typeof id!=="string"||id.length>120||seen.has(id))throw new RangeError("Invalid editor layer member");seen.add(id);}
      return {name:l.name,visible:l.visible,locked:l.locked,ids:[...l.ids]};
    });
  }
  if(raw.terrainHeight!==undefined){
    const h=raw.terrainHeight;
    if(!h||h.size!==129||!Array.isArray(h.values)||h.values.length!==129*129||h.values.some(v=>typeof v!=='number'||!Number.isFinite(v)||Math.abs(v)>1200))throw new RangeError('Invalid authored terrain height field');
    result.terrainHeight={size:129,values:[...h.values]};
  }
  if(raw.morrowSourceRoadCount!==undefined)
    result.morrowSourceRoadCount=integer(raw.morrowSourceRoadCount,0,LIM.roads,'Morrow source road count');
  if(raw.morrowSourcePoiCount!==undefined)
    result.morrowSourcePoiCount=integer(raw.morrowSourcePoiCount,0,LIM.markers,'Morrow source destination count');
  if(raw.morrowRoadWidthScale!==undefined)
    result.morrowRoadWidthScale=real(raw.morrowRoadWidthScale,.1,10,'Morrow road width scale');
  const ids=new Set();
  if(raw.races!==undefined){
    if(!Array.isArray(raw.races)||raw.races.length>64)throw new RangeError('Invalid editor race count');
    result.races=raw.races.map(r=>{
      if(!r||!idOk(r.id)||!r.id.startsWith('race-')||ids.has(r.id))throw new TypeError('Invalid/duplicate race ID');
      ids.add(r.id);
      const mode=oneOf(r.mode,['sprint','circuit'],'race format');
      const points=polygon(r.points,width,height,mode==='circuit'?3:2,100,'race');
      points.forEach((point,i)=>{
        const layer=r.points[i].road_layer??0;
        if(!Number.isInteger(layer)||Math.abs(layer)>2)throw new RangeError('Invalid race checkpoint road layer');
        if(layer)point.road_layer=layer;
      });
      if(points.some((p,i)=>i>0&&distance(p,points[i-1])<5))throw new RangeError('Race checkpoints must be at least 5 m apart');
      // Preserve native-editor grid and event configuration on browser import/export.
      const entry={id:r.id,name:title(r.name,'Editor race'),mode,points,laps:integer(r.laps??1,1,20,'race laps'),
        checkpoint_radius:real(r.checkpoint_radius??16,4,60,'checkpoint radius'),start_radius:real(r.start_radius??8,3,30,'race start radius'),time_limit:real(r.time_limit??0,0,7200,'race time limit')};
      if(r.race_kind!==undefined){
        entry.race_kind=oneOf(r.race_kind,['point_to_point','circuit','time_trial'],'race type');
        if((entry.race_kind==='circuit')!==(mode==='circuit')||
           (entry.race_kind==='time_trial'&&(r.enemy_starts??[]).length))
          throw new TypeError('Race type does not match its route or rivals');
      }
      const pool=r.opponent_pool??[];
      if(!Array.isArray(pool)||pool.length>128||pool.some(id=>typeof id!=='string'||!idOk(id))||new Set(pool).size!==pool.length)
        throw new TypeError('Invalid race opponent vehicle IDs');
      if(r.opponent_pool!==undefined)entry.opponent_pool=[...pool];
      for(const [key,max] of [['reward_cash',1000000],['reward_player_xp',100000],['reward_car_xp',100000]])
        if(r[key]!==undefined)entry[key]=integer(r[key],0,max,key);
      // Match native Godot and the production Python baker. Older authored
      // maps have no override and retain the standard friend-race rewards.
      if(r.multiplayer_reward_custom!==undefined){
        if(typeof r.multiplayer_reward_custom!=='boolean')
          throw new TypeError('Multiplayer prize override must be a boolean');
        entry.multiplayer_reward_custom=r.multiplayer_reward_custom;
      }
      for(const [key,max] of [['multiplayer_reward_cash',Number.MAX_SAFE_INTEGER],
          ['multiplayer_reward_player_xp',Number.MAX_SAFE_INTEGER],
          ['multiplayer_reward_car_xp',Number.MAX_SAFE_INTEGER],
          ['multiplayer_reward_part_chance',100]]){
        if(r.multiplayer_reward_custom===true&&r[key]===undefined)
          throw new TypeError('Missing configured multiplayer prize: '+key);
        if(r[key]!==undefined){
          if(!Number.isSafeInteger(r[key]))throw new RangeError('Invalid exact integer '+key);
          entry[key]=integer(r[key],0,max,key);
        }
      }
      if(r.category!==undefined)entry.category=oneOf(r.category,['street','circuit','time_trial','championship','challenge'],'event category');
      if(r.difficulty!==undefined)entry.difficulty=oneOf(r.difficulty,['rookie','amateur','pro','elite'],'event difficulty');
      if(r.repeatable!==undefined){
        if(typeof r.repeatable!=='boolean')throw new TypeError('Race repeatable must be boolean');
        entry.repeatable=r.repeatable;
      }
      for(const [field,min,max] of [['required_player_level',1,100],['required_car_level',1,50],
        ['first_win_reward_cash',0,1000000],['first_win_reward_player_xp',0,100000],
        ['first_win_reward_car_xp',0,100000],['race_heat',0,5],['escape_time_limit',30,300],
        ['entry_fee',0,50000],['underground_rep_reward',0,30],['required_underground_rep',0,100000]]){
        if(r[field]!==undefined)entry[field]=integer(r[field],min,max,field);
      }
      if((entry.race_heat??0)===0&&(entry.underground_rep_reward??0)>0)
        throw new TypeError('Underground race reputation requires wanted level above zero');
      for(const field of ['prerequisite_races','required_vehicle_ids']){
        if(r[field]===undefined)continue;
        const items=r[field];
        if(!Array.isArray(items)||items.length>(field==='prerequisite_races'?16:128)||
          items.some(id=>typeof id!=='string'||!idOk(id))||new Set(items).size!==items.length||
          (field==='prerequisite_races'&&items.includes(r.id)))throw new TypeError('Invalid '+field);
        entry[field]=[...items];
      }
      if(r.formation!==undefined)entry.formation=oneOf(r.formation,['single_file','side_by_side','staggered'],'race grid formation');
      const pose=s=>{
        if(!s||typeof s!=='object')throw new TypeError('Invalid race grid slot');
        return {...point(s,width,height),rotation:real(s.rotation,-360,360,'grid angle')};
      };
      if(r.player_start!==undefined)entry.player_start=pose(r.player_start);
      if(r.enemy_starts!==undefined){
        if(!Array.isArray(r.enemy_starts)||r.enemy_starts.length>6||r.enemy_starts.length&&!entry.player_start)
          throw new TypeError('Invalid race starting grid');
        entry.enemy_starts=r.enemy_starts.map(pose);
      }
      return entry;
    });
  }
  if(result.races){
    const events=new Map(result.races.map(e=>[e.id,e]));
    const visiting=new Set(),visited=new Set();
    const walk=id=>{
      if(!events.has(id)||visiting.has(id))throw new TypeError('Missing or cyclic race prerequisite: '+id);
      if(visited.has(id))return;
      visiting.add(id);
      for(const required of events.get(id).prerequisite_races??[])walk(required);
      visiting.delete(id);visited.add(id);
    };
    for(const event of result.races)walk(event.id);
  }
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
    if(!Array.isArray(raw[type])||raw[type].length>entityLimit(raw,type))throw new RangeError('Invalid '+type+' count');
    result[type]=raw[type].map(item=>{
      const checked=validEntity(item,type,width,height);
      if(ids.has(checked.id))throw new TypeError('Duplicate entity ID: '+checked.id);
      ids.add(checked.id);return checked;
    });
  }
  // Preserve native-map dealership edits in browser Map Builder round-trips.
  // Dealer records are source overrides, never duplicated vehicle definitions.
  if(raw.dealerships!==undefined){
    if(!Array.isArray(raw.dealerships)||raw.dealerships.length>64)throw new RangeError('Invalid dealership count');
    const dealerIds=new Set();
    result.dealerships=raw.dealerships.map(value=>{
      if(!value||typeof value!=='object'||!idOk(value.id)||dealerIds.has(value.id))
        throw new TypeError('Invalid or duplicate dealership ID');
      dealerIds.add(value.id);
      const record={id:value.id};
      for(const key of ['name','tier','region','texture']){
        if(value[key]!==undefined){
          if(typeof value[key]!=='string'||value[key].length>180)throw new TypeError('Invalid dealership '+key);
          record[key]=value[key];
        }
      }
      if((value.x===undefined)!==(value.y===undefined))throw new TypeError('Dealership position needs x and y');
      if(value.x!==undefined){record.x=real(value.x,0,width,'dealership x');record.y=real(value.y,0,height,'dealership y');}
      if(value.lot_width_m!==undefined)record.lot_width_m=real(value.lot_width_m,18,70,'dealer lot width');
      if(value.lot_depth_m!==undefined)record.lot_depth_m=real(value.lot_depth_m,14,60,'dealer lot depth');
      if(value.inventory_mode!==undefined)
        record.inventory_mode=oneOf(value.inventory_mode,['automatic','manual'],'dealer inventory mode');
      if(value.inventory!==undefined){
        if(!Array.isArray(value.inventory)||value.inventory.length>1000||
            value.inventory.some(id=>typeof id!=='string'||!id.length||id.length>100)||
            new Set(value.inventory).size!==value.inventory.length)
          throw new TypeError('Invalid dealership vehicle IDs');
        record.inventory=value.inventory.slice();
      }
      return record;
    });
  }
  const raceIds=new Set((result.races??[]).map(e=>e.id));
  const dealerIds=new Set((result.dealerships??[]).map(e=>e.id));
  let playerSpawns=0;
  const byMarkerId=new Map(result.markers.map(m=>[m.id,m]));
  for(const marker of result.markers){
    if(marker.type==='player_spawn')playerSpawns++;
    const info=marker.properties??{};
    if(info.description!==undefined&&(typeof info.description!=='string'||info.description.length>500))
      throw new TypeError('Invalid map marker description');
    for(const field of ['race_id','required_race']){
      if(info[field]!==undefined&&(
        typeof info[field]!=='string'||info[field].length>100||
        (info[field]!==''&&!raceIds.has(info[field]))))
        throw new TypeError('Marker references unknown race: '+field);
    }
    if(info.dealer_id!==undefined&&(
      typeof info.dealer_id!=='string'||info.dealer_id.length>100||
      (info.dealer_id!==''&&!dealerIds.has(info.dealer_id))))
      throw new TypeError('Marker references unknown dealership');
    if(info.contract_kind!==undefined&&!['courier','smuggling','getaway'].includes(info.contract_kind))
      throw new TypeError('Invalid driving contract type');
    if(info.destination_marker_id!==undefined&&(
      typeof info.destination_marker_id!=='string'||info.destination_marker_id.length>100))
      throw new TypeError('Invalid driving contract destination');
    if(marker.type==='contract'&&info.destination_marker_id){
      const dest=byMarkerId.get(info.destination_marker_id);
      if(!dest||dest.type!=='contract_dropoff'||dest.id===marker.id)
        throw new TypeError('Contract destination must link to a dropoff marker');
      const distance=Math.hypot(marker.x-dest.x,marker.y-dest.y);
      if(distance<100||distance>15000)
        throw new RangeError('Driving contract distance must be between 100 and 15000 metres');
    }
    if(info.contact_style!==undefined&&!['street','business','mechanic','casual','racing'].includes(info.contact_style))
      throw new TypeError('Invalid contact appearance');
    for(const [field,max] of [['contact_role',60],['contact_greeting',180],['contact_bio',240]]){
      if(info[field]!==undefined&&(typeof info[field]!=='string'||info[field].length>max))
        throw new TypeError('Invalid contact personality field: '+field);
    }
    if(info.offers!==undefined){
      if(marker.type!=='contract_contact'||!Array.isArray(info.offers)||info.offers.length>8)
        throw new TypeError('Contact must have no more than eight jobs');
      const seenOffers=new Set();
      for(const offer of info.offers){
        if(!offer||typeof offer!=='object'||Array.isArray(offer))throw new TypeError('Invalid job');
        if(typeof offer.id!=='string'||!/^[A-Za-z_][A-Za-z0-9_]{0,55}$/.test(offer.id)||
           seenOffers.has(offer.id))throw new TypeError('Duplicate/invalid contract job ID');
        seenOffers.add(offer.id);
        if(typeof offer.title!=='string'||!offer.title.trim()||offer.title.length>80)
          throw new TypeError('Invalid contract title');
        if(offer.description!==undefined&&
           (typeof offer.description!=='string'||offer.description.length>400))
          throw new TypeError('Invalid contract briefing description');
        if(!['courier','smuggling','getaway','robbery'].includes(offer.kind)||
           !['rookie','amateur','pro','elite'].includes(offer.difficulty??'rookie'))
          throw new TypeError('Invalid job type or difficulty');
        if(offer.required_race_id!==undefined&&(typeof offer.required_race_id!=='string'||
          (offer.required_race_id!==''&&!raceIds.has(offer.required_race_id))))
          throw new TypeError('Contract requires an existing race victory');
        if(offer.repeatable!==undefined&&typeof offer.repeatable!=='boolean')
          throw new TypeError('Invalid repeatability');
        for(const [key,min,max] of [['cash',0,10000],['player_xp',0,1500],['car_xp',0,1200],
             ['underground_rep',0,30],['wanted_level',0,5],['required_player_level',1,100],
             ['required_underground_rep',0,100000],['time_limit_seconds',60,900],
             ['robbery_hold_seconds',3,30],['arrival_radius_m',6,30]]){
          if(offer[key]!==undefined)integer(offer[key],min,max,key);
        }
        const destination=byMarkerId.get(offer.destination_marker_id);
        if(!destination||destination.type!=='contract_dropoff'||
           Math.hypot(destination.x-marker.x,destination.y-marker.y)<100||
           Math.hypot(destination.x-marker.x,destination.y-marker.y)>15000)
          throw new TypeError('Job requires connected dropoff marker between 100m and 15km');
        if(offer.kind==='robbery'){
          const target=byMarkerId.get(offer.robbery_marker_id);
          if(!target||target.type!=='robbery_target'||target.id===destination.id||
             Math.hypot(target.x-marker.x,target.y-marker.y)<100||
             Math.hypot(target.x-destination.x,target.y-destination.y)<100)
            throw new TypeError('Robbery requires a separate target at least 100m from pickup and dropoff');
        }else if(offer.robbery_marker_id)throw new TypeError('Non-robbery job has robbery target');
      }
    }
    if(info.enabled!==undefined&&typeof info.enabled!=='boolean')throw new TypeError('Invalid marker enabled flag');
    if(info.radius_m!==undefined)real(info.radius_m,4,50,'marker radius');
    if(info.traffic_weight!==undefined)integer(info.traffic_weight,1,10,'traffic spawn priority');
  }
  if(playerSpawns>1)throw new TypeError('Only one player spawn marker is allowed');
  for(const prop of result.props)if(!assetOk(result,prop))throw new TypeError('Unknown or incompatible scenery artwork: '+prop.assetId);
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
  if(doc[type].length>=entityLimit(doc,type))throw new RangeError('Maximum '+type+' reached');
  const id=unique(type==='roads'?'road':type==='regions'?'region':type==='props'?'prop':'marker',
    ['roads','regions','props','markers'].flatMap(t=>doc[t]));
  let item=validEntity({id,...input},type,doc.world.width,doc.world.height);
  if(type==='props'){
    if(!assetOk(doc,item))throw new TypeError('Unknown or incompatible game asset');
    // Manually authored objects use the exact chosen coordinates. Road alignment
    // is an explicit user action and environment presets can opt in themselves.
  }
  // Gameplay markers intentionally have no spatial snapping, road clearance,
  // or overlap restrictions. Only valid coordinates within the world apply.
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
  const merged={...item,...patch,id};
  if(type==='roads'&&item.elevation?.point_layers&&patch.points&&patch.points.length!==item.points.length&&!Object.hasOwn(patch,'elevation'))
    throw new RangeError('Use insert/remove point to keep the elevation profile aligned');
  if(type==='props'&&patch.assetId!==undefined&&patch.assetId!==item.assetId){
    delete merged.assetPath;delete merged.assetSize;delete merged.assetRegion;delete merged.assetCollision;
  }
  let updated=validEntity(merged,type,doc.world.width,doc.world.height);
  if(type==='props'){
    if(!assetOk(doc,updated))throw new TypeError('Unknown or incompatible game asset');
    // Preserve exact positions and rotation for BOTH adopted game objects and
    // newly placed props. Never move another entity as a side effect.
    // Road overlaps are reported by Map health and the live safety overlay;
    // they do not mutate placement during dragging, editing, or resizing.
  }
  // Dragging or editing a marker never moves it away from roads, buildings,
  // other markers or water. Retain its exact requested coordinate.
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
  const patch={points};
  if(found.type==='roads'&&found.item.elevation?.point_layers){
    const layers=[...found.item.elevation.point_layers];
    const a=layers[Math.max(0,index-1)],b=layers[Math.min(index,layers.length-1)];
    // Choose the feasible adjacent level. Reject if neither fits.
    const options=[...new Set([a,b])];
    for(const layer of options){
      const next=layers.slice();next.splice(index,0,layer);
      try{return updateEntity(doc,id,{points,elevation:{start_layer:next[0],end_layer:next.at(-1),point_layers:next}});}catch(e){if(!(e instanceof RangeError))throw e;}
    }
    throw new RangeError('Inserted point would create a steep grade; reposition it or adjust the point heights');
  }
  return updateEntity(doc,id,patch);
}
export function deleteControlPoint(doc,id,index){
  const found=getEntity(doc,id);
  if(!found||!['roads','regions'].includes(found.type))return doc;
  if(found.item.points.length<=(found.type==='roads'?2:3))throw new RangeError('Too few control points');
  const points=found.item.points.filter((_,i)=>i!==index);
  if(found.type==='roads'&&found.item.elevation?.point_layers){
    const layers=found.item.elevation.point_layers.filter((_,i)=>i!==index);
    return updateEntity(doc,id,{points,elevation:{start_layer:layers[0],end_layer:layers.at(-1),point_layers:layers}});
  }
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
