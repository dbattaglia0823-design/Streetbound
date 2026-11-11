import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWorld,createEntity,normalizeWorld,serializeWorld,demoWorld} from '../world-model.js';
import {auditWorld,selfCrossing} from '../world-audit.js';
import {findEndpointGaps,snapSafeEndpoints,smartRoadSnap,
  cleanDuplicateRoadPoints,largeDragDistance} from '../world-safe-edit.js';

const coords=(...xy)=>xy.map(([x,y])=>({x,y}));
const base={name:'Road',roadClass:'city',surface:'asphalt',width:40,lanes:2,
  shoulder:3,smooth:false,markings:true};
const world=()=>createWorld({name:'Map Health Fixture',width:1600,height:1200});
const addRoad=(w,points,more={})=>createEntity(w,'roads',{...base,...more,points});
const codes=report=>report.issues.map(issue=>issue.code);

test('clean highways have no blocking geometry problems and report junctions',()=>{
  let doc=addRoad(world(),coords([100,600],[1500,600]));
  doc=addRoad(doc,coords([800,100],[800,1100]),{name:'Crossroad'});
  const data=auditWorld(doc);
  assert.equal(data.canExport,true);
  assert.equal(data.counts.errors,0);
  assert.ok(data.stats.junctions>0);
  assert.ok(codes(data).includes('missing_spawn'));
  assert.deepEqual(doc,normalizeWorld(doc),'audit never mutates the map');
});

test('adjacent duplicate control points block game export and one-click cleanup is reversible',()=>{
  const doc=addRoad(world(),coords([100,500],[400,500],[400,500],[900,500]));
  const before=serializeWorld(doc);
  const results=auditWorld(doc);
  assert.ok(codes(results).includes('road_zero_segment'));
  assert.equal(results.canExport,false);
  const repaired=cleanDuplicateRoadPoints(doc);
  assert.equal(repaired.removed,1);
  assert.equal(repaired.doc.roads[0].points.length,3);
  assert.equal(auditWorld(repaired.doc).canExport,true);
  assert.equal(serializeWorld(doc),before,'original version is unchanged for undo');
});

test('terrain self crossing blocks export, closed race circuits do not',()=>{
  let doc=addRoad(world(),coords([100,100],[500,100],[500,500],[100,500],[100,100]),
    {name:'Closed course',roadClass:'track',surface:'track'});
  doc=createEntity(doc,'regions',{name:'Twisted terrain',biome:'forest',elevation:0,
    points:coords([200,200],[1000,800],[200,800],[900,200])});
  const result=auditWorld(doc);
  assert.ok(codes(result).includes('terrain_self_crossing'));
  assert.ok(!codes(result).includes('road_self_crossing'));
  assert.ok(selfCrossing(doc.regions[0].points,{closed:true}));
});

test('only compatible nearby endpoints are suggested and repaired',()=>{
  let doc=addRoad(world(),coords([100,500],[420,500]),{name:'West'});
  doc=addRoad(doc,coords([440,500],[850,500]),{name:'East'});
  const unmodified=serializeWorld(doc);
  const gaps=findEndpointGaps(doc);
  assert.equal(gaps.length,1);
  assert.equal(gaps[0].distance,20);
  assert.ok(codes(auditWorld(doc)).includes('near_road_endpoint'));
  const fixed=snapSafeEndpoints(doc);
  assert.equal(fixed.count,1);
  const a=fixed.doc.roads[0].points.at(-1),b=fixed.doc.roads[1].points[0];
  assert.deepEqual(a,b);
  assert.equal(findEndpointGaps(fixed.doc).length,0);
  assert.equal(serializeWorld(doc),unmodified);
});

test('loose surfaces never auto-connect to pavement, including drawing snaps',()=>{
  let doc=addRoad(world(),coords([100,500],[420,500]),{name:'Asphalt'});
  doc=addRoad(doc,coords([440,500],[900,500]),{name:'Dirt',surface:'dirt'});
  assert.equal(findEndpointGaps(doc).length,0);
  assert.equal(snapSafeEndpoints(doc).count,0);
  const dirt=smartRoadSnap(doc,{x:420,y:500},'dirt',{radius:25});
  assert.notEqual(dirt?.roadId,doc.roads[0].id);
  const paving=smartRoadSnap(doc,{x:423,y:501},'asphalt',{radius:25});
  assert.equal(paving.roadId,doc.roads[0].id);
  assert.equal(paving.kind,'endpoint');
});

test('a near centerline snap is supported for T junctions on compatible surfaces',()=>{
  const doc=addRoad(world(),coords([100,600],[1400,600]));
  const hit=smartRoadSnap(doc,{x:800,y:606},'concrete',{radius:20});
  assert.equal(hit.kind,'centerline');
  assert.ok(Math.abs(hit.y-600)<.01);
  const loose=smartRoadSnap(doc,{x:800,y:606},'gravel',{radius:20});
  assert.equal(loose,null);
});

test('ambiguous close endpoint cluster is not silently repaired',()=>{
  let doc=addRoad(world(),coords([100,500],[400,500]));
  doc=addRoad(doc,coords([410,500],[750,500]));
  doc=addRoad(doc,coords([412,505],[1000,800]));
  const fixes=snapSafeEndpoints(doc);
  assert.ok(fixes.count<=1,'ambiguous endpoint is left for manual review');
});

test('scenery clearance warnings remain but game marker locations are unrestricted',()=>{
  let doc=addRoad(world(),coords([100,600],[1500,600]));
  doc=normalizeWorld({...doc,
    props:[{id:'prop-1',type:'house',name:'Obstructed house',x:550,y:600,rotation:0,
      scale:1,assetId:''}],
    markers:[{id:'marker-1',type:'race_start',name:'Wrong race start',x:1200,y:950,
      rotation:0,properties:{}}]});
  const result=auditWorld(doc);
  assert.equal(result.canExport,true);
  assert.ok(codes(result).includes('scenery_over_road'));
  assert.ok(!codes(result).includes('marker_off_road'),
    'game markers are intentional free overlays even when placed off road');
});

test('lane width warnings and self-crossing road detection are advisory',()=>{
  let doc=addRoad(world(),coords([100,200],[500,750],[100,750],[500,200]),
    {width:8,lanes:4});
  const result=auditWorld(doc);
  assert.equal(result.canExport,true);
  assert.ok(codes(result).includes('road_self_crossing'));
  assert.ok(codes(result).includes('narrow_lanes'));
});

test('large drag guard measures actual movement and is zero for nonroads',()=>{
  const a=addRoad(world(),coords([100,500],[900,500]));
  const b=normalizeWorld({...a,roads:[{...a.roads[0],points:coords([100,500],[1400,500])}]});
  assert.equal(largeDragDistance(a,b,a.roads[0].id),500);
  assert.equal(largeDragDistance(a,b,'missing'),0);
});

test('real demo map audits deterministically without altering original JSON',()=>{
  const doc=demoWorld();
  const before=serializeWorld(doc);
  const a=auditWorld(doc),b=auditWorld(doc);
  assert.deepEqual(a,b);
  assert.equal(serializeWorld(doc),before);
  assert.ok(a.stats.roads>0);
});

test('map editor includes health and backup controls, map audit UI and export preflight',async()=>{
  const files=['../world-audit.js','../world-safe-edit.js','../world-audit-ui.js',
    '../world-renderer.js','../world-editor.js','../index.html'];
  const parts=await Promise.all(files.map(x=>readFile(new URL(x,import.meta.url),'utf8')));
  const editor=parts[4],html=parts[5],auditUI=parts[2];
  for(const id of ['audit-run','audit-snap','audit-clean','audit-recover',
    'audit-backup','audit-show-overlay','road-smart-snap'])
    assert.ok(html.includes('id="'+id+'"'),id);
  assert.ok(editor.includes('auditUI.preflight()'));
  assert.ok(editor.includes('largeDragDistance('));
  assert.ok(editor.includes("auditUI.stash(doc)"));
  assert.ok(auditUI.includes('auditWorld(getDoc())'));
});

test('headless audit UI renders issues, blocks errors and allows JSON recovery',async()=>{
  const elements=new Map();
  class Element {
    constructor(){this.children=[];this.textContent='';this.checked=true;this.dataset={};this.events={};this.className='';}
    addEventListener(name,fn){this.events[name]=fn;}
    append(...items){this.children.push(...items);}
    replaceChildren(){this.children=[];}
    scrollIntoView(){}
  }
  const oldDoc=globalThis.document,oldLocal=globalThis.localStorage,oldWindow=globalThis.window;
  const storage=new Map();
  globalThis.document={
    getElementById(id){if(!elements.has(id))elements.set(id,new Element());return elements.get(id);},
    createElement(){return new Element();},
    createTextNode(text){return {textContent:text}}
  };
  globalThis.localStorage={getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value)};
  let confirms=0;
  globalThis.window={confirm:()=>{confirms++;return true;}};
  try{
    const {createMapAuditUI}=await import('../world-audit-ui.js');
    let doc=addRoad(world(),coords([100,500],[100,500],[1200,500]));
    const ctrl=createMapAuditUI({getDoc:()=>doc,
      change:edit=>{doc=edit(doc);},selectIssue:()=>{},download:()=>{},
      startWorld:(next)=>{doc=next;},getDirty:()=>true,worldSlug:()=>'',status:()=>{}});
    assert.equal(ctrl.preflight(),false);
    assert.equal(confirms,0,'blocking errors never show an override prompt');
    assert.ok(elements.get('audit-list').children.length>0);
    assert.ok(ctrl.issues.length>0);
    assert.ok(ctrl.stash(doc));
    elements.get('audit-clean').events.click();
    assert.equal(ctrl.preflight(),true);
    assert.equal(ctrl.report.counts.errors,0);
    elements.get('audit-recover').events.click();
    assert.ok(auditWorld(doc).counts.errors>0);
    ctrl.invalidate();
    assert.equal(ctrl.report,null);
    assert.equal(ctrl.issues.length,0);
  }finally{
    globalThis.document=oldDoc;globalThis.localStorage=oldLocal;globalThis.window=oldWindow;
  }
});
