/**
 * Morrow Coast authoring bridge (Streetbound streamed-world v1 -> World Forge v2).
 * Imports actual authored road anchors (not thousands of baked tessellation
 * points) and the stable terrain/POI IDs. Generated scenery/physics indices
 * remain owned by tools/build_morrow_coast.py and are never edited as if
 * they were independent source assets.
 */
import {normalizeWorld} from './world-model.js';

export const MORROW_SOURCE='../worlds/morrow-coast.world.json';
export const MORROW_EDIT_NAME='morrow-coast.edits.world.json';
const BIOMES=new Set(['grass','forest','mountain','rock','beach','ocean','lake','city','desert','farmland']);
const biomeOf=kind=>BIOMES.has(kind)?kind:kind==='water'?'lake':
  ['town','highland'].includes(kind)?'grass':kind==='riverbank'?'beach':'grass';
const roadClassOf=kind=>({
  local:'city',arterial:'city',highway:'highway',rural:'country',
  mountain:'mountain',track:'track',driveway:'service',gravel:'service'
})[kind]||'city';
const surfaceOf=surface=>surface==='GRAVEL'?'gravel':
  surface==='DIRT'?'dirt':'asphalt';
const clamp=(v,low,high)=>Math.max(low,Math.min(high,v));
function pointsOf(items){
  return items.map(point=>({x:+point[0],y:+point[1]}));
}
function simplifyPolygon(items,max=180){
  // Import is intentionally a reviewable proxy, not lossy overwriting of
  // original coast/river masks. The rebaker only changes edited polygons.
  // Original ocean/river masks may intentionally extend past the game map.
  // The editor clamps only its preview; unchanged high-detail source is safe.
  const pts=pointsOf(items).map(p=>({x:clamp(p.x,0,6400),y:clamp(p.y,0,4800)}));
  if(pts.length>1 && Math.hypot(pts[0].x-pts.at(-1).x,pts[0].y-pts.at(-1).y)<.001)pts.pop();
  if(pts.length<=max)return pts;
  return Array.from({length:max},(_,i)=>pts[Math.floor(i*pts.length/max)]);
}
function poiType(poi){
  const category=String(poi.category||'');
  return category.includes('DEALERSHIP')?'dealership':
    category.includes('FUEL')?'fuel':
    category.includes('GARAGE')||category.includes('CUSTOMIZATION')?'garage':
    category.includes('RACE')||category.includes('DRAG')?'race_start':'custom';
}
export function convertMorrowWorld(raw){
  if(!raw||raw.format!=='streetbound.streamed-world'||raw.version!==1)
    throw new TypeError('This is not a Streetbound Morrow Coast streamed-world v1 file.');
  const width=raw.size[0],height=raw.size[1];
  const roads=raw.roads.map((road,index)=>({
    id:'road-'+index,name:String(road.name||'Road'),roadClass:roadClassOf(road.kind),
    surface:surfaceOf(road.surface),width:clamp(+road.width,6,160),
    lanes:clamp(road.lanes||2,1,6),shoulder:road.kind==='highway'?4:2,
    smooth:true,markings:road.surface!=='GRAVEL',
    points:pointsOf(road.anchors||road.points)
  }));
  const regions=[];
  for(const [index,terrain] of raw.terrain.entries()){
    if(regions.length>=220)break;
    if(!terrain.points||terrain.points.length<3)continue;
    // Avoid duplicating riverbank/foam masks with identical footprints.
    if(['foam','riverbank','highland'].includes(terrain.kind))continue;
    const polygon=simplifyPolygon(terrain.points);
    if(polygon.length<3)continue;
    regions.push({id:'region-'+index,name:String(terrain.kind)+' '+index,
      biome:biomeOf(terrain.kind),elevation:0,points:polygon});
  }
  const markers=[{id:'marker-0',name:'Morrow Coast Player Start',
    type:'player_spawn',x:+raw.spawn.position[0],y:+raw.spawn.position[1],
    rotation:(+raw.spawn.rotation||0)*180/Math.PI,properties:{}}];
  for(const [index,poi] of (raw.pois||[]).entries()){
    if(markers.length>=400)break;
    markers.push({id:'marker-'+(index+1),name:String(poi.name),
      type:poiType(poi),x:+poi.position[0],y:+poi.position[1],
      rotation:0,properties:{}});
  }
  // Procedural forest/city props remain source-owned. Only explicit
  // authored IDs are editable and survive a production-world rebake.
  const props=(raw.props||[]).filter(prop=>typeof prop.authoring_id==='string')
    .slice(0,200).map(prop=>({
      id:prop.authoring_id,name:prop.editor_name||prop.editor_type||'Scenery',
      type:prop.editor_type,
      x:+prop.p[0],y:+prop.p[1],scale:+(prop.editor_scale||1),
      rotation:+prop.angle*180/Math.PI,assetId:'',
      stallWidth:prop.stall_width,occupancy:prop.occupancy,
      entranceWidth:prop.entrance_width
    }));
  const result=normalizeWorld({
    format:'gdt.racing-world',version:2,name:'Morrow Coast',
    world:{width,height,seed:28114,base:'grass'},
    roads,regions,props,markers,assets:[]
  });
  return {doc:result,stats:{roads:roads.length,regions:regions.length,
    landmarkMarkers:markers.length,proceduralProps:raw.props?.length||0,
    generatedJunctions:raw.junctions?.length||0}};
}

export async function loadMorrowCoast(){
  const response=await fetch(MORROW_SOURCE,{cache:'no-store'});
  if(!response.ok)throw new Error('Cannot load Morrow Coast. Start the editor with Start Map Editor.cmd so repository world files are served.');
  const raw=await response.json();
  return convertMorrowWorld(raw);
}

export function isMorrowEdit(doc){
  // Explicit selection, not just a similar-looking world name.
  return doc.name==='Morrow Coast'&&
    doc.world.width===6400&&doc.world.height===4800&&
    doc.roads.some(r=>/^road-\d+$/.test(r.id));
}

/** This remains editable v2 JSON; production bake validates each numbered
 * road against the authored source before changing any world geometry.
 */
export function morrowEditText(doc){
  if(!isMorrowEdit(doc))throw new TypeError('Open Morrow Coast first before saving edits into its authoring file.');
  return JSON.stringify(doc,null,2)+'\n';
}
