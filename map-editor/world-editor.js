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
import {drawWorld,drawEditorOverlay,drawProp} from './world-renderer.js';
import {pickEditableScenery} from './world-selection.js';
import {buildWorldZip,worldSlug} from './world-export.js';
import {buildRoadJunctions} from './world-junctions.js';
import {liveRoadAutomation,liveRoadClearances,drawLiveAutomation} from './world-automation-preview.js';
import {smartRoadSnap,largeDragDistance} from './world-safe-edit.js';
import {joinRoadEndpoints,splitRoadAt} from './world-road-topology.js';
import {createMapAuditUI} from './world-audit-ui.js';
import {loadMorrowCoast,isMorrowEdit,expandMorrowWorld,morrowEditText,MORROW_EDIT_NAME,
  MORROW_MAX_WIDTH,MORROW_MAX_HEIGHT} from './morrow-coast-bridge.js';
import {buildRuntimePreview,browseRuntimeAssets,pickRuntimeProp,REPLACEABLE_KINDS,BASE_SIZE,
  GAME_ART,GAME_ART_KINDS} from './morrow-runtime-preview.js';
import {lanePatterns,drawLanePreview} from './traffic-patterns.js';
import {applyEnvironmentPreset} from './world-environment-presets.js';
import {encodeSession,decodeSession,shouldRestoreSession} from './world-session.js';
import {setProjectAssets,projectAssets,projectArtwork,projectAssetUrl} from './world-project-assets.js';
import {
  placeBesideRoad,nearestRoadPlacement,placementFootprint,
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
let busyDepth=0;
let sessionReady=false;
function setBusy(active){
  busyDepth+=active?1:-1;
  const dialog=$('busy-dialog');
  if(busyDepth>0&&!dialog.open)dialog.showModal();
  if(!busyDepth&&dialog.open)dialog.close();
  document.body.setAttribute('aria-busy',String(busyDepth>0));
  panSpace=false;
}
function flushAutosave(){
  if(!sessionReady)return; // Do not overwrite a draft while startup is still fetching its preview.
  clearTimeout(autosaveTimer);
  try{localStorage.setItem(AUTO,encodeSession(doc,{dirty,worldSha:loadedWorldSha,
    view:{zoom,x:(viewport.clientWidth/2-offsetX)/zoom,y:(viewport.clientHeight/2-offsetY)/zoom}}));}
  catch{status('Autosave unavailable. Export JSON to protect your world.');}
}
function readyToSave(){
  if(busyDepth)return false;
  if(draft||gesture){status('Finish or cancel the current shape or edit before saving.');return false;}
  return true;
}
let presetCache=null;
const laneCache=new WeakMap();
const trafficFor=()=>{let lanes=laneCache.get(doc.roads);if(!lanes){lanes=lanePatterns(doc.roads);laneCache.set(doc.roads,lanes);}return lanes;};
const minZoom=.007,maxZoom=5; // Entire 22k+ worlds still fit on narrow mobile viewports.
const status=message=>{$('status').textContent=message;$('busy-message').textContent=message;};
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
function previewPreset(){
  if(!$('show-preset-preview').checked)return null;
  const chosen=selection?getEntity(doc,selection.id):null;
  const item=chosen?.item;
  const mid=item?.points?.[Math.floor(item.points.length/2)];
  const anchor=mid||(item&&Number.isFinite(item.x)?{x:item.x,y:item.y}:
    worldPoint((viewport.clientWidth*.5-offsetX)/zoom,
      (viewport.clientHeight*.5-offsetY)/zoom));
  const options={preset:$('environment-preset').value,anchor,
    selectedId:selection?.id||null,density:Number($('environment-density').value),
    parkingSize:Number($('parking-size').value),
    stallWidth:Number($('parking-stall-width').value),
    occupancy:Number($('parking-occupancy').value),
    entranceWidth:Number($('parking-entrance').value)};
  const key=JSON.stringify(options);
  if(presetCache?.doc===doc&&presetCache.key===key)return presetCache.value;
  let value;
  try{
    const generated=applyEnvironmentPreset(doc,options).doc;
    value={addedProps:generated.props.slice(doc.props.length),
      addedRoads:generated.roads.slice(doc.roads.length),
      changedRegions:generated.regions.filter((r,i)=>r!==doc.regions[i])};
  }catch(e){value={error:e.message,addedProps:[],addedRoads:[],changedRegions:[]};}
  presetCache={doc,key,value};
  return value;
}
const currentDisplay = ()=>({
  showTerrain:$('show-terrain').checked,showRoads:$('show-roads').checked,
  junctions:$('show-junctions').checked,
  showScenery:$('show-scenery').checked,showMarkers:$('show-markers').checked
});
/** A transparent, uncommitted simulation of the selected environment
 * generator. This is the exact output of applyEnvironmentPreset, not a random
 * approximation. It disappears when disabled; Apply remains a separate action.
 */
function drawPresetGhost(ctx,generated,source,zoom,bounds){
  if(generated.error)return;
  const u=1/Math.max(.007,zoom);
  ctx.save();
  ctx.globalAlpha=.66;
  for(const road of generated.addedRoads){
    const pts=sampleRoad(road.points,road.smooth,12);
    if(pts.length<2)continue;
    ctx.beginPath();ctx.moveTo(pts[0].x,pts[0].y);
    for(const p of pts.slice(1))ctx.lineTo(p.x,p.y);
    ctx.lineWidth=road.width+2*u;ctx.strokeStyle='#a8e9e055';ctx.stroke();
    ctx.lineWidth=1.5*u;ctx.strokeStyle='#dbf9de';ctx.setLineDash([5*u,3*u]);
    ctx.stroke();ctx.setLineDash([]);
  }
  for(const prop of generated.addedProps){
    if(bounds&&(prop.x<bounds.minX-120||prop.x>bounds.maxX+120||
      prop.y<bounds.minY-120||prop.y>bounds.maxY+120))continue;
    const size=placementFootprint(source,prop);
    ctx.beginPath();ctx.arc(prop.x,prop.y,size,0,Math.PI*2);
    ctx.fillStyle='#9ce6bd30';ctx.fill();ctx.strokeStyle='#a8f8cf';
    ctx.lineWidth=1.5*u;ctx.setLineDash([4*u,3*u]);ctx.stroke();ctx.setLineDash([]);
  }
  for(const region of generated.changedRegions){
    if(region.points.length<3)continue;
    ctx.beginPath();ctx.moveTo(region.points[0].x,region.points[0].y);
    for(const p of region.points.slice(1))ctx.lineTo(p.x,p.y);
    ctx.closePath();ctx.strokeStyle='#b7f0cc';ctx.lineWidth=2*u;
    ctx.setLineDash([6*u,4*u]);ctx.stroke();ctx.setLineDash([]);
  }
  ctx.restore();
}

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
  // The live preview is derived from the CURRENT source, including the road
  // being dragged; no auto geometry modifies the saved map.
  const auto=liveRoadAutomation(doc.roads);
  const showClearances=$('show-road-clearances').checked;
  drawLiveAutomation(ctx,auto,{zoom,bounds,
    showJunctions:$('show-junctions').checked,
    showLoosePriority:$('show-road-priority').checked,
    showGaps:$('show-road-gaps').checked,
    showClearances,clearances:showClearances?liveRoadClearances(doc):[]});
  const generated=previewPreset();
  if(generated)drawPresetGhost(ctx,generated,doc,zoom,bounds);
  let roadsidePreview=null;
  if(tool==='prop'&&hover&&!$('scenery-paint').checked&&!$('scenery-erase').checked){
    try{
      const proposed={type:$('prop-type').value,assetId:$('prop-asset').value,
        x:hover.x,y:hover.y,rotation:0,scale:1};
      // Preview the exact cursor position; there is no automatic move.
      roadsidePreview={...proposed,radius:placementFootprint(doc,proposed)};
    }catch{/* Invalid placements do not render a misleading ghost. */}
  }
  if($('show-traffic').checked)drawLanePreview(ctx,trafficFor(),zoom,bounds);
  const closing=draft?.type==='road'&&draft.points.length>=3&&hover&&
    distance(hover,draft.points[0])<=clamp(15/zoom,8,28);
  const roadSnapPreview=closing?{point:draft.points[0],snapped:null}:
    tool==='road'&&hover&&$('road-smart-snap').checked?
    snapEnd(hover,$('road-surface').value):null;
  const selected=selection?getEntity(doc,selection.id):null;
  let alignmentPreview=null;
  if(selected?.type==='props'&&$('show-road-clearances').checked){
    try{
      const proposed=placeBesideRoad(doc,selected.item,
        {snap:true,align:true,maxSnapDistance:1500});
      const displacement=distance(proposed,selected.item);
      if(displacement>.1)
        alignmentPreview={from:selected.item,to:proposed,
          radius:placementFootprint(doc,proposed)};
    }catch{/* No safe projected alignment; the explicit action will report it. */}
  }
  drawEditorOverlay(ctx,doc,{selection,alignmentPreview,
    hover:draft?(roadSnapPreview?.point||hover):null,draft,zoom,roadsidePreview,
    roadSnapPreview:roadSnapPreview?.snapped?{from:hover,to:roadSnapPreview.point,
      kind:roadSnapPreview.snapped.kind}:null,
    insertMode:pointInsertMode,insertHover:tool==='select'?hover:null,
    brushPreview:tool==='prop'&&($('scenery-paint').checked||$('scenery-erase').checked)&&hover
      ?{position:hover,radius:Number($('brush-radius').value),erase:$('scenery-erase').checked}:null,
    showBoundaries:$('show-boundaries').checked,auditIssues:auditUI.issues});
  ctx.restore();
  ctx.setTransform(dpr,0,0,dpr,0,0);
  ctx.strokeStyle='#f5c29699';ctx.lineWidth=1;ctx.strokeRect(offsetX+.5,offsetY+.5,doc.world.width*zoom,doc.world.height*zoom);
  $('zoom-value').textContent=Math.round(zoom*100)+'%';
  const conflicts=$('show-road-clearances').checked?liveRoadClearances(doc).length:null;
  $('live-automation-status').textContent=
    auto.junctions.length+' live intersections · '+
    auto.looseEnds.length+' loose-road cut ends · '+
    auto.gaps.length+' possible road-end joins'+
    (conflicts===null?'':(' · '+conflicts+' scenery overlaps'))+
    (generated?.error?' · Preset: '+generated.error:
      generated?(' · Preset preview: '+generated.addedProps.length+
      ' props, '+generated.addedRoads.length+' access roads'):'');
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
// Keep existing inspector/creation controls and their event listeners intact.
// Move only relevant controls into a small, floating context panel. Every move
// leaves a placeholder so nodes can be returned to their original location.
let contextView='auto',contextKey='',contextCollapsed=false;
const contextOrigins=new Map();
function relocateContext(node,host){
  if(!node||!host)return;
  if(!contextOrigins.has(node)){
    const marker=document.createComment('context-control');
    node.before(marker);
    contextOrigins.set(node,marker);
  }
  host.append(node);
}
function restoreContext(){
  for(const [node,marker] of [...contextOrigins].reverse()){
    if(marker.parentNode)marker.replaceWith(node);
    else node.remove();
  }
  contextOrigins.clear();
  $('context-body').replaceChildren();
}
function contextGroup(title,nodes,expanded=false){
  const section=document.createElement('details');
  section.className='context-extra';section.open=expanded;
  const label=document.createElement('summary');label.textContent=title;section.append(label);
  for(const node of nodes)relocateContext(node,section);
  $('context-body').append(section);
}
function renderContextPanel(){
  const found=selection?getEntity(doc,selection.id):null;
  const view=contextView==='auto'?(tool==='select'&&found?'selected':tool):contextView;
  const id=found?.item.id||'';
  const key=view==='selected'?view+':'+found.type:view;
  const titles={selected:found?.item.name||'Selected item',select:'Select / Edit',
    road:'Draw road',terrain:'Terrain region',prop:'Place scenery',marker:'Place marker',
    pan:'Pan view',layers:'World layers',objects:'Map objects',health:'Map health',world:'World settings'};
  $('context-title').textContent=titles[view]||'Properties';
  document.querySelectorAll('[data-context-view]').forEach(b=>{
    b.setAttribute('aria-pressed',String(b.dataset.contextView===contextView));
  });
  // Do not move focused inputs during ordinary inspector updates.
  if(key===contextKey)return;
  contextKey=key;restoreContext();
  const body=$('context-body');
  const put=node=>relocateContext(node,body);
  const field=id=>$(id)?.closest('.field');
  const explain=message=>{
    const p=document.createElement('p');p.className='context-hint';p.textContent=message;body.append(p);
  };
  const left=document.querySelector('.left-panel');
  if(view==='road'){
    put(left.querySelectorAll(':scope > .settings-group')[0]);
  }else if(view==='terrain'){
    put(left.querySelectorAll(':scope > .settings-group')[1]);
  }else if(view==='prop'){
    put(field('prop-type'));put(field('prop-asset'));
    put(left.querySelector('.upload-asset'));
    contextGroup('Paint / erase scenery',[left.querySelector('.scenery-brush-controls:not([aria-labelledby="preset-title"])')]);
    contextGroup('Environment presets',[left.querySelector('[aria-labelledby="preset-title"]')]);
    contextGroup('Road alignment',[left.querySelector('.roadside-controls')]);
  }else if(view==='marker'){
    put(field('marker-type'));
  }else if(view==='selected'){
    put($('selected-type').closest('.panel-head'));
    put($('inspector-empty'));
    put($('inspector'));
    if(found?.type==='props')contextGroup('Road alignment',[left.querySelector('.roadside-controls')]);
  }else if(view==='layers'){
    put(document.querySelector('.right-panel .visibility-list'));
  }else if(view==='health'){
    put($('audit-heading'));put(document.querySelector('.right-panel .map-audit-panel'));
  }else if(view==='objects'){
    put($('entities-count').closest('.panel-head'));
    put(field('entities-filter')||$('entities-filter').closest('.filter-row'));
    put($('entity-list'));
  }else if(view==='world'){
    put($('morrow-expand-panel'));
    if(!isMorrowEdit(doc))explain('Open Game Map to edit and expand the playable world.');
  }else if(view==='select'){
    explain('Click a road, building, region or marker to edit it.');
  }else if(view==='pan'){
    explain('Drag the map to navigate. Use the mouse wheel to zoom.');
  }
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
  // Avoid showing two identical "Save to Game" actions in project mode.
  // The normal Save action already delegates to save-morrow when connected.
  $('save-morrow').hidden=true;
  $('save-world').textContent=isMorrowEdit(doc)&&liveSession?'Save to Game':'Save';
  $('adopt-game-prop').hidden=!runtimePreview;
  $('adopt-game-hint').hidden=!runtimePreview;
  $('game-asset-status').textContent=runtimePreview
    ?runtimePreview.propsCount.toLocaleString()+
      ' existing game scenery assets loaded (buildings, trees, rocks, parking and landmarks). '+
      doc.props.length+' editable additions/overrides. Select a game asset on the map or in the Assets list to edit it.'
    :'Open Game Map to load the playable scene and the asset atlas from the project folder.';
  $('world-dimensions').textContent=doc.world.width+' × '+doc.world.height+' world units';
  const gameAssets=runtimePreview?.propsCount||0;
  const authoringAdds=runtimePreview?doc.props.filter(p=>!p.replaces&&
    !runtimePreview.authoredIds.has(p.id)).length:doc.props.length;
  $('object-count').textContent=doc.roads.length+' roads · '+
    buildRoadJunctions(doc.roads).length+' intersections · '+
    doc.regions.length+' regions · '+
    (gameAssets+authoringAdds).toLocaleString()+' scenery assets'+
    (runtimePreview?' ('+gameAssets.toLocaleString()+' baked)':'');
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
  autosaveTimer=setTimeout(flushAutosave,650);
  refreshUI();if(label)status(label);
}
function change(edit,label){
  const before=doc;
  try{
    // Only the requested edit is committed. Do not reflow unrelated buildings
    // when a road changes: live clearances show potential problems instead.
    const next=edit(doc);
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
  autosaveTimer=setTimeout(flushAutosave,650);
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
    select:'Drag a road or terrain area to move it. Drag its control handles to reshape it. Alt-drag also moves the entire shape.',
    road:'Click to add road points. Click the first point again to close a loop, or press Enter to finish an open road. Nearby compatible endpoints snap together.',
    terrain:'Click around a terrain area. Double-click or Enter to close the polygon.',
    prop:'Click for a single prop, or enable hold-and-drag to paint or erase scenery.',
    marker:'Click to place a gameplay marker.',
    pan:'Drag to move around the open world.'
  }[next]);
  contextView='auto';renderContextPanel();
  refreshAssetDock();requestRender();
}
function setSelection(id,point=-1){
  if(id!==selection?.id)pointInsertMode=null;
  selection=id?{id,point}:null;
  refreshSpriteLists();
  refreshHeader();refreshInspector();refreshEntities();
  if(tool==='select')contextView='auto';
  renderContextPanel();requestRender();
}
function selectedShape(){
  const found=selection?getEntity(doc,selection.id):null;
  return found&&(found.type==='roads'||found.type==='regions')?found:null;
}
function choosePointInsert(mode){
  const found=selectedShape();
  if(!found){status('Select an existing road or terrain region first.');return;}
  if(mode!=='between'&&mode!=='split'&&found.type!=='roads')return;
  pointInsertMode=pointInsertMode?.id===selection.id&&pointInsertMode?.mode===mode?null:{id:selection.id,mode};
  refreshInspector();requestRender();
  status(pointInsertMode
    ?mode==='split'?'Click anywhere along the road to split it into two roads.':mode==='between'?'Click directly on the selected curve to insert a point.':'Click anywhere in the world to extend this end of the selected road.'
    :'Point insertion canceled.');
}
function insertSelectedPoint(p,mode='between'){
  const found=selectedShape();if(!found)return false;
  const threshold=clamp(14/zoom,17,75);
  if(mode==='split'){
    try{
      const before=doc;
      const result=splitRoadAt(doc,found.item.id,worldPoint(p.x,p.y),{maxDistance:threshold});
      doc=result.doc;pointInsertMode=null;
      makeSnapshot(before,'Split road at the chosen point. Both sections are editable and can be joined again.');
      setSelection(result.newRoadId,0);
      return true;
    }catch(e){errorMessage(e);return false;}
  }
  try{
    const result=insertShapePoint(doc,found.item.id,worldPoint(p.x,p.y),{mode,maxDistance:threshold});
    const before=doc;
    let next=result.doc;
    let joined=false;
    if(found.type==='roads'&&(mode==='start'||mode==='end')&&$('road-smart-snap').checked){
      const outcome=joinRoadEndpoints(next,found.item.id,{radius:clamp(15/zoom,8,28)});
      next=outcome.doc;joined=outcome.joined;
    }
    doc=next;pointInsertMode=null;
    makeSnapshot(before,joined?'Extended and joined the road to a compatible endpoint.':
      'Added control point '+(result.index+1)+'. Drag it to reshape the '+(found.type==='roads'?'road':'coastline')+'.');
    setSelection(found.item.id,joined?-1:result.index);
    return true;
  }catch(e){errorMessage(e);return false;}
}
/** Make a visible native house/object editable on first click, keeping the
 * same source replacement identity so Apply to Game never duplicates it.
 */
function adoptRuntimeScenery(source){
  const type=REPLACEABLE_KINDS[source.kind],size=BASE_SIZE[type];
  if(!size)return null;
  const scale=clamp(Number(source.size[0])/size[0],.25,2.5);
  const same=item=>item.replaces&&item.replaces.kind===source.kind&&
    item.replaces.seed===source.seed&&
    Math.hypot(item.replaces.p[0]-source.p[0],item.replaces.p[1]-source.p[1])<.03;
  const existing=doc.props.find(same);
  if(existing){setSelection(existing.id);return existing.id;}
  // Numeric IDs must be parsed correctly even when several prior houses
  // have already been adopted. Keep stable, collision-free authoring IDs.
  const id='prop-'+(Math.max(0,...doc.props.map(item=>
    /^prop-\d+$/.test(item.id)?Number(item.id.slice(5)):0))+1);
  const next={id,type,name:'Game '+source.kind.replaceAll('_',' '),
    x:Number(source.p[0]),y:Number(source.p[1]),
    rotation:Number(source.angle)*180/Math.PI,scale,
    assetId:source.kind==='coastal_house'?'game-coastal_house':'',
    replaces:{kind:String(source.kind),seed:Number(source.seed)||0,
      p:[Number(source.p[0]),Number(source.p[1])]},hidden:false};
  const previous=doc;
  if(change(d=>normalizeWorld({...d,props:[...d.props,next]}),
      'Selected game scenery is now editable. Drag it or use the Inspector, then Apply to Game.')&&doc!==previous){
    adoptGameProp=false;$('adopt-game-prop').classList.remove('active');
    setSelection(id);
    return id;
  }
  return null;
}

function hitTest(p){
  // Keep handle picking close to the visibly drawn handle, otherwise at a
  // zoomed-out map the oversized hit radius prevents dragging the road body.
  const radius=clamp(8/zoom,6,26);
  // Match the visible stacking order: marker > visible scenery > road >
  // terrain. In particular, unadopted baked houses must be selectable
  // directly without first turning on a separate adoption mode.
  if($('show-markers').checked)
    for(let i=doc.markers.length-1;i>=0;i--)
      if(distance(p,doc.markers[i])<clamp(10/zoom,9,36))
        return {id:doc.markers[i].id,point:-1,kind:'entity'};
  if($('show-scenery').checked){
    const edited=pickEditableScenery(doc.props,p,{
      gameArt:Boolean(runtimePreview),tolerance:clamp(3/zoom,0,8)});
    if(edited)return {id:edited.id,point:-1,kind:'entity'};
    const native=pickRuntimeProp(runtimePreview,doc,p,clamp(9/zoom,6,48));
    if(native)return {kind:'native',source:native};
  }
  // Preserve precise selected road/terrain handles where no visible object
  // covers them, so coastline and spline editing stays fully functional.
  if(selection){
    const found=getEntity(doc,selection.id);
    if(found&&['roads','regions'].includes(found.type)){
      for(let i=0;i<found.item.points.length;i++)if(distance(p,found.item.points[i])<radius)
        return {id:selection.id,point:i,kind:'handle'};
    }
  }
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
    $('split-selected-road').disabled=item.points.length<2;
    $('join-selected-road').disabled=doc.roads.length<2;
    for(const [id,mode] of [['insert-road-point','between'],['extend-road-start','start'],['extend-road-end','end'],['split-selected-road','split']]){
      const button=$(id);const active=pointInsertMode?.id===item.id&&pointInsertMode.mode===mode;
      button.setAttribute('aria-pressed',String(active));button.classList.toggle('is-active',active);
    }
    $('insert-hint').textContent=pointInsertMode?.id===item.id
      ?(pointInsertMode.mode==='split'?'Click on the road where it should separate.':pointInsertMode.mode==='between'?'Click the selected road line to insert a control point.':'Click a new endpoint to extend the road.')
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
  // Scenery imported from the live game is stored in a spatial preview, not
  // doc.props, because the generator owns those thousands of source records.
  // Show actual game objects first in All / Scenery instead of "0 TOTAL".
  const showScenery=filter==='all'||filter==='props';
  const baseTypes=filter==='all'?['props','roads','regions','markers']:[filter];
  const baseEntries=baseTypes.flatMap(type=>doc[type].map(item=>({type,item})));
  const added=runtimePreview?doc.props.filter(p=>!p.replaces&&
    !runtimePreview.authoredIds.has(p.id)).length:0;
  const count=showScenery&&runtimePreview
    ?runtimePreview.propsCount+added+
      (filter==='all'?doc.roads.length+doc.regions.length+doc.markers.length:0)
    :baseEntries.length;
  $('entities-count').textContent=count.toLocaleString()+
    (showScenery&&runtimePreview?' ASSETS':' TOTAL');
  const maxRows=180;
  // All objects must retain room for roads, terrain and markers; dedicate
  // the full browser only when the user explicitly selects Game scenery.
  const nativeRows=filter==='all'?72:maxRows;
  const native=showScenery&&runtimePreview?
    browseRuntimeAssets(runtimePreview,doc,nativeRows):{total:0,rows:[]};
  const entries=[
    ...baseEntries.filter(e=>e.type==='props'),
    ...native.rows.map(item=>({type:'native',item})),
    ...baseEntries.filter(e=>e.type!=='props')
  ];
  let visibleEntries=entries.slice(0,maxRows);
  const selected=baseEntries.find(e=>e.item.id===selection?.id);
  if(selected&&!visibleEntries.some(e=>e.item.id===selected.item.id)){
    if(visibleEntries.length>=maxRows)visibleEntries=visibleEntries.slice(0,maxRows-1);
    visibleEntries.push(selected);
  }
  if(!visibleEntries.length){
    const empty=document.createElement('p');empty.className='muted-copy';
    empty.textContent=runtimePreview&&showScenery
      ?'No baked scenery found. Check the playable world archive and rebuild.'
      :'No objects in this category yet.';
    list.append(empty);
  }
  if(showScenery&&runtimePreview&&native.rows.length){
    const hint=document.createElement('p');hint.className='muted-copy';
    hint.textContent='Existing game scenery, nearest player start first. Click an asset to locate it; ordinary scenery becomes editable. Landmarks are protected. Apply to Game saves changes.';
    list.append(hint);
  }
  for(const {type,item} of visibleEntries){
    const game=type==='native';
    const source=game?item.source:null;
    const row=document.createElement('button');row.type='button';
    row.className='entity-row'+(selection?.id===item.id?' selected':'');
    row.setAttribute('aria-pressed',String(!game&&selection?.id===item.id));
    row.title=game
      ?(item.editable?'Edit existing game asset':'Protected game landmark — locate only')
      :item.name;
    const ico=document.createElement('span');ico.className='icon';
    ico.textContent=game?'♣':{roads:'〰',regions:'⬡',props:'♣',markers:'◇'}[type];
    const name=document.createElement('span');name.className='entity-name';
    name.textContent=game
      ?item.name+' · '+Math.round(item.x)+', '+Math.round(item.y)
      :item.name;
    const tag=document.createElement('span');tag.className='entity-type';
    tag.textContent=game?(item.editable?'GAME':'LANDMARK'):
      {roads:'ROAD',regions:'LAND',props:'EDIT',markers:'POINT'}[type];
    row.append(ico,name,tag);
    row.addEventListener('click',()=>{
      setTool('select');
      if(game){
        // Do not move or overwrite gameplay-critical POI scenery. Selection
        // of ordinary game assets creates an explicit, undoable override.
        if(item.editable)adoptRuntimeScenery(source);
        else status('Protected game landmark: location shown. Its original asset is unchanged.');
        if(zoom<0.5)setZoom(0.65);
        focusPoint(item);
      }else{
        setSelection(item.id);
        if(type==='props'||type==='markers')focusPoint(item);
        else focusPoint(item.points.reduce((p,q)=>({
          x:p.x+q.x/item.points.length,y:p.y+q.y/item.points.length
        }),{x:0,y:0}));
      }
    });
    list.append(row);
  }
  if(count>visibleEntries.length){
    const hint=document.createElement('p');hint.className='muted-copy';
    hint.textContent='Showing '+visibleEntries.length+' of '+count.toLocaleString()+
      ' objects. Pan the map or click visible scenery to edit other existing assets.';
    list.append(hint);
  }
}
const ASSET_GROUPS={
  nature:new Set(['oak','pine','palm','bush','rock','boulder']),
  buildings:new Set(['house','building','warehouse','garage','gas_station']),
  roads:new Set(['streetlight','sign','barrier','dock','parking','parked_car']),
  landscaping:new Set(['planter','garden','field','island','forecourt'])
};
let activeDockAsset=null;
let projectCatalogSignature='',catalogLoading=false;
async function refreshProjectAssets(){
  if(catalogLoading)return;
  catalogLoading=true;
  try{
    const response=await fetch('/api/project-assets',{cache:'no-store'});
    if(!response.ok)throw new Error('Start Map Editor.cmd to discover project artwork.');
    const data=await response.json(),signature=JSON.stringify(data.assets);
    if(signature!==projectCatalogSignature){
      setProjectAssets(data.assets);projectCatalogSignature=signature;refreshUI();
    }
  }finally{catalogLoading=false;}
}
const dockCategory=type=>Object.entries(ASSET_GROUPS).find(([,types])=>types.has(type))?.[0]||'roads';
function assetCandidates(){
  const kinds=[...$('prop-type').options].filter(option=>option.value);
  const assets=[];
  for(const kind of kinds){
    assets.push({type:kind.value,assetId:'',label:kind.textContent,group:dockCategory(kind.value)});
    if(runtimePreview)for(const [assetId,name] of GAME_ART)
      if((GAME_ART_KINDS[kind.value]||[]).includes(assetId.slice(5)))
        assets.push({type:kind.value,assetId,label:name,group:dockCategory(kind.value),game:true});
    for(const custom of doc.assets){
      assets.push({type:kind.value,assetId:custom.id,label:custom.name,group:'imported',custom});
    }
  }
  for(const item of projectAssets())assets.push({type:item.type,assetId:item.id,
    label:item.name,group:'buildings',project:true});
  return assets;
}
function drawAssetThumbnail(canvas,item){
  const ctx=canvas.getContext('2d');
  if(!ctx)return;
  ctx.clearRect(0,0,canvas.width,canvas.height);
  const usingNativeArt=item.game||(!item.custom&&!!runtimePreview);
  // The standalone illustrated props are intentionally larger than the
  // metre-scale game atlas. Fit them independently to avoid clipped thumbnails.
  const [w,h]=item.project?projectArtwork({type:item.type,assetId:item.assetId}).size:
    item.custom?[item.custom.width,item.custom.height]:
    usingNativeArt?(BASE_SIZE[item.type]||[30,30]):[116,104];
  const extent=Math.max(1,w,h);
  const scale=Math.min(67/extent,8);
  ctx.save();
  ctx.translate(canvas.width/2,canvas.height/2);
  ctx.scale(scale,scale);
  // Render with the same renderer and asset selection as the placement preview.
  drawProp(ctx,{id:'dock-'+item.type,x:0,y:0,rotation:0,scale:1,
    type:item.type,assetId:item.assetId},
    doc.assets,usingNativeArt);
  ctx.restore();
}
function refreshAssetDock(){
  const container=$('asset-dock-scroller');
  if(!container)return;
  const category=$('asset-dock-category').value;
  const query=$('asset-dock-search').value.trim().toLowerCase();
  const all=assetCandidates();
  const filtered=all.filter(item=>(category==='all'||category===item.group)&&
    (!query||(item.label+' '+item.type+' '+item.group).toLowerCase().includes(query)));
  const fragment=document.createDocumentFragment();
  const selectedType=$('prop-type').value,selectedArtwork=$('prop-asset').value;
  for(const item of filtered){
    const card=document.createElement('button');
    card.type='button';card.className='asset-dock-card';
    const chosen=selectedType===item.type&&selectedArtwork===item.assetId;
    if(chosen)card.classList.add('selected');
    card.setAttribute('aria-pressed',String(chosen&&tool==='prop'));
    card.title=item.label+' · '+item.type.replaceAll('_',' ');
    const preview=document.createElement('canvas');
    preview.width=112;preview.height=80;preview.setAttribute('aria-hidden','true');
    card.append(preview);
    const caption=document.createElement('span');caption.className='asset-dock-name';
    caption.textContent=item.label;card.append(caption);
    if(item.assetId){
      const origin=document.createElement('small');
      origin.textContent=item.custom?'Imported':'Game artwork';
      card.append(origin);
    }
    card.addEventListener('click',()=>{
      $('prop-type').value=item.type;
      refreshSpriteLists();
      $('prop-asset').value=item.assetId;
      activeDockAsset=item.type+':'+item.assetId;
      setTool('prop');refreshAssetDock();
      status('Ready to place '+item.label+'. Click the map to add it.');
    });
    fragment.append(card);
    drawAssetThumbnail(preview,item);
  }
  if(!filtered.length){
    const empty=document.createElement('p');
    empty.className='asset-dock-empty';empty.textContent='No matching assets. Choose another category or clear the search.';
    fragment.append(empty);
  }
  container.replaceChildren(fragment);
  $('asset-dock-count').textContent=filtered.length+' of '+all.length+' assets';
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
    if(['house','building','warehouse','garage','gas_station'].includes(type))
      for(const asset of projectAssets())select.append(new Option('Project folder · '+asset.name,asset.id));
    select.value=[...select.options].some(option=>option.value===previous)?previous:'';
  }
}
function refreshUI(){refreshSpriteLists();refreshHeader();refreshInspector();refreshEntities();renderContextPanel();refreshAssetDock();requestRender();}
function startWorld(world,message,{skipRecovery=false,preview=null,restoredDirty=false,worldSha='',view=null}={}){
  clearTimeout(autosaveTimer);
  if(gesture?.mode==='spray')clearInterval(gesture.timer);
  if(dirty&&!skipRecovery)auditUI.stash(doc);
  doc=normalizeWorld(world);selection=null;pointInsertMode=null;draft=null;gesture=null;
  sessionReady=true;
  runtimePreview=preview;loadedWorldSha=worldSha;adoptGameProp=false;
  undoStack=[];redoStack=[];dirty=restoredDirty;
  auditUI.invalidate();refreshUI();fit();status(message);
  if(view){setZoom(view.zoom);focusPoint(view);}
  flushAutosave();
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
      applied=change(d=>{
        const created=createEntity(d,'roads',{name:roadClass[0].toUpperCase()+roadClass.slice(1)+' road',roadClass,surface,
          width,lanes,shoulder,smooth:$('road-smooth').checked,markings:$('road-markings').checked,points:work.points});
        if(!$('road-smart-snap').checked)return created;
        const newId=created.roads.at(-1).id;
        // Join one or both unambiguous compatible end pairs as part of this
        // same undo step; T junctions and mismatched road types remain separate.
        let working=created;
        for(let i=0;i<2;i++){
          const outcome=joinRoadEndpoints(working,newId,{radius:1});
          if(!outcome.joined)break;
          working=outcome.doc;
        }
        return working;
      },'Road added. Compatible touching road ends joined automatically.');
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
  // Closing a road is always available, even when snapping to other roads is disabled.
  // Keep the original first point as the shared endpoint so the geometry is exact.
  const first=draft?.type==='road'&&draft.points.length>=3?draft.points[0]:null;
  const closeRadius=clamp(15/zoom,8,28);
  const closesLoop=tool==='road'&&first&&distance(point,first)<=closeRadius;
  const where=closesLoop?{...first}:(snap?snap.point:point);
  if(!draft)draft={type:tool,width:Number($('road-width').value),points:[]};
  if(draft.points.length && distance(draft.points.at(-1),where)<1) return;
  draft.points.push(where);
  if(closesLoop){finishDraft();return;}
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
    if(change(d=>createEntity(d,'props',{type,name:projectAssets().find(a=>a.id===$('prop-asset').value)?.name||type.replace(/_/g,' '),x:p.x,y:p.y,scale:1,rotation:0,assetId:$('prop-asset').value}),
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
      const source=pickRuntimeProp(runtimePreview,doc,p,clamp(9/zoom,6,48));
      if(!source){
        status('No unedited game scenery at that point. Select an already edited house normally.');
        return;
      }
      adoptRuntimeScenery(source);
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
    if(hit?.kind==='native'){
      const id=adoptRuntimeScenery(hit.source);
      const adopted=id?getEntity(doc,id):null;
      if(adopted){
        gesture={mode:'entity',before:doc,id,start:p,
          x:adopted.item.x,y:adopted.item.y};
        canvas.setPointerCapture(event.pointerId);
      }
      return;
    }
    setSelection(hit?.id||null,hit?.point??-1);
    if(!hit)return;
    const found=getEntity(doc,hit.id);
    if(hit.kind==='handle'){
      gesture={mode:'control',before:doc,id:hit.id,index:hit.point};
      canvas.setPointerCapture(event.pointerId);
    }else if(found&&['roads','regions'].includes(found.type)&&hit.kind==='entity'){
      // Whole-shape dragging is the default when pressing the road body or
      // the interior of a region. Handles above still edit individual points.
      // The original map is used on every pointermove (no accumulating drift).
      gesture={mode:'shape',before:doc,id:hit.id,start:p};
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
        // Join when an existing endpoint is dragged onto another compatible
        // endpoint. Interior edits keep all existing road objects separate.
        if($('road-smart-snap').checked&&
          (current.mode==='shape'||(current.mode==='control'&&
          (current.index===0||current.index===doc.roads.find(r=>r.id===current.id)?.points.length-1)))){
          const joined=joinRoadEndpoints(doc,current.id,{radius:clamp(15/zoom,8,28)});
          if(joined.joined){doc=joined.doc;selection={id:joined.roadId,point:-1};pointInsertMode=null;}
        }
        // New junctions and overlap indicators update live, but unchanged
        // scenery and game markers remain at their authored coordinates.
      }
      makeSnapshot(current.before,'Moved '+(current.mode==='control'?'control point':
        current.mode==='shape'?'entire shape':'object')+
        '. Other assets stayed in place; review live road clearances if needed.');
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
  if(busyDepth){event.preventDefault();return;}
  if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='s'){
    event.preventDefault();
    if(event.target instanceof HTMLElement)event.target.blur();
    $('save-world').click();return;
  }
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
for(const [id,mode] of [['insert-road-point','between'],['extend-road-start','start'],['extend-road-end','end'],['split-selected-road','split']])
  $(id).addEventListener('click',()=>choosePointInsert(mode));
$('join-selected-road').addEventListener('click',()=>{
  const found=selectedShape();
  if(!found||found.type!=='roads')return status('Select a road to join.');
  const radius=clamp(15/zoom,8,28);
  try{
    const result=joinRoadEndpoints(doc,found.item.id,{radius});
    if(!result.joined)return status('No unambiguous matching road ends. Move two compatible road endpoints together first.');
    const before=doc;doc=result.doc;pointInsertMode=null;
    makeSnapshot(before,'Joined two roads into one editable road.');
    setSelection(result.roadId);
  }catch(e){errorMessage(e);}
});
for(const [id,axis] of [['inspect-point-x','x'],['inspect-point-y','y']]){
  $(id).addEventListener('change',event=>{
    const found=selectedShape();if(!found||selection.point<0)return;
    const numeric=Number(event.target.value);
    if(!Number.isFinite(numeric)||numeric<0||numeric>(axis==='x'?doc.world.width:doc.world.height)){
      errorMessage(new RangeError('Point coordinate is outside the world'));refreshInspector();return;
    }
    const original=found.item.points[selection.point];
    const pointIndex=selection.point;
    const endpoint=found.type==='roads'&&(pointIndex===0||pointIndex===found.item.points.length-1);
    if(!change(d=>{
      const changed=moveControlPoint(d,found.item.id,pointIndex,{...original,[axis]:numeric});
      if(!endpoint||!$('road-smart-snap').checked)return changed;
      return joinRoadEndpoints(changed,found.item.id,{radius:1}).doc;
    },'Updated road control point. Compatible endpoints join automatically.'))refreshInspector();
    else if(endpoint)setSelection(found.item.id,-1);
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
  if(found?.type!=='props')
    return status('Select a scenery object to align; gameplay markers stay wherever you place them.');
  try{
    const before=doc;
    const placed=placeBesideRoad(doc,found.item,{snap:true,align:true,maxSnapDistance:1500});
    const travel=distance(placed,found.item);
    if(travel>40&&!window.confirm(
      'Align '+found.item.name+' to the road '+Math.round(travel)+
      ' world units away? This only moves the selected object and can be undone.'))return;
    doc=updateEntity(doc,selection.id,{x:placed.x,y:placed.y,rotation:placed.rotation});
    if(before!==doc)makeSnapshot(before,'Aligned scenery with the road and cleared the shoulder.');
    $('roadside-status').textContent='Selected scenery checked against nearby roads.';
  }catch(e){errorMessage(e);}
});
$('repair-roadside').addEventListener('click',()=>{
  // Only actual roadway conflicts are candidates, never every authored house.
  const result=repairRoadsideObjects(doc);
  const count=result.moved+result.rotated;
  if(count&&!window.confirm(
      'Move '+count+' overlapping scenery object(s) to safe roadside positions? '+
      'All other assets and gameplay markers will stay exactly where they are. '+
      'This can be undone.'))return;
  if(result.doc!==doc){
    const before=doc;doc=result.doc;
    makeSnapshot(before,'Moved '+count+' overlapping scenery objects (explicit repair).');
  }
  $('roadside-status').textContent='Repaired '+count+' overlapping scenery objects.'+
    (result.failed?' '+result.failed+' still need manual review.':
      ' All other scenery and markers were left unchanged.');
});
$('environment-preset').addEventListener('change',()=>{
  $('parking-generator-controls').hidden=$('environment-preset').value!=='parking';
  requestRender();
});
for(const id of ['environment-density','parking-size','parking-stall-width',
  'parking-occupancy','parking-entrance'])$(id).addEventListener('change',requestRender);
$('road-smart-snap').addEventListener('change',requestRender);
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
for(const id of ['show-roads','show-junctions','show-road-priority','show-road-gaps',
  'show-road-clearances','show-preset-preview','show-terrain','show-scenery',
  'show-markers','show-boundaries','audit-show-overlay','show-traffic'])
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
async function openGameMap({skipConfirm=false,fromApply=false}={}){
  if(busyDepth&&!fromApply)return false;
  const button=$('load-morrow');
  if(!skipConfirm&&dirty&&!window.confirm(
    'Reload current playable Morrow Coast? Keep unsaved edits with Export JSON first.'))return;
  button.disabled=true;
  setBusy(true);
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
    // Build the native asset browser BEFORE the world UI renders. Previously
    // the editor briefly displayed 0 scenery and could stay zoomed out so far
    // that thousands of 7-metre trees were effectively invisible.
    if(!Array.isArray(raw.props)||!raw.props.length)
      throw new Error('Playable Morrow Coast contains no baked scenery assets. Rebuild Morrow Coast from the source map before editing.');
    const preview=buildRuntimePreview(raw);
    startWorld(world,'Loaded current playable Morrow Coast: '+stats.roads+' roads, '+
      stats.regions+' regions, '+stats.landmarkMarkers+' landmarks and '+
      stats.proceduralProps.toLocaleString()+' existing baked scenery objects.',
      {preview});
    liveSession=session;
    loadedWorldSha=session?.worldSha||'';
    flushAutosave();
    $('show-traffic').checked=true;
    $('show-scenery').checked=true;
    // Start at the actual driving neighborhood where houses and foliage are
    // recognizable; Fit remains available for the whole-coast overview.
    setZoom(Math.max(zoom,0.65));
    const spawn=world.markers.find(item=>item.type==='player_spawn');
    if(spawn)focusPoint(spawn);
    refreshUI();
    status(stats.proceduralProps.toLocaleString()+' existing game assets loaded. '+
      (session?'Project connected: Apply to Game saves edits.':
        'Start Map Editor.cmd for direct project saves.')+
      ' Use Fit for the full map.');
    return true;
  }catch(e){errorMessage(e);return false;}
  finally{button.disabled=false;setBusy(false);}
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
  if(!readyToSave())return;
  if(!isMorrowEdit(doc))return status('Open Game Map first.');
  button.disabled=true;
  flushAutosave();setBusy(true);
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
      loadedWorldSha=result.worldSha;
      dirty=false;flushAutosave();
      if(!await openGameMap({skipConfirm:true,fromApply:true}))
        throw new Error('Map applied, but preview reload failed. Your saved edits are retained; use Open Game Map to retry.');
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
  finally{button.disabled=false;setBusy(false);}
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
  if(!readyToSave())return;
  if(isMorrowEdit(doc)&&liveSession&&!loadedWorldSha)
    return status('This recovered draft has no game revision. Export JSON before reopening the current game map.');
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
    flushAutosave();
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
  if(!readyToSave())return;
  try{download(serializeWorld(doc),worldSlug(doc.name)+'.world.json','application/json');status('World geometry JSON downloaded.');}
  catch(e){errorMessage(e);}
});
$('export-godot').addEventListener('click',async()=>{
  if(!readyToSave())return;
  const button=$('export-godot');button.disabled=true;
  try{
    if(!auditUI.preflight())return;
    const response=await fetch('./world_loader.gd',{cache:'no-store'});
    if(!response.ok)throw new Error('Could not load the Godot world adapter from the server.');
    const images=new Map();
    for(const path of new Set(doc.props.map(p=>p.assetPath).filter(Boolean))){
      const image=await fetch(projectAssetUrl(path),{cache:'no-store'});
      if(!image.ok)throw new Error('Building artwork is missing: '+path);
      images.set('assets/'+path,new Uint8Array(await image.arrayBuffer()));
    }
    const zip=buildWorldZip(doc,await response.text(),images);
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
document.querySelectorAll('[data-context-view]').forEach(button=>{
  button.addEventListener('click',()=>{
    contextView=button.dataset.contextView;
    renderContextPanel();
  });
});
$('context-toggle').addEventListener('click',()=>{
  contextCollapsed=!contextCollapsed;
  $('context-panel').classList.toggle('collapsed',contextCollapsed);
  $('context-toggle').textContent=contextCollapsed?'+':'−';
  $('context-toggle').setAttribute('aria-expanded',String(!contextCollapsed));
  $('context-toggle').setAttribute('aria-label',contextCollapsed?'Expand properties':'Collapse properties');
});
// Capture before the existing map-health handler scrolls to its heading.
$('audit-top').addEventListener('click',()=>{
  contextView='health';renderContextPanel();
  $('context-panel').classList.remove('collapsed');contextCollapsed=false;
  $('context-toggle').textContent='−';
  $('context-toggle').setAttribute('aria-expanded','true');
},true);
document.addEventListener('gdt-world-asset-ready',()=>{requestRender();refreshAssetDock();});
$('asset-dock-category').addEventListener('change',refreshAssetDock);
$('asset-dock-search').addEventListener('input',refreshAssetDock);
$('asset-dock-collapse').addEventListener('click',()=>{
  const dock=$('asset-dock'),button=$('asset-dock-collapse');
  const closed=dock.classList.toggle('collapsed');
  button.setAttribute('aria-expanded',String(!closed));
  button.textContent=closed?'Show assets':'Hide assets';
});
$('prop-type').addEventListener('change',()=>{refreshSpriteLists();refreshAssetDock();});
$('prop-asset').addEventListener('change',refreshAssetDock);
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
    if(doc!==previous){const id=doc.assets.at(-1).id;$('prop-asset').value=id;refreshAssetDock();}
  }catch(e){errorMessage(e);}
  event.target.value='';
});
const resize=new ResizeObserver(requestRender);resize.observe(viewport);
$('busy-dialog').addEventListener('cancel',event=>event.preventDefault());
$('refresh-project-assets').addEventListener('click',()=>refreshProjectAssets()
  .then(()=>status(projectAssets().length+' project building assets found.')).catch(errorMessage));
setInterval(()=>{if(liveSession&&!busyDepth)refreshProjectAssets().catch(()=>{});},3000);
window.addEventListener('resize',requestRender);
let recoveredSession=null;
try{recoveredSession=decodeSession(localStorage.getItem(AUTO));}catch{}
window.addEventListener('pagehide',flushAutosave);
document.addEventListener('visibilitychange',()=>{if(document.hidden)flushAutosave();});
// Read-only integration/testing API. Callers cannot mutate editor state through this snapshot.
window.GDTWorldForge=Object.freeze({getSnapshot:()=>structuredClone(doc)});
window.StreetboundMapEditor=window.GDTWorldForge;
refreshUI();
requestAnimationFrame(async()=>{
  setBusy(true);
  try{
  fit();
  const session=await detectProjectMode();
  if(session)try{await refreshProjectAssets();}catch(e){errorMessage(e);}
  if(shouldRestoreSession(recoveredSession,Boolean(session))){
    liveSession=session;
    let preview=null;
    if(session&&isMorrowEdit(recoveredSession.doc)){
      try{const {raw}=await loadMorrowCoast();preview=buildRuntimePreview(raw);}
      catch{/* Keep the draft even when the source map cannot be fetched. */}
    }
    const stale=session&&isMorrowEdit(recoveredSession.doc)&&recoveredSession.worldSha!==session.worldSha;
    startWorld(recoveredSession.doc,'Restored your last editing session. '+
      (stale?'The game map has changed. Export this draft before reopening the current game map.':
        recoveredSession.dirty?'Unsaved edits recovered.':'Your browser save is ready.'),
      {preview,restoredDirty:recoveredSession.dirty,worldSha:recoveredSession.worldSha,view:recoveredSession.view});
    return;
  }
  if(session){
    // Local project mode always opens the live game, not an outdated demo
    // cached in the browser from a previous editing session.
    liveSession=session;
    await openGameMap({skipConfirm:true,fromApply:true});
  }else status('Map Builder ready. Open Game Map for the current Morrow Coast; '+
    'launch Start Map Editor.cmd for one-click project saves.');
  }finally{sessionReady=true;setBusy(false);}
});
