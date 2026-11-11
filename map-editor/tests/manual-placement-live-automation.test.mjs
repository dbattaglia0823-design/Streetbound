import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWorld,createEntity,updateEntity,normalizeWorld,serializeWorld,moveControlPoint} from '../world-model.js';
import {paintSceneryBrush} from '../world-edit-tools.js';
import {repairRoadsideObjects,placementFootprint,roadwayClearance} from '../world-road-placement.js';
import {liveRoadAutomation,liveRoadClearances} from '../world-automation-preview.js';
import {auditWorld} from '../world-audit.js';
import {applyEnvironmentPreset} from '../world-environment-presets.js';

const p=(x,y)=>({x,y});
const road=(name,points,surface='asphalt')=>({
  name,roadClass:'city',surface,width:28,lanes:2,shoulder:2,
  markings:true,smooth:false,points
});
const fixture=()=>createWorld({name:'Manual placement check',width:1600,height:1200});

test('manual scenery creation/editing retains precise coordinates and angles even over road',()=>{
  let doc=createEntity(fixture(),'roads',
    road('East-west',[p(100,600),p(1500,600)]));
  doc=createEntity(doc,'props',{type:'house',name:'Manual house',
    x:520,y:600,rotation:37,scale:1,assetId:''});
  const house=doc.props[0];
  assert.deepEqual([house.x,house.y,house.rotation],[520,600,37],
    'house does not auto-jump to another roadside when first placed');
  const changed=updateEntity(doc,house.id,{x:750,y:610,rotation:-62,scale:1.4});
  assert.deepEqual([changed.props[0].x,changed.props[0].y,changed.props[0].rotation],
    [750,610,-62]);
  assert.deepEqual(doc.props[0],house,'source remains unchanged for Undo');
  assert.ok(auditWorld(changed).issues.some(issue=>issue.code==='scenery_over_road'),
    'road conflicts are disclosed as warnings without moving scenery');
});

test('adopted game house can be moved without hidden road snapping or relocation',()=>{
  let doc=createEntity(fixture(),'roads',
    road('Street',[p(100,650),p(1500,650)]));
  doc=normalizeWorld({...doc,props:[{
    id:'prop-44',name:'Adopted coastal house',type:'house',
    x:330,y:420,rotation:0,scale:1,assetId:'',
    replaces:{kind:'coastal_house',seed:34,p:[330,420]},hidden:false
  }]});
  const moved=updateEntity(doc,'prop-44',{x:500,y:650,rotation:90});
  assert.deepEqual([moved.props[0].x,moved.props[0].y,moved.props[0].rotation],
    [500,650,90]);
  assert.deepEqual(moved.props[0].replaces,doc.props[0].replaces,
    'original replacement identity stays stable after manual movement');
});

test('editing a road never silently relocates any placed scenery or markers',()=>{
  let doc=createEntity(fixture(),'roads',
    road('Avenue',[p(100,400),p(1500,400)]));
  doc=createEntity(doc,'props',{type:'building',name:'Unrelated shop',
    x:750,y:750,rotation:11,scale:1,assetId:''});
  doc=createEntity(doc,'markers',{type:'race_start',name:'Start',
    x:750,y:400,rotation:0,properties:{}});
  const before=serializeWorld(doc);
  const moved=moveControlPoint(doc,doc.roads[0].id,0,p(100,750));
  assert.deepEqual(moved.props,doc.props);
  assert.deepEqual(moved.markers,doc.markers);
  assert.equal(serializeWorld(doc),before);
  const repaired=repairRoadsideObjects(moved);
  assert.deepEqual(repaired.doc.markers,doc.markers,
    'even explicit roadside repair must not touch markers');
});

test('explicit road repair affects only conflicting props, not the entire neighborhood',()=>{
  let doc=createEntity(fixture(),'roads',
    road('Repair surface',[p(100,650),p(1500,650)]));
  doc=createEntity(doc,'props',{type:'house',name:'Already clear',
    x:700,y:150,rotation:18,scale:1,assetId:''});
  doc=createEntity(doc,'props',{type:'sign',name:'On lane',
    x:850,y:650,rotation:7,scale:1,assetId:''});
  const normal=doc.props[0];
  const result=repairRoadsideObjects(doc);
  assert.deepEqual(result.doc.props[0],normal);
  assert.ok(result.moved>0);
  assert.ok(roadwayClearance(result.doc,result.doc.props[1],
    placementFootprint(result.doc,result.doc.props[1]))>=0);
});

test('live automation recomputes intersections, loose-road cutoffs and suggested joins',()=>{
  let doc=createEntity(fixture(),'roads',
    road('North-south',[p(800,100),p(800,1100)]));
  doc=createEntity(doc,'roads',
    road('East-west',[p(100,600),p(1500,600)]));
  doc=createEntity(doc,'roads',
    road('Dirt crossing',[p(100,700),p(1500,700)],'dirt'));
  doc=createEntity(doc,'roads',
    road('Gap A',[p(180,225),p(300,225)]));
  doc=createEntity(doc,'roads',
    road('Gap B',[p(315,225),p(430,225)]));
  const original=liveRoadAutomation(doc.roads);
  assert.ok(original.junctions.some(j=>j.roads.includes(doc.roads[0].id)&&
    j.roads.includes(doc.roads[1].id)));
  assert.ok(original.looseEnds.length>=2,
    'visible dirt road is clipped at nearby asphalt instead of connecting');
  assert.ok(original.gaps.some(g=>g.distance>2&&g.distance<=24));
  const moved=updateEntity(doc,doc.roads[1].id,{points:[p(100,1090),p(1500,1090)]});
  const fresh=liveRoadAutomation(moved.roads);
  assert.notEqual(fresh,original,'road changes invalidate the preview');
  assert.equal(original,liveRoadAutomation(doc.roads),'unchanged road arrays are cached');
  assert.deepEqual(doc.roads[1].points,[p(100,600),p(1500,600)],
    'preview calculations never mutate authored geometry');
});

test('live scenery conflict preview reports overlaps without changing positions',()=>{
  let doc=createEntity(fixture(),'roads',
    road('Road',[p(100,600),p(1500,600)]));
  doc=createEntity(doc,'props',{name:'Overlapping',type:'house',x:700,y:600,
    scale:1,rotation:0,assetId:''});
  const preview=liveRoadClearances(doc);
  assert.equal(preview.length,1);
  assert.equal(preview[0].id,doc.props[0].id);
  assert.deepEqual([doc.props[0].x,doc.props[0].y],[700,600]);
  assert.equal(liveRoadClearances(doc),preview);
});

test('paint brush never relocates sampled props beyond cursor radius',()=>{
  const origin=p(620,600),radius=70;
  const doc=fixture();
  const painted=paintSceneryBrush(doc,origin,{
    type:'oak',radius,count:10,spacing:10,avoidRoads:true,avoidWater:true,
    variation:false
  });
  assert.ok(painted.props.length>0);
  for(const item of painted.props)
    assert.ok(Math.hypot(item.x-origin.x,item.y-origin.y)<=radius+.1);
});

test('environment generators remain explicit and reversible, preview has no side effects',()=>{
  let doc=createEntity(fixture(),'roads',
    road('Preview avenue',[p(100,600),p(1500,600)]));
  const original=serializeWorld(doc);
  const result=applyEnvironmentPreset(doc,{preset:'street',
    selectedId:doc.roads[0].id,anchor:p(800,600),density:1});
  assert.ok(result.count>0);
  assert.equal(serializeWorld(doc),original);
  assert.deepEqual(result.doc.roads,doc.roads);
});

test('UI retains manual placement with live layers and explicit confirmation',async()=>{
  const editor=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const renderer=await readFile(new URL('../world-renderer.js',import.meta.url),'utf8');
  for(const id of ['show-junctions','show-road-priority','show-road-gaps',
    'show-road-clearances','show-preset-preview','live-automation-status'])
    assert.ok(html.includes('id="'+id+'"'),id);
  assert.match(editor,/drawLiveAutomation\(ctx,auto/);
  assert.match(editor,/previewPreset\(\)/);
  assert.match(editor,/drawPresetGhost\(ctx,generated/);
  assert.match(editor,/window\.confirm\([\s\S]*?Move.*overlapping scenery object/);
  assert.ok(!editor.includes('repairRoadsideObjects(next)'),
    'normal road changes must not repair every adjacent prop');
  assert.ok(!editor.includes('const fixed=repairRoadsideObjects(doc);'),
    'road drag completion must not relocate objects');
  assert.match(renderer,/roadSnapPreview/);
  assert.match(html,/<input id="road-smart-snap" type="checkbox">/,
    'automatic road-point snap should be visibly opt-in');
});
