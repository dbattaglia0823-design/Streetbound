import {
  createWorld,demoWorld,parseWorld,serializeWorld,normalizeWorld,getEntity,
  createEntity,addSpriteAsset,updateEntity,removeEntity,reorderEntity,moveControlPoint,insertControlPoint,
  deleteControlPoint,scatterVegetation
} from './world-model.js';
import {
  roadInsertCandidate,regionInsertCandidate,insertShapePoint,translateEntity,duplicateEntity,
  paintSceneryBrush,eraseSceneryBrush
} from './world-edit-tools.js';
import {distance,clamp,nearestOnPath,pointInPolygon,regionAt,sampleRoad} from './world-geometry.js';
import {drawWorld,drawEditorOverlay} from './world-renderer.js';
import {buildWorldZip,worldSlug} from './world-export.js';
import {buildRoadJunctions} from './world-junctions.js';
import {smartRoadSnap,largeDragDistance} from './world-safe-edit.js';
import {createMapAuditUI} from './world-audit-ui.js';
import {loadMorrowCoast,isMorrowEdit,expandMorrowWorld,morrowEditText,MORROW_EDIT_NAME,
  MORROW_MAX_WIDTH,MORROW_MAX_HEIGHT} from './morrow-coast-bridge.js';
import {buildRuntimePreview,pickRuntimeProp,REPLACEABLE_KINDS,BASE_SIZE,
  GAME_ART,GAME_ART_KINDS} from './morrow-runtime-preview.js';
import {lanePatterns,drawLanePreview} from './traffic-patterns.js';
import {applyEnvironmentPreset} from './world-environment-presets.js';
import {
  placeBesideRoad,placeSiteMarker,nearestRoadPlacement,placementFootprint,
  roadwayClearance,repairRoadsideObjects
} from './world-road-placement.js';

const $=id=>document.getElementById(id);
const viewport=$('viewport'),canvas=$('world-canvas'),ctx=canvas.getContext('2d');
const mini=$('minimap'),miniCtx=mini.getContext('2d');
const AUTO='streetbound.map-editor.autosave.v2',SAVE='streetbound.map-editor.manual.v2';
let doc=demoWorld(),tool='select',selection=null,draft=null,gesture=null,hover=null,pointInsertMode=null;
let zoom=.25,offsetX=0,offsetY=0,panSpace=false,dirty=false,frame=0,autosaveTimer=0;
let liveSession=null,loadedWorldSha='',runtimePreview=null,adoptGameProp=false;
let undoStack=[],redoStack=[];
const laneCache=new WeakMap();
const trafficFor=()=>{let lanes=laneCache.get(doc.roads);if(!lanes){lanes=lanePatterns(doc.roads);laneCache.set(doc.roads,lanes);}return lanes;};
const minZoom=.007,maxZoom=5; // Entire 22k+ worlds still fit on narrow mobile viewports.
const status=message=>{$('status').textContent=message;};
const errorMessage=e=>status(e?.message||'Action failed.');
const worldPoint = (x,y)=>({x:clamp(x,0,doc.world.width),y:clamp(y,0,doc.world.height)});
const screen = event => {
  const rect=canvas.getBoundingClientRect(),sx=event.clientX-rect.left,sy=event.clientY-rect.top;
  return {sx,sy,x:(sx-offsetX)/zoom,y:(sy-offsetY)/zoom};
};
const snapEnd = (p,surface) => {
  if(!$('road-smart-snap').checked)return {point:p,snapped:null};
  const hit=smartRoadSnap(doc,p,surface,{radius:clamp(15/zoom,8,28)});
  return {point:hit?{x:hit.x,y:hit.y}:p,snapped:hit};
};
const currentDisplay = ()=>({
  showTerrain:$('show-terrain').checked,showRoads:$('show-roads').checked,
  junctions:$('show-junctions').checked,
  showScenery:$('show-scenery').checked,showMarkers:$('show-markers').checked
});
function render(){
  const dpr=clamp(window.devicePixelRatio||1,1,2);
  const w=Math.max(1,viewport.clientWidth),h=Math.max(1,viewport.clientHeight);
  if(canvas.width!==Math.round(w*dpr)||canvas.height!==Math.round(h*dpr)){
    canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);
  }
  ctx.setTransform(dpr,0,0,dpr,0,0);
  ctx.fillStyle='#0b151d';ctx.fillRect(0,0,w,h);
  ctx.save();ctx.setTransform(dpr*zoom,0,0,dpr*zoom,dpr*offsetX,dpr*offsetY);
  ctx.beginPath();ctx.rect(0,0,doc.world.width,doc.world.height);ctx.clip();
  const bounds={minX:Math.max(0,-offsetX/zoom),minY:Math.max(0,-offsetY/zoom),
    maxX:Math.min(doc.world.width,(w-offsetX)/zoom),maxY:Math.min(doc.world.height,(h-offsetY)/zoom)};
  drawWorld(ctx,doc,{...currentDisplay(),bounds,quality:zoom<.08?0:1,
    runtimePreview,zoom});
  let roadsidePreview=null;
  if(tool==='prop'&&hover&&!$('scenery-paint').checked&&!$('scenery-erase').checked){
    try{
      const proposed={type:$('prop-type').value,assetId:$('prop-asset').value,
        x:hover.x,y:hover.y,rotation:0,scale:1};
      const placed=placeBesideRoad(doc,proposed);
      roadsidePreview={...placed,radius:placementFootprint(doc,placed)};
    }catch{/* Invalid placements do not render a misleading ghost. */}
  }
  if($('show-traffic').checked)drawLanePreview(ctx,trafficFor(),zoom,bounds);
  drawEditorOverlay(ctx,doc,{selection,hover:draft?hover:null,draft,zoom,roadsidePreview,
    insertMode:pointInsertMode,insertHover:tool==='select'?hover:null,
    brushPreview:tool==='prop'&&($('scenery-paint').checked||$('scenery-erase').checked)&&hover
      ?{position:hover,radius:Number($('brush-radius').value),erase:$('scenery-erase').checked}:null,
    showBoundaries:$('show-boundaries').checked,auditIssues:auditUI.issues});
  ctx.restore();
  ctx.setTransform(dpr,0,0,dpr,0,0);
  ctx.strokeStyle='#f5c29699';ctx.lineWidth=1;ctx.strokeRect(offsetX+.5,offsetY+.5,doc.world.width*zoom,doc.world.height*zoom);
  $('zoom-value').textContent=Math.round(zoom*100)+'%';
  // The minimap is lightweight (no procedural ground texture).
  miniCtx.setTransform(1,0,0,1,0,0);miniCtx.clearRect(0,0,mini.width,mini.height);
  miniCtx.save();
  const scale=Math.min(mini.width/doc.world.width,mini.height/doc.world.height);
  // Detailed scenery is unreadable on a 190px-wide minimap and costly with large worlds.
  // The overview must use the same source-resolution coastline and baked
  // road centerlines as the main canvas. The old simplified-region mini-map
  // showed a different ocean/land boundary from the actual game.
  miniCtx.scale(scale,scale);drawWorld(miniCtx,doc,{...currentDisplay(),
    // A 190px overview needs coastlines and roads, not 19k detailed game props
    // re-rendered on every pan/zoom; this also keeps the editor responsive.
    showScenery:false,
    runtimePreview,quality:0,junctions:false,showMarkers:false});
  miniCtx.restore();
  miniCtx.strokeStyle='#f5c18e';miniCtx.lineWidth=1.7;
  miniCtx.strokeRect(Math.max(0,-offsetX/zoom)*scale,Math.max(0,-offsetY/zoom)*scale,
    Math.min(w/zoom,doc.world.width)*scale,Math.min(h/zoom,doc.world.height)*scale);
}
function requestRender(){
  if(frame)return;
  frame=requestAnimationFrame(()=>{frame=0;render();});
}
function fit(){
  const w=viewport.clientWidth,h=viewport.clientHeight;
  zoom=clamp(Math.min((w-36)/doc.world.width,(h-36)/doc.world.height),minZoom,maxZoom);
  offsetX=(w-doc.world.width*zoom)/2;offsetY=(h-doc.world.height*zoom)/2;
  requestRender();
}
function setZoom(value,sx=viewport.clientWidth/2,sy=viewport.clientHeight/2){
  const next=clamp(value,minZoom,maxZoom),x=(sx-offsetX)/zoom,y=(sy-offsetY)/zoom;
  zoom=next;offsetX=sx-x*zoom;offsetY=sy-y*zoom;requestRender();
}
function focusPoint(p){
  offsetX=viewport.clientWidth/2-p.x*zoom;offsetY=viewport.clientHeight/2-p.y*zoom;requestRender();
}
function refreshHeader(){
  $('world-title').value=doc.name;
  $('save-morrow').hidden=!isMorrowEdit(doc);
  $('morrow-expand-panel').hidden=!isMorrowEdit(doc);
  if(isMorrowEdit(doc)){
    const w=$('expand-world-width'),h=$('expand-world-height');
    w.value=doc.world.width;h.value=doc.world.height;
    w.min=doc.world.width;h.min=doc.world.height;
    w.max=MORROW_MAX_WIDTH;h.max=MORROW_MAX_HEIGHT;
    $('expand-morrow').disabled=
      doc.world.width===MORROW_MAX_WIDTH&&doc.world.height===MORROW_MAX_HEIGHT;
  }
  $('save-morrow').textContent=liveSession?'Save to Game':'Export Morrow edits';
  $('save-world').textContent=isMorrowEdit(doc)&&liveSession?'Save to Game':'Save';
  $('adopt-game-prop').hidden=!runtimePreview;
  $('adopt-game-hint').hidden=!runtimePreview;
  $('game-asset-status').textContent=runtimePreview
    ?'Live project assets: game scenery atlas and parked-traffic PNGs. '+
       runtimePreview.propsCount.toLocaleString()+' baked props displayed; generated props are rebuilt from the source.'
    :'Open Game Map to load the playable scene and the asset atlas from the project folder.';
  $('world-dimensions').textContent=doc.world.width+' × '+doc.world.height+' world units';
  $('object-count').textContent=doc.roads.length+' roads · '+
    buildRoadJunctions(doc.roads).length+' intersections · '+
    doc.regions.length+' regions · '+doc.props.length+' placed scenery'+
    (runtimePreview?' · '+runtimePreview.propsCount.toLocaleString()+' existing game props':'');
  const canFinish=draft && draft.points.length>=(draft.type==='road'?2:3);
  $('finish-shape').disabled=!canFinish;$('cancel-shape').disabled=!draft;
  $('delete-entity').disabled=!selection;
  $('undo-world').disabled=!undoStack.length;$('redo-world').disabled=!redoStack.length;
}
function makeSnapshot(before,label){
  if(before===doc)return;
  undoStack.push(before);if(undoStack.length>35)undoStack.shift();
  redoStack=[];dirty=true;
  auditUI.invalidate();
  clearTimeout(autosaveTimer);
  autosaveTimer=setTimeout(()=>{
    try{localStorage.setItem(AUTO,serializeWorld(doc));}
    catch{status('Autosave unavailable. Export JSON to protect your world.');}
  },650);
  refreshUI();if(label)status(label);
}
function change(edit,label){
  const before=doc;
  try{
    let next=edit(doc);
    if(next.roads!==before.roads){
      const fixed=repairRoadsideObjects(next);
      if(fixed.failed)throw new RangeError('Road change would overlap '+fixed.failed+
        ' placed objects. Try moving them or widening the surrounding area first.');
      next=fixed.doc;
    }
    if(next!==doc){doc=next;makeSnapshot(before,label);}else requestRender();
    return true;
  }catch(e){doc=before;errorMessage(e);return false;}
}
function undo(){
  if(!undoStack.length)return status('No earlier changes.');
  redoStack.push(doc);doc=undoStack.pop();afterHistory('Undid edit.');
}
function redo(){
  if(!redoStack.length)return status('No further changes.');
  undoStack.push(doc);doc=redoStack.pop();afterHistory('Redid edit.');
}
function afterHistory(message){
  if(selection&&!getEntity(doc,selection.id))selection=null;
  dirty=true;auditUI.invalidate();clearTimeout(autosaveTimer);
  autosaveTimer=setTimeout(()=>{try{localStorage.setItem(AUTO,serializeWorld(doc));}catch{status('Autosave unavailable. Export JSON instead.');}},650);
  refreshUI();status(message);
}
function setTool(next){
  if(!['select','road','terrain','prop','marker','pan'].includes(next))return;
  if(draft)cancelDraft(false);
  if(gesture?.mode==='spray')finishSpray(false);
  if(next!=='select')pointInsertMode=null;
  tool=next;
  document.querySelectorAll('[data-tool]').forEach(button=>{
    const on=button.dataset.tool===next;button.classList.toggle('active',on);button.setAttribute('aria-pressed',String(on));
  });
  status({
    select:'Select a road to insert points, drag its control handles, or Alt-drag the entire shape.',
    road:'Click to add road control points. Double-click or Enter to finish; road endpoints snap near existing roads.',
    terrain:'Click around a terrain area. Double-click or Enter to close the polygon.',
    prop:'Click for a single prop, or enable hold-and-drag to paint or erase scenery.',
    marker:'Click to place a gameplay marker.',
    pan:'Drag to move around the open world.'
  }[next]);
  requestRender();
}
function setSelection(id,point=-1){
  if(id!==selection?.id)pointInsertMode=null;
  selection=id?{id,point}:null;
  refreshHeader();refreshInspector();refreshEntities();requestRender();
}
function selectedShape(){
  const found=selection?getEntity(doc,selection.id):null;
  return found&&(found.type==='roads'||found.type==='regions')?found:null;
}
function choosePointInsert(mode){
  const found=selectedShape();
  if(!found){status('Select an existing road or terrain region first.');return;}
  if(mode!=='between'&&found.type!=='roads')return;
  pointInsertMode=pointInsertMode?.id===selection.id&&pointInsertMode?.mode===mode?null:{id:selection.id,mode};
  refreshInspector();requestRender();
  status(pointInsertMode
    ?mode==='between'?'Click directly on the selected curve to insert a point.':'Click anywhere in the world to extend this end of the selected road.'
    :'Point insertion canceled.');
}
function insertSelectedPoint(p,mode='between'){
  const found=selectedShape();if(!found)return false;
  const threshold=clamp(14/zoom,17,75);
  try{
    const result=insertShapePoint(doc,found.item.id,worldPoint(p.x,p.y),{mode,maxDistance:threshold});
    const before=doc;
    let next=result.doc;
    if(found.type==='roads'){
      const fixed=repairRoadsideObjects(next);
      if(fixed.failed)throw new RangeError('Some roadside props cannot be moved clear of this edit.');
      next=fixed.doc;
    }
    doc=next;pointInsertMode=null;makeSnapshot(before,'Added control point '+(result.index+1)+'. Drag it to reshape the '+(found.type==='roads'?'road':'coastline')+'.');
    setSelection(found.item.id,result.index);
    return true;
  }catch(e){errorMessage(e);return false;}
}
function hitTest(p){
  const radius=clamp(12/zoom,9,48);
  if(selection){
    const found=getEntity(doc,selection.id);
    if(found&&['roads','regions'].includes(found.type)){
      for(let i=0;i<found.item.points.length;i++)if(distance(p,found.item.points[i])<radius)
        return {id:selection.id,point:i,kind:'handle'};
    }
  }
  if($('show-markers').checked)
    for(let i=doc.markers.length-1;i>=0;i--)
      if(distance(p,doc.markers[i])<Math.max(18,12/zoom))return {id:doc.markers[i].id,point:-1,kind:'entity'};
  if($('show-scenery').checked)
    for(let i=doc.props.length-1;i>=0;i--)
      if(distance(p,doc.props[i])<Math.max(18*doc.props[i].scale,12/zoom))return {id:doc.props[i].id,point:-1,kind:'entity'};
  if($('show-roads').checked)
    for(let i=doc.roads.length-1;i>=0;i--){
      const road=doc.roads[i],d=nearestOnPath(p,sampleRoad(road.points,road.smooth,12)).distance;
      if(d<Math.max(road.width/2,10/zoom))return {id:road.id,point:-1,kind:'entity'};
    }
  if($('show-terrain').checked)
    for(let i=doc.regions.length-1;i>=0;i--)
      if(pointInPolygon(p,doc.regions[i].points))return {id:doc.regions[i].id,point:-1,kind:'entity'};
  return null;
}
function refreshInspector(){
  const found=selection?getEntity(doc,selection.id):null;
  if(!found){
    $('hide-game-prop').hidden=true;
    $('inspector').hidden=true;$('inspector-empty').hidden=false;
    $('selected-type').textContent='NOTHING SELECTED';return;
  }
  $('hide-game-prop').hidden=!(found.type==='props'&&found.item.replaces);
  if(found.type==='props'&&found.item.replaces)
    $('hide-game-prop').textContent=found.item.hidden?'Restore game scenery':'Hide original from game';
  const {type,item}=found;
  $('inspector').hidden=false;$('inspector-empty').hidden=true;
  $('selected-type').textContent={roads:'ROAD',regions:'TERRAIN',props:'SCENERY',markers:'MARKER'}[type];
  $('inspector-name').value=item.name;
  for(const x of ['road','region','prop','marker'])$('inspect-'+x).hidden=type!=={road:'roads',region:'regions',prop:'props',marker:'markers'}[x];
  const position=type==='props'||type==='markers';$('position-fields').hidden=!position;
  if(position){$('inspect-x').value=Math.round(item.x);$('inspect-y').value=Math.round(item.y);}
  $('point-help').hidden=!(type==='roads'||type==='regions');
  $('remove-point').hidden=!(type==='roads'||type==='regions');
  $('remove-point').disabled=selection.point<0;
  const shape=type==='roads'||type==='regions';
  $('point-coordinate-fields').hidden=!shape||selection.point<0;
  if(shape&&selection.point>=0){
    $('inspect-point-x').value=found.item.points[selection.point].x;
    $('inspect-point-y').value=found.item.points[selection.point].y;
  }
  $('prop-transform-buttons').hidden=type!=='props';
  if(type==='roads'){
    $('road-point-count').textContent=item.points.length+' road points'+(selection.point>=0?' · editing point '+(selection.point+1):'');
    for(const [id,mode] of [['insert-road-point','between'],['extend-road-start','start'],['extend-road-end','end']]){
      const button=$(id);const active=pointInsertMode?.id===item.id&&pointInsertMode.mode===mode;
      button.setAttribute('aria-pressed',String(active));button.classList.toggle('is-active',active);
    }
    $('insert-hint').textContent=pointInsertMode?.id===item.id
      ?(pointInsertMode.mode==='between'?'Click the selected road line to insert a control point.':'Click a new endpoint to extend the road.')
      :'Insert points on the curve, or extend either endpoint. Shift-click a selected road to insert directly.';
    $('inspect-road-class').value=item.roadClass;$('inspect-road-surface').value=item.surface;
    $('inspect-road-width').value=item.width;$('inspect-road-lanes').value=item.lanes;
    $('inspect-road-shoulder').value=item.shoulder;$('inspect-road-smooth').checked=item.smooth;
    $('inspect-road-markings').checked=item.markings;
  }else if(type==='regions'){
    $('inspect-biome').value=item.biome;$('inspect-elevation').value=item.elevation;
  }else if(type==='props'){
    $('inspect-prop-type').value=item.type;$('inspect-asset').value=item.assetId||'';
    $('inspect-scale').value=item.scale;$('inspect-rotation').value=item.rotation;
  }else{
    $('inspect-marker-type').value=item.type;$('inspect-properties').value=JSON.stringify(item.properties,null,2);
  }
}
function refreshEntities(){
  const list=$('entity-list');list.replaceChildren();
  const filter=$('entities-filter').value;
  const sections=filter==='all'?['roads','regions','markers','props']:[filter];
  let entries=sections.flatMap(type=>doc[type].map(item=>({type,item})));
  $('entities-count').textContent=entries.length+' TOTAL';
  if(entries.length>180){
    const selected=entries.find(entry=>entry.item.id===selection?.id);
    entries=entries.slice(0,179);
    if(selected&&!entries.some(e=>e.item.id===selected.item.id))entries.push(selected);
  }
  if(!entries.length){const p=document.createElement('p');p.className='muted-copy';p.textContent='Nothing in this category yet.';list.append(p);}
  for(const {type,item} of entries){
    const row=document.createElement('button');row.type='button';row.className='entity-row'+(selection?.id===item.id?' selected':'');
    row.setAttribute('aria-pressed',String(selection?.id===item.id));row.title=item.name;
    const ico=document.createElement('span');ico.className='icon';
    ico.textContent={roads:'〰',regions:'⬡',props:'♣',markers:'◇'}[type];
    const name=document.createElement('span');name.className='entity-name';name.textContent=item.name;
    const tag=document.createElement('span');tag.className='entity-type';tag.textContent={roads:'ROAD',regions:'LAND',props:'PROP',markers:'POINT'}[type];
    row.append(ico,name,tag);
    row.addEventListener('click',()=>{
      setTool('select');setSelection(item.id);
      if(type==='props'||type==='markers')focusPoint(item);
      else focusPoint(item.points.reduce((p,q)=>({x:p.x+q.x/item.points.length,y:p.y+q.y/item.points.length}),{x:0,y:0}));
    });
    list.append(row);
  }
  if((filter==='all'?doc.roads.length+doc.regions.length+doc.props.length+doc.markers.length:doc[filter].length)>entries.length){
    const p=document.createElement('p');p.className='muted-copy';p.textContent='Showing the first 180 items. Filter by category to find more.';list.append(p);
  }
}
function refreshSpriteLists(){
  for(const id of ['prop-asset','inspect-asset']){
    const select=$(id),previous=select.value;
    const current=selection?getEntity(doc,selection.id):null;
    const type=id==='inspect-asset'&&current?.type==='props'
      ?current.item.type:$('prop-type').value;
    select.replaceChildren();
    select.append(new Option('Automatic game illustration',''));
    if(runtimePreview){
      for(const [assetId,name] of GAME_ART){
        if((GAME_ART_KINDS[type]||[]).includes(assetId.slice(5)))
          select.append(new Option('Game folder · '+name,assetId));
      }
    }
    for(const asset of doc.assets||[])select.append(new Option(asset.name,asset.id));
    select.value=[...select.options].some(option=>option.value===previous)?previous:'';
  }
}
function refreshUI(){refreshSpriteLists();refreshHeader();refreshInspector();refreshEntities();requestRender();}
function startWorld(world,message,{skipRecovery=false}={}){
  clearTimeout(autosaveTimer);
  if(gesture?.mode==='spray')clearInterval(gesture.timer);
  if(dirty&&!skipRecovery)auditUI.stash(doc);
  doc=normalizeWorld(world);selection=null;pointInsertMode=null;draft=null;gesture=null;
  runtimePreview=null;loadedWorldSha='';adoptGameProp=false;
  undoStack=[];redoStack=[];dirty=false;
  auditUI.invalidate();refreshUI();fit();status(message);
  try{localStorage.setItem(AUTO,serializeWorld(doc));}
  catch{status('Autosave unavailable. Export JSON for a backup.');}
}
function cancelDraft(notify=true){
  draft=null;refreshHeader();requestRender();
  if(notify)status('Unfinished shape discarded.');
}
function finishDraft(){
  if(!draft)return;
  const work=draft;
  if(work.points.length<(work.type==='road'?2:3)){status('Add more points before finishing.');return;}
  try{
    let applied=false;
    if(work.type==='road'){
      const roadClass=$('road-class').value,surface=$('road-surface').value;
      const width=Number($('road-width').value),lanes=Number($('road-lanes').value);
      const shoulder=Number($('road-shoulder').value);
      applied=change(d=>createEntity(d,'roads',{name:roadClass[0].toUpperCase()+roadClass.slice(1)+' road',roadClass,surface,
        width,lanes,shoulder,smooth:$('road-smooth').checked,markings:$('road-markings').checked,points:work.points}),'Curved road added. Select it to refine the control points.');
    }else{
      const biome=$('biome').value,elevation=Number($('elevation').value);
      applied=change(d=>createEntity(d,'regions',{name:biome[0].toUpperCase()+biome.slice(1)+' region',biome,elevation,points:work.points}),'Terrain area added. Select its boundary to reshape the area.');
    }
    if(applied){draft=null;refreshHeader();requestRender();}
  }catch(e){errorMessage(e);}
}
function addDraftPoint(p,detail){
  const point=worldPoint(p.x,p.y);
  if(detail>=2&&draft){finishDraft();return;}
  const snap=tool==='road'?snapEnd(point,$('road-surface').value):null;
  const where=snap?snap.point:point;
  if(!draft)draft={type:tool,width:Number($('road-width').value),points:[]};
  if(draft.points.length && distance(draft.points.at(-1),where)<1) return;
  draft.points.push(where);
  hover=null;
  refreshHeader();requestRender();
  status((snap?.snapped?'Connected to '+snap.snapped.roadName+' ('+snap.snapped.kind+'). ':'')+
    draft.points.length+' control points · Enter to finish · Esc to cancel');
}
/** Paint or erase with continuous sampling while the pointer is held.
 * A full press/drag is committed once on pointerup, not on each spray tick.
 */
function brushSettings(){
  return {type:$('prop-type').value,assetId:$('prop-asset').value,
    radius:Number($('brush-radius').value),spacing:Number($('brush-spacing').value),
    count:Number($('brush-density').value),variation:$('brush-variation').checked,
    avoidRoads:$('brush-avoid-roads').checked,avoidWater:$('brush-avoid-water').checked};
}
function sprayAt(position){
  if(gesture?.mode!=='spray'||!position)return;
  const before=doc,settings=brushSettings();
  try{
    doc=gesture.erase?eraseSceneryBrush(doc,position,settings.radius):paintSceneryBrush(doc,position,settings);
    if(doc!==before){gesture.changed=true;gesture.lastCount=doc.props.length;requestRender();}
    if(doc.props.length>=4000&&!gesture.erase)status('Scenery limit reached (4,000 objects).');
  }catch(e){errorMessage(e);finishSpray(true);}
}
function beginSpray(event,p){
  const settings=brushSettings();
  if(!Number.isFinite(settings.radius)||settings.radius<8||settings.radius>250||
     !Number.isFinite(settings.spacing)||settings.spacing<5||settings.spacing>200){
    status('Brush radius must be 8–250 and spacing must be 5–200.');return;
  }
  gesture={mode:'spray',before:doc,last:worldPoint(p.x,p.y),erase:$('scenery-erase').checked,changed:false,
    lastCount:doc.props.length,pointerId:event.pointerId,timer:null};
  canvas.setPointerCapture(event.pointerId);
  sprayAt(gesture.last);
  if(gesture?.mode!=='spray')return;
  gesture.timer=setInterval(()=>{if(gesture?.mode==='spray')sprayAt(gesture.last);},110);
  status(gesture.erase?'Hold and drag to remove scenery.':'Hold and drag to scatter scenery.');
}
function continueSpray(p){
  if(gesture?.mode!=='spray')return;
  if(p.x<0||p.y<0||p.x>doc.world.width||p.y>doc.world.height){
    gesture.last=null;return;
  }
  const to=worldPoint(p.x,p.y);
  const from=gesture.last;
  const radius=Number($('brush-radius').value);
  if(from){
    const steps=Math.min(35,Math.ceil(distance(from,to)/Math.max(8,radius*.65)));
    for(let i=1;i<=steps;i++)sprayAt({x:from.x+(to.x-from.x)*i/steps,y:from.y+(to.y-from.y)*i/steps});
  }else sprayAt(to);
  if(gesture?.mode==='spray')gesture.last=to;
}
function finishSpray(cancel=false){
  if(gesture?.mode!=='spray')return;
  const current=gesture;clearInterval(current.timer);gesture=null;
  if(cancel){doc=current.before;refreshUI();status('Scenery stroke canceled.');return;}
  if(current.changed){
    makeSnapshot(current.before,(current.erase?'Erased ':'Painted ')+Math.abs(doc.props.length-current.before.props.length)+' scenery objects. One undo step.');
  }else{requestRender();status('No scenery changed. Try a smaller spacing or different location.');}
}
canvas.addEventListener('contextmenu',event=>{event.preventDefault();if(draft)finishDraft();});
canvas.addEventListener('pointerdown',event=>{
  if(![0,1,2].includes(event.button))return;
  event.preventDefault();
  const p=screen(event);
  if(event.button===2){if(draft)finishDraft();return;}
  if(event.button===1||panSpace||tool==='pan'){
    gesture={mode:'pan',sx:p.sx,sy:p.sy,startX:offsetX,startY:offsetY};canvas.setPointerCapture(event.pointerId);return;
  }
  if(p.x<0||p.y<0||p.x>doc.world.width||p.y>doc.world.height)return;
  canvas.focus({preventScroll:true});
  if(tool==='road'||tool==='terrain'){addDraftPoint(p,event.detail);return;}
  if(tool==='prop'){
    if($('scenery-paint').checked||$('scenery-erase').checked){beginSpray(event,p);return;}
    const type=$('prop-type').value;
    const before=doc;
    if(change(d=>createEntity(d,'props',{type,name:type.replace(/_/g,' '),x:p.x,y:p.y,scale:1,rotation:0,assetId:$('prop-asset').value}),
      'Placed '+type.replace(/_/g,' ')+' beside the nearest road (if nearby).')&&doc!==before)
      setSelection(doc.props.at(-1)?.id);
    return;
  }
  if(tool==='marker'){
    const type=$('marker-type').value;
    const before=doc;
    if(change(d=>createEntity(d,'markers',{type,name:type.replace(/_/g,' '),x:p.x,y:p.y,rotation:0,properties:{}}),
      'Placed '+type.replace(/_/g,' ')+'.')&&doc!==before)
      setSelection(doc.markers.at(-1)?.id);
    return;
  }
  if(tool==='select'){
    if(runtimePreview&&(adoptGameProp||event.ctrlKey)){
      const source=pickRuntimeProp(runtimePreview,doc,p,clamp(12/zoom,12,48));
      if(!source){
        status('No editable baked tree, rock or building at that point. Zoom in and click another.');
        return;
      }
      const type=REPLACEABLE_KINDS[source.kind],size=BASE_SIZE[type];
      const scale=clamp(Number(source.size[0])/size[0],.25,2.5);
      const same=(item)=>item.replaces&&item.replaces.kind===source.kind&&
        item.replaces.seed===source.seed&&
        Math.hypot(item.replaces.p[0]-source.p[0],item.replaces.p[1]-source.p[1])<.03;
      if(doc.props.some(same))return status('That game object is already editable.');
      const id='prop-'+(Math.max(0,...doc.props.map(item=>
        /^prop-(\\d+)$/.test(item.id)?Number(item.id.slice(5)):0))+1);
      const next={id,type,name:'Game '+source.kind.replaceAll('_',' '),
        x:Number(source.p[0]),y:Number(source.p[1]),rotation:Number(source.angle)*180/Math.PI,
        scale,assetId:source.kind==='coastal_house'?'game-coastal_house':'',
        replaces:{kind:String(source.kind),seed:Number(source.seed)||0,
          p:[Number(source.p[0]),Number(source.p[1])]},hidden:false};
      if(change(d=>normalizeWorld({...d,props:[...d.props,next]}),
        'Existing game scenery is now editable. Move, resize or hide it, then Apply to Game.')){
        adoptGameProp=false;$('adopt-game-prop').classList.remove('active');
        setSelection(id);
      }
      return;
    }
    const current=selectedShape();
    if(pointInsertMode?.id===selection?.id&&current){
      insertSelectedPoint(p,pointInsertMode.mode);return;
    }
    if(event.shiftKey&&current){
      insertSelectedPoint(p,'between');return;
    }
    if(event.altKey&&current){
      const hit=hitTest(p);
      if(hit?.id===selection.id){
        gesture={mode:'shape',before:doc,id:selection.id,start:p};
        canvas.setPointerCapture(event.pointerId);
        return;
      }
    }
    // Double-click an existing road/poly edge to insert a new handle.
    if(event.detail>=2 && selection){
      const found=getEntity(doc,selection.id);
      if(found&&['roads','regions'].includes(found.type)){
        const near=found.type==='roads'?roadInsertCandidate(found.item,p):regionInsertCandidate(found.item,p);
        if(near?.distance<clamp(14/zoom,17,75)){
          insertSelectedPoint(p,'between');return;
        }
      }
    }
    const hit=hitTest(p);
    setSelection(hit?.id||null,hit?.point??-1);
    if(!hit)return;
    const found=getEntity(doc,hit.id);
    if(hit.kind==='handle'){
      gesture={mode:'control',before:doc,id:hit.id,index:hit.point};
      canvas.setPointerCapture(event.pointerId);
    }else if(found&&['props','markers'].includes(found.type)){
      gesture={mode:'entity',before:doc,id:hit.id,start:p,x:found.item.x,y:found.item.y};
      canvas.setPointerCapture(event.pointerId);
    }
  }
});
canvas.addEventListener('pointermove',event=>{
  const p=screen(event);
  hover=(p.x>=0&&p.y>=0&&p.x<=doc.world.width&&p.y<=doc.world.height)?worldPoint(p.x,p.y):null;
  $('coordinates').textContent=hover?'x '+Math.round(hover.x)+' / y '+Math.round(hover.y):'Outside world';
  if(gesture){
    if(gesture.mode==='spray'){continueSpray(p);}
    else if(gesture.mode==='pan'){offsetX=gesture.startX+p.sx-gesture.sx;offsetY=gesture.startY+p.sy-gesture.sy;}
    else if(gesture.mode==='control'){
      try{doc=moveControlPoint(doc,gesture.id,gesture.index,worldPoint(p.x,p.y));}
      catch(e){errorMessage(e);}
    }else if(gesture.mode==='shape'){
      try{doc=translateEntity(gesture.before,gesture.id,p.x-gesture.start.x,p.y-gesture.start.y);}
      catch(e){errorMessage(e);}
    }else if(gesture.mode==='entity'){
      try{
        doc=updateEntity(doc,gesture.id,{x:clamp(gesture.x+(p.x-gesture.start.x),0,doc.world.width),
          y:clamp(gesture.y+(p.y-gesture.start.y),0,doc.world.height)});
      }catch(e){errorMessage(e);}
    }
  }
  requestRender();
});
function pointerEnd(event,wasCancelled=false){
  if(!gesture)return;
  if(gesture.mode==='spray'){
    const pointerId=gesture.pointerId;
    finishSpray(wasCancelled);
    if(canvas.hasPointerCapture(pointerId))canvas.releasePointerCapture(pointerId);
    return;
  }
  const current=gesture;gesture=null;
  if(wasCancelled && current.before){doc=current.before;refreshUI();}
  else if(current.before && current.before!==doc){
    try{
      if(doc.roads!==current.before.roads){
        const jump=largeDragDistance(current.before,doc,current.id);
        if(jump>350&&!window.confirm(
          'This road moved '+Math.round(jump)+' world units. It may create unintended intersections. Keep the change?'))
          throw new RangeError('Large road move canceled; previous road geometry restored.');
        const fixed=repairRoadsideObjects(doc);
        if(fixed.failed)throw new RangeError('Road edit would overlap '+fixed.failed+
          ' existing object(s). Try another curve or clear the area first.');
        doc=fixed.doc;
      }
      makeSnapshot(current.before,'Moved '+(current.mode==='control'?'control point':
        current.mode==='shape'?'entire shape':'object')+' and updated roadside clearance.');
    }catch(e){doc=current.before;refreshUI();errorMessage(e);}
  }
  else requestRender();
  if(canvas.hasPointerCapture(event.pointerId))canvas.releasePointerCapture(event.pointerId);
}
canvas.addEventListener('pointerup',event=>pointerEnd(event));
canvas.addEventListener('pointercancel',event=>pointerEnd(event,true));
canvas.addEventListener('pointerleave',()=>{if(!gesture){hover=null;requestRender();}});
viewport.addEventListener('wheel',event=>{
  event.preventDefault();const rect=canvas.getBoundingClientRect();
  setZoom(zoom*(event.deltaY<0?1.12:.89),event.clientX-rect.left,event.clientY-rect.top);
},{passive:false});
mini.addEventListener('pointerdown',event=>{
  const rect=mini.getBoundingClientRect(),x=(event.clientX-rect.left)/rect.width*doc.world.width,
    y=(event.clientY-rect.top)/rect.height*doc.world.height;
  focusPoint({x,y});
});
document.addEventListener('keydown',event=>{
  const target=event.target;
  const typing=target instanceof HTMLElement&&(['INPUT','TEXTAREA','SELECT'].includes(target.tagName)||target.isContentEditable);
  if(typing)return;
  if(event.code==='Space'){event.preventDefault();panSpace=true;return;}
  if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='z'){event.preventDefault();event.shiftKey?redo():undo();return;}
  if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='y'){event.preventDefault();redo();return;}
  if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='d'&&selection){
    event.preventDefault();duplicateSelected();return;
  }
  if(event.ctrlKey||event.metaKey||event.altKey)return;
  if(event.key==='Escape'&&gesture?.mode==='spray'){finishSpray(true);return;}
  if(event.key==='Escape'&&pointInsertMode){pointInsertMode=null;refreshInspector();requestRender();status('Point insertion canceled.');return;}
  if(event.key==='Escape'&&draft){cancelDraft();return;}
  if(event.key==='Enter'&&draft){event.preventDefault();finishDraft();return;}
  if(event.key==='Delete'&&selection){event.preventDefault();deleteSelected();return;}
  if(event.key==='+'||event.key==='='){setZoom(zoom*1.2);return;}
  if(event.key==='-'){setZoom(zoom/1.2);return;}
  const tools={v:'select',r:'road',t:'terrain',p:'prop',m:'marker',h:'pan'};
  const next=tools[event.key.toLowerCase()];
  if(next){event.preventDefault();setTool(next);}
});
document.addEventListener('keyup',event=>{if(event.code==='Space')panSpace=false;});
window.addEventListener('blur',()=>{panSpace=false;if(gesture?.mode==='spray')finishSpray();});
document.querySelectorAll('[data-tool]').forEach(button=>button.addEventListener('click',()=>setTool(button.dataset.tool)));
$('finish-shape').addEventListener('click',finishDraft);$('cancel-shape').addEventListener('click',()=>cancelDraft());
$('undo-world').addEventListener('click',undo);$('redo-world').addEventListener('click',redo);
$('zoom-in').addEventListener('click',()=>setZoom(zoom*1.3));
$('zoom-out').addEventListener('click',()=>setZoom(zoom/1.3));
$('fit').addEventListener('click',fit);
for(const [id,mode] of [['insert-road-point','between'],['extend-road-start','start'],['extend-road-end','end']])
  $(id).addEventListener('click',()=>choosePointInsert(mode));
for(const [id,axis] of [['inspect-point-x','x'],['inspect-point-y','y']]){
  $(id).addEventListener('change',event=>{
    const found=selectedShape();if(!found||selection.point<0)return;
    const numeric=Number(event.target.value);
    if(!Number.isFinite(numeric)||numeric<0||numeric>(axis==='x'?doc.world.width:doc.world.height)){
      errorMessage(new RangeError('Point coordinate is outside the world'));refreshInspector();return;
    }
    const original=found.item.points[selection.point];
    if(!change(d=>moveControlPoint(d,found.item.id,selection.point,{...original,[axis]:numeric}),
      'Changed point '+(selection.point+1)+' '+axis.toUpperCase()+'.'))refreshInspector();
  });
}
function duplicateSelected(){
  if(!selection)return;
  try{
    const previous=doc;
    const copy=duplicateEntity(doc,selection.id);
    doc=copy.doc;pointInsertMode=null;
    makeSnapshot(previous,'Duplicated selected object.');
    setSelection(copy.id);
  }catch(e){errorMessage(e);}
}
$('duplicate-entity').addEventListener('click',duplicateSelected);
for(const button of document.querySelectorAll('[data-nudge]')){
  button.addEventListener('click',()=>{
    if(!selection)return;
    const step=Number($('nudge-step').value);
    if(!Number.isFinite(step)||step<1||step>500){status('Move step must be 1–500.');return;}
    const [x,y]=button.dataset.nudge.split(',').map(Number);
    change(d=>translateEntity(d,selection.id,x*step,y*step),'Moved selected object.');
  });
}
for(const [id,changeBy] of [['rotate-prop-left',-15],['rotate-prop-right',15]]){
  $(id).addEventListener('click',()=>{
    const found=selection?getEntity(doc,selection.id):null;if(found?.type!=='props')return;
    const next=(((found.item.rotation+changeBy+180)%360+360)%360)-180;
    change(d=>updateEntity(d,selection.id,{rotation:next}),'Rotated scenery.');
  });
}
for(const [id,changeBy] of [['scale-prop-down',-.1],['scale-prop-up',.1]]){
  $(id).addEventListener('click',()=>{
    const found=selection?getEntity(doc,selection.id):null;if(found?.type!=='props')return;
    const next=Math.round(clamp(found.item.scale+changeBy,.25,5)*100)/100;
    change(d=>updateEntity(d,selection.id,{scale:next}),'Resized scenery.');
  });
}
function deleteSelected(){
  if(!selection)return;
  const found=getEntity(doc,selection.id);
  if(!found)return setSelection(null);
  const id=selection.id,index=selection.point;
  if(index>=0&&['roads','regions'].includes(found.type)){
    change(d=>deleteControlPoint(d,id,index),'Removed one control point.');
    if(getEntity(doc,id))setSelection(id,-1);
  }else{change(d=>removeEntity(d,id),'Removed '+found.item.name+'.');setSelection(null);}
}
$('delete-entity').addEventListener('click',()=>{if(selection){const id=selection.id;change(d=>removeEntity(d,id),'Entity removed.');setSelection(null);}});
$('remove-point').addEventListener('click',()=>{
  if(!selection||selection.point<0)return;
  change(d=>deleteControlPoint(d,selection.id,selection.point),'Removed control point.');
  setSelection(selection.id,-1);
});
$('move-forward').addEventListener('click',()=>{if(selection)change(d=>reorderEntity(d,selection.id,1),'Changed draw order.');});
$('move-backward').addEventListener('click',()=>{if(selection)change(d=>reorderEntity(d,selection.id,-1),'Changed draw order.');});
$('scenery-erase').addEventListener('change',event=>{
  if(event.target.checked)$('scenery-paint').checked=true;
  if(event.target.checked)setTool('prop');
  requestRender();
});
$('scenery-paint').addEventListener('change',event=>{
  if(!event.target.checked)$('scenery-erase').checked=false;
  requestRender();
});
for(const id of ['brush-radius','brush-spacing','brush-density','brush-variation','brush-avoid-roads','brush-avoid-water'])
  $(id).addEventListener('input',requestRender);
$('snap-selected-roadside').addEventListener('click',()=>{
  const found=selection?getEntity(doc,selection.id):null;
  if(!found||!['props','markers'].includes(found.type))
    return status('Select a building, scenery object or service marker first.');
  try{
    if(found.type==='markers'&&!['garage','dealership','fuel','mission','fast_travel','player_spawn'].includes(found.item.type))
      return status('Race starts, checkpoints, finishes and traffic spawns intentionally remain on their road paths.');
    const before=doc;
    if(found.type==='props'){
      const placed=placeBesideRoad(doc,found.item,{snap:true,align:true,maxSnapDistance:1500});
      doc=updateEntity(doc,selection.id,{x:placed.x,y:placed.y,rotation:placed.rotation});
    }else{
      const placed=placeSiteMarker(doc,found.item);
      doc=updateEntity(doc,selection.id,{x:placed.x,y:placed.y,rotation:placed.rotation});
    }
    if(before!==doc)makeSnapshot(before,'Aligned selected object to local road curve and cleared the shoulder.');
    $('roadside-status').textContent='Selected object checked against nearby roads.';
  }catch(e){errorMessage(e);}
});
$('repair-roadside').addEventListener('click',()=>{
  const result=repairRoadsideObjects(doc,{alignAll:true});
  if(result.doc!==doc){
    const before=doc;doc=result.doc;
    makeSnapshot(before,'Aligned '+(result.moved+result.rotated+result.adjustedMarkers)+
      ' objects. Road shoulders are clear.');
  }
  $('roadside-status').textContent='Moved '+result.moved+' scenery, rotated '+result.rotated+
    ', adjusted '+result.adjustedMarkers+' site markers'+(result.failed?'; '+result.failed+' need manual relocation.':'.');
});
$('environment-preset').addEventListener('change',()=>{
  $('parking-generator-controls').hidden=$('environment-preset').value!=='parking';
});
$('parking-generator-controls').hidden=$('environment-preset').value!=='parking';
$('apply-environment-preset').addEventListener('click',()=>{
  const preset=$('environment-preset').value;
  const entity=selection?getEntity(doc,selection.id):null;
  // Use selected entity when possible; otherwise the visible canvas center.
  const focused=entity?.item;
  const selectedPoint=focused?.points?.[Math.floor(focused.points.length/2)];
  const anchor=selectedPoint || (focused&&Number.isFinite(focused.x)?
    {x:focused.x,y:focused.y}:
    worldPoint((viewport.clientWidth*.5-offsetX)/zoom,
      (viewport.clientHeight*.5-offsetY)/zoom));
  let result=null;
  const succeeded=change(d=>{
    result=applyEnvironmentPreset(d,{preset,anchor,
      selectedId:selection?.id||null,density:Number($('environment-density').value),
      parkingSize:Number($('parking-size').value),
      stallWidth:Number($('parking-stall-width').value),
      occupancy:Number($('parking-occupancy').value),
      entranceWidth:Number($('parking-entrance').value)});
    return result.doc;
  },'Environment preset created. Undo removes the entire preset.');
  if(succeeded&&result){
    const summary=result.count+' objects'+
      (result.roadsAdded?' and '+result.roadsAdded+' road access':'')+
      (result.regionsUpdated?' with updated biome':'')+
      (result.stallCapacity?' · '+result.stallCapacity+' marked stalls':'');
    $('environment-preset-status').textContent='Added '+summary+
      '. Inspect and run Map health before exporting.';
    status('Placed '+summary+'. All scenery clearances are checked.');
  }else{
    $('environment-preset-status').textContent=$('status').textContent;
  }
});
$('scatter').addEventListener('click',()=>{
  const id=selection?.id,region=doc.regions.find(r=>r.id===id);
  if(!region){status('Select a terrain region before scattering scenery.');return;}
  change(d=>scatterVegetation(d,id,Number($('scatter-count').value)),'Scattered vegetation while avoiding roads.');
});
$('road-shoulder').addEventListener('input',e=>{$('shoulder-label').textContent=e.target.value+' m';});
for(const id of ['show-roads','show-junctions','show-terrain','show-scenery','show-markers','show-boundaries','audit-show-overlay','show-traffic'])
  $(id).addEventListener('change',requestRender);
$('entities-filter').addEventListener('change',refreshEntities);
const fields={
  'inspector-name':{name:'name'},
  'inspect-road-class':{roadClass:'string'},'inspect-road-surface':{surface:'string'},
  'inspect-road-width':{width:'number'},'inspect-road-lanes':{lanes:'number'},
  'inspect-road-shoulder':{shoulder:'number'},'inspect-road-smooth':{smooth:'boolean'},
  'inspect-road-markings':{markings:'boolean'},'inspect-biome':{biome:'string'},
  'inspect-elevation':{elevation:'number'},'inspect-prop-type':{type:'string'},'inspect-asset':{assetId:'string'},
  'inspect-scale':{scale:'number'},'inspect-rotation':{rotation:'number'},
  'inspect-marker-type':{type:'string'},'inspect-x':{x:'number'},'inspect-y':{y:'number'},
  'inspect-properties':{properties:'json'}
};
for(const [elementId,options] of Object.entries(fields)){
  $(elementId).addEventListener('change',event=>{
    if(!selection)return;
    const [key,kind]=Object.entries(options)[0];let value;
    try{
      if(kind==='number')value=Number(event.target.value);
      else if(kind==='boolean')value=event.target.checked;
      else if(kind==='json')value=JSON.parse(event.target.value);
      else value=event.target.value;
      change(d=>updateEntity(d,selection.id,{[key]:value}),'Updated '+key+'.');
    }catch(e){errorMessage(e);refreshInspector();}
  });
}
$('world-title').addEventListener('change',e=>change(d=>normalizeWorld({...d,name:e.target.value}),'World renamed.'));
$('new-world').addEventListener('click',()=>$('new-dialog').showModal());
$('cancel-new').addEventListener('click',()=>$('new-dialog').close());
$('create-demo').addEventListener('click',()=>{
  startWorld(demoWorld(),'Loaded the Coastal Ridge example world.');$('new-dialog').close();
});
function loadAtlasCoast(){
  if(dirty&&!window.confirm('Replace unsaved edits with the coastal sample? Export JSON first.'))return;
  startWorld(demoWorld(),'Coastal starter loaded. Edits remain local until you export JSON.');
  if($('new-dialog').open)$('new-dialog').close();
}
$('load-atlas').addEventListener('click',loadAtlasCoast);
$('adopt-game-prop').addEventListener('click',()=>{
  if(!runtimePreview)return status('Open Game Map first.');
  setTool('select');
  adoptGameProp=!adoptGameProp;
  $('adopt-game-prop').classList.toggle('active',adoptGameProp);
  status(adoptGameProp?'Click existing scenery to edit that object in the game.':
    'Game scenery selection canceled.');
});
$('hide-game-prop').addEventListener('click',()=>{
  const found=selection?getEntity(doc,selection.id):null;
  if(found?.type!=='props'||!found.item.replaces)return;
  change(d=>updateEntity(d,selection.id,{hidden:!found.item.hidden}),
    found.item.hidden?'Restored original game scenery.':'Hidden game scenery. Apply to Game to remove it from the playable world.');
});
async function detectProjectMode(){
  try{
    const response=await fetch('/api/editor-status',{cache:'no-store'});
    if(!response.ok)return null;
    const data=await response.json();
    if(data.live===true&&typeof data.token==='string'&&/^[a-f0-9]{64}$/.test(data.worldSha))
      return data;
  }catch{/* Hosted/static mode cannot write project files. */}
  return null;
}
async function openGameMap({skipConfirm=false}={}){
  const button=$('load-morrow');
  if(!skipConfirm&&dirty&&!window.confirm(
    'Reload current playable Morrow Coast? Keep unsaved edits with Export JSON first.'))return;
  button.disabled=true;
  status('Loading actual Morrow Coast, current game scenery and installed artwork...');
  try{
    const session=await detectProjectMode();
    const {doc:world,stats,raw}=await loadMorrowCoast();
    // Hidden adopted props are intentionally absent from the baked world;
    // preserve their authoring records from the last applied source overlay.
    if(session?.overlayExists){
      try{
        const response=await fetch('/api/morrow-edits',{cache:'no-store'});
        if(response.ok){
          const overlay=normalizeWorld(await response.json());
          if(overlay.name===world.name){
            const seen=new Set(world.props.map(p=>p.id));
            for(const item of overlay.props)
              if(item.replaces?.kind&&item.hidden&&!seen.has(item.id))
                world.props.push(item);
          }
        }
      }catch{/* Baked scene still loads if editable overlay is unavailable. */}
    }
    startWorld(world,'Loaded current playable Morrow Coast: '+stats.roads+' roads, '+
      stats.regions+' regions, '+stats.landmarkMarkers+' landmarks and '+
      stats.proceduralProps.toLocaleString()+' existing baked scenery objects.');
    runtimePreview=buildRuntimePreview(raw);
    liveSession=session;
    loadedWorldSha=session?.worldSha||'';
    $('show-traffic').checked=true;
    $('show-scenery').checked=true;
    refreshUI();
    status(session?'Live project connected. Save to Game writes and rebuilds the playable world. Restart the game after saving.':
      'Current map imported. Direct write requires Start Map Editor.cmd with Python 3.');
  }catch(e){errorMessage(e);}
  finally{button.disabled=false;}
}
$('load-morrow').addEventListener('click',()=>openGameMap());
$('expand-morrow').addEventListener('click',()=>{
  if(!isMorrowEdit(doc))return status('Open Game Map first.');
  const width=Number($('expand-world-width').value);
  const height=Number($('expand-world-height').value);
  const old=doc;
  if(width===old.world.width&&height===old.world.height)
    return status('Increase width or height to add space.');
  if(change(d=>expandMorrowWorld(d,{width,height}),
      'Expanded the map boundary. All original roads, terrain, landmarks and objects retain their exact coordinates.')){
    $('morrow-expand-status').textContent=
      'Current map '+width+' × '+height+' m · +'+(width-old.world.width)+
      ' m east, +'+(height-old.world.height)+
      ' m south. Click Apply to Game to rebuild the playable world.';
    fit();
  }
});
$('save-morrow').addEventListener('click',async()=>{
  const button=$('save-morrow');
  if(!isMorrowEdit(doc))return status('Open Game Map first.');
  button.disabled=true;
  try{
    const content=morrowEditText(doc);
    if(liveSession&&loadedWorldSha){
      // Only the explicitly started loopback project server exposes this API.
      // It backs up the current world, validates inputs, invokes the real
      // Python baker and rolls back on failure. Nothing is silently written
      // while editing; this click is the user's apply action.
      status('Validating and rebuilding playable Morrow Coast...');
      const response=await fetch('/api/apply-morrow',{
        method:'POST',headers:{'Content-Type':'application/json',
          'X-Streetbound-Editor-Token':liveSession.token},
        body:JSON.stringify({world:doc,worldSha:loadedWorldSha})
      });
      const result=await response.json();
      if(!response.ok||!result.ok)
        throw new Error(result.error||'The map rebuild failed; project files were restored.');
      // The rebuild is complete before the world is reloaded, and the
      // revision is refreshed to avoid a second-save conflict.
      await openGameMap({skipConfirm:true});
      status('Applied directly to worlds/morrow-coast.world.json. '+
        'Rebuilt '+(result.stats?.roads||0)+' roads and '+
        (result.stats?.props||0).toLocaleString()+' scenery items. Restart the game to load changes.');
    }else if(typeof window.showSaveFilePicker==='function'){
      const handle=await window.showSaveFilePicker({suggestedName:MORROW_EDIT_NAME,
        types:[{description:'Morrow Coast source overlay',accept:{'application/json':['.json']}}]});
      const writer=await handle.createWritable();await writer.write(content);await writer.close();
      status('Saved source overlay. To update the game, put it in map-editor/maps/ '+
        'and run tools/Rebuild Morrow Coast.cmd, or start the live project server.');
    }else{
      download(content,MORROW_EDIT_NAME,'application/json');
      status('Exported edit overlay. Start the local Map Editor to apply directly to the game.');
    }
  }catch(e){if(e?.name!=='AbortError')errorMessage(e);}
  finally{button.disabled=false;}
});

$('create-atlas').addEventListener('click',loadAtlasCoast);
$('confirm-new').addEventListener('click',()=>{
  try{
    const next=createWorld({name:$('new-name').value,width:Number($('new-width').value),
      height:Number($('new-height').value),base:$('new-base').value});
    startWorld(next,'Created a blank continuous world.');$('new-dialog').close();
  }catch(e){errorMessage(e);}
});
function download(content,filename,mime){
  const blob=content instanceof Blob?content:new Blob([content],{type:mime});
  const url=URL.createObjectURL(blob),a=document.createElement('a');
  a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();
  setTimeout(()=>URL.revokeObjectURL(url),1500);
}
$('save-world').addEventListener('click',()=>{
  // When editing the playable map, Save means write the actual game world,
  // not an unrelated localStorage copy that Godot never reads.
  if(isMorrowEdit(doc)&&liveSession&&loadedWorldSha){
    $('save-morrow').click();
    return;
  }
  try{
    const last=localStorage.getItem(SAVE),next=serializeWorld(doc);
    if(last&&last!==next)auditUI.stash(last);
    localStorage.setItem(SAVE,next);dirty=false;
    status('Saved in browser. Previous save retained when storage permits; export JSON for a portable backup.');
  }
  catch{status('Browser storage is full or disabled. Export JSON instead.');}
});
$('load-world').addEventListener('click',()=>{
  try{
    const saved=localStorage.getItem(SAVE);
    if(!saved)return status('No manually saved world found.');
    if(dirty&&!window.confirm('Replace your current unsaved edits with the saved world?'))return;
    startWorld(parseWorld(saved),'Opened manually saved world.');
  }catch(e){errorMessage(e);}
});
$('import-world').addEventListener('change',async event=>{
  const file=event.target.files?.[0];if(!file)return;
  try{
    if(file.size>8_000_000)throw new RangeError('World file exceeds 8 MB');
    const parsed=parseWorld(await file.text());
    if(!dirty||window.confirm('Import replaces unsaved edits. Export JSON for a reliable backup; a small local recovery is attempted. Continue?'))
      startWorld(parsed,'Imported editable world. Run Map health before Godot export.');
  }catch(e){errorMessage(e);}
  event.target.value='';
});
$('export-world').addEventListener('click',()=>{
  try{download(serializeWorld(doc),worldSlug(doc.name)+'.world.json','application/json');status('World geometry JSON downloaded.');}
  catch(e){errorMessage(e);}
});
$('export-godot').addEventListener('click',async()=>{
  const button=$('export-godot');button.disabled=true;
  try{
    if(!auditUI.preflight())return;
    const response=await fetch('./world_loader.gd',{cache:'no-store'});
    if(!response.ok)throw new Error('Could not load the Godot world adapter from the server.');
    const zip=buildWorldZip(doc,await response.text());
    download(zip.bytes,worldSlug(doc.name)+'-godot4.zip','application/zip');
    status('Godot 4 world ZIP downloaded. See CODEX_IMPORT.md inside.');
  }catch(e){errorMessage(e);}
  finally{button.disabled=false;}
});
const auditUI=createMapAuditUI({
  getDoc:()=>doc,change,download,worldSlug,status,
  startWorld,getDirty:()=>dirty,
  selectIssue:issue=>{
    if(draft)cancelDraft(false);
    setTool('select');
    if(issue.entityId)setSelection(issue.entityId);
    setZoom(Math.max(zoom,.45));
    focusPoint(issue.point);
    status(issue.message);
  }
});
document.addEventListener('gdt-world-asset-ready',requestRender);
$('prop-type').addEventListener('change',refreshSpriteLists);
$('import-sprite').addEventListener('change',async event=>{
  const file=event.target.files?.[0];
  if(!file)return;
  try{
    if(!['image/png','image/webp'].includes(file.type))throw new TypeError('Only PNG and WebP artwork is supported.');
    if(file.size>950_000)throw new RangeError('Sprite artwork must be under 950 KB.');
    const src=await new Promise((resolve,reject)=>{
      const reader=new FileReader();
      reader.onload=()=>resolve(reader.result);
      reader.onerror=()=>reject(new Error('Could not read sprite file.'));
      reader.readAsDataURL(file);
    });
    const image=new Image();image.src=src;await image.decode();
    if(image.naturalWidth>2048||image.naturalHeight>2048)throw new RangeError('Sprites must be 2048 pixels or smaller.');
    const previous=doc;
    change(d=>addSpriteAsset(d,{name:file.name,src,width:image.naturalWidth,height:image.naturalHeight}),
      'Imported custom artwork: '+file.name+'. Select it for scenery placement.');
    if(doc!==previous){const id=doc.assets.at(-1).id;$('prop-asset').value=id;}
  }catch(e){errorMessage(e);}
  event.target.value='';
});
const resize=new ResizeObserver(requestRender);resize.observe(viewport);
window.addEventListener('resize',requestRender);
try{const stored=localStorage.getItem(AUTO);if(stored)doc=parseWorld(stored);}catch{}
// Read-only integration/testing API. Callers cannot mutate editor state through this snapshot.
window.GDTWorldForge=Object.freeze({getSnapshot:()=>structuredClone(doc)});
window.StreetboundMapEditor=window.GDTWorldForge;
refreshUI();
requestAnimationFrame(async()=>{
  fit();
  const session=await detectProjectMode();
  if(session){
    // Local project mode always opens the live game, not an outdated demo
    // cached in the browser from a previous editing session.
    liveSession=session;
    await openGameMap({skipConfirm:true});
  }else status('Map Builder ready. Open Game Map for the current Morrow Coast; '+
    'launch Start Map Editor.cmd for one-click project saves.');
});
