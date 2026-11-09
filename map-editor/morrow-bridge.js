/**
 * Lossless ROAD-EDIT BRIDGE from Streetbound's production Morrow Coast v1
 * to freeform World Forge v2. Source scenery, coastline, junctions, bridge
 * clearance and spatial indexes are NEVER rewritten by the browser. Instead,
 * export a small validated patch that the Python production baker replays
 * before rebuilding all downstream artifacts and safety checks.
 */
import {normalizeWorld} from './world-model.js';
import {distance} from './world-geometry.js';

const ROAD_CLASS={local:'city',arterial:'city',highway:'highway',
  rural:'country',mountain:'mountain',track:'track',
  driveway:'service',gravel:'service'};
const KINDS={city:'local',highway:'highway',country:'rural',
  mountain:'mountain',track:'track',service:'driveway'};
const SURFACES=new Set(['asphalt','concrete','track','dirt','gravel']);
const pos=a=>({x:Number(a[0]),y:Number(a[1])});
const vec=p=>[+p.x.toFixed(3),+p.y.toFixed(3)];
const same=(a,b,tolerance=.2)=>distance(a,b)<=tolerance;

export function openMorrowWorld(source){
  if(source?.format!=='streetbound.streamed-world'||source.version!==1||
    !Array.isArray(source.roads)||!Array.isArray(source.size))
    throw new TypeError('Expected the baked Morrow Coast streamed-world JSON');
  if(source.roads.length>180)
    throw new RangeError('Current editor supports 180 roads; Morrow has '+source.roads.length+
      '. Do not silently truncate production roads.');
  const [width,height]=source.size;
  const originalRoads=new Map();
  const roads=source.roads.map(road=>{
    const id=Number(road.id),points=road.anchors.map(pos);
    originalRoads.set(id,{points:points.map(p=>({...p})),
      width:Number(road.width),lanes:Number(road.lanes),
      name:road.name,kind:road.kind,surface:road.surface});
    const surface=String(road.surface).toLowerCase();
    return {id:'mc-road-'+id,name:road.name,points,
      roadClass:ROAD_CLASS[road.kind]||'country',
      surface:SURFACES.has(surface)?surface:'asphalt',
      width:Math.max(6,Number(road.width)),lanes:Math.max(1,Number(road.lanes)),
      shoulder:road.kind==='highway'?5:road.kind==='mountain'?2:3,
      smooth:true,markings:road.kind!=='driveway'&&road.kind!=='gravel'};
  });
  const doc=normalizeWorld({format:'gdt.racing-world',version:2,
    name:'Morrow Coast • Road authoring',
    world:{width,height,seed:28114,base:'grass'},roads,
    regions:[],props:[],markers:[],assets:[]});
  return {doc,reference:{roads:originalRoads,width,height,
    sourceName:source.name,count:source.roads.length,
    sourceVersion:source.version},
    warnings:['Morrow Coast road-edit mode: existing scenery, coastline and props remain in the production bake.',
      'This editor exports a road patch, NOT a replacement 7.5 MB streamed-world JSON.',
      'Terrain, scenery and marker changes in this preview are not included in the road patch.']};
}

export function buildMorrowPatch(doc,reference){
  if(!reference?.roads)throw new TypeError('Load the production Morrow Coast world first');
  const existing=new Map();
  const additions=[];
  for(const road of doc.roads){
    const match=/^mc-road-(\d+)$/.exec(road.id);
    if(!match){additions.push(road);continue;}
    const id=Number(match[1]),original=reference.roads.get(id);
    if(!original)throw new Error('Unrecognized Morrow road ID '+road.id);
    if(existing.has(id))throw new Error('Duplicate Morrow road '+road.id);
    existing.set(id,road);
  }
  for(const id of reference.roads.keys()){
    if(!existing.has(id))throw new Error('Production road '+id+' was removed. Restore it or undo; the safe bridge never deletes existing roads.');
  }
  const changes=[];
  for(const [id,road] of existing){
    const before=reference.roads.get(id);
    if(road.points.length<2||road.points.length>100)throw new Error('Road '+id+' has invalid control points');
    if(!same(road.points[0],before.points[0])||
       !same(road.points.at(-1),before.points.at(-1)))
      throw new Error('Road '+road.name+' moved a shared node. Keep its endpoints fixed; reshape interior control points instead.');
    const width=Math.max(6,+road.width);
    const surface=road.surface==='dirt'||road.surface==='gravel'?'GRAVEL':'ASPHALT';
    // Several production classes map to the same editor selector (city).
    // Preserve the original kind unless the user actually changes class.
    const originalClass=ROAD_CLASS[before.kind]||'country';
    const kind=road.roadClass===originalClass?before.kind:(KINDS[road.roadClass]||before.kind);
    const changed=road.points.length!==before.points.length||
      road.points.some((p,i)=>!before.points[i]||!same(p,before.points[i],.01))||
      Math.abs(width-before.width)>.01||road.lanes!==before.lanes||
      surface!==before.surface||kind!==before.kind;
    if(changed)changes.push({road_id:id,name:before.name,
      anchors:road.points.map(vec),width,lanes:road.lanes,surface,kind});
  }
  for(const r of additions){
    if(r.points.length<2||r.points.length>100)throw new Error('A new road has invalid geometry');
    if(r.points.some(p=>p.x<0||p.y<0||p.x>reference.width||p.y>reference.height))
      throw new Error('Added road must remain inside Morrow Coast bounds');
  }
  return {format:'streetbound.morrow-editor-patch',version:1,
    baseline:{road_count:reference.count,world_name:reference.sourceName},
    updated_roads:changes.sort((a,b)=>a.road_id-b.road_id),
    new_roads:additions.map(r=>({name:r.name,
      anchors:r.points.map(vec),kind:KINDS[r.roadClass]||'local',
      width:r.width,lanes:r.lanes,
      surface:r.surface==='dirt'||r.surface==='gravel'?'GRAVEL':'ASPHALT'})),
    notes:'Place at worlds/morrow-coast.editor-patch.json; run tools/build_morrow_coast.py. Only road geometry and traffic data are changed; all production map indexes are rebaked.'};
}
