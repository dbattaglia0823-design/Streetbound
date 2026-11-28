import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {roadMarkingPlan,markerInteractionRanges,roadRenderPlan} from '../world-renderer.js';
import {createWorld,createEntity,parseWorld,serializeWorld,updateEntity} from '../world-model.js';
import {buildRoadJunctions} from '../world-junctions.js';
import {roadPieces,isLoose,pavedVsLoose} from '../world-road-priority.js';
import {buildRoadNetwork,buildWorldZip} from '../world-export.js';

const coords=(...xy)=>xy.map(([x,y])=>({x,y}));
const base={roadClass:'city',surface:'asphalt',width:56,shoulder:4,
  lanes:2,markings:true,smooth:false};
const build=(...items)=>{
  let doc=createWorld({name:'Streetbound Road Priority Test',width:1600,height:1200});
  for(const [name,surface,points,width=surface==='dirt'?24:56] of items){
    doc=createEntity(doc,'roads',{...base,name,surface,width,points});
  }
  return doc;
};
const crossing=()=>build(
  ['Paved across','asphalt',coords([120,600],[1480,600])],
  ['Trail north south','dirt',coords([800,100],[800,1100])]);
const near=(a,b,epsilon=2)=>Math.hypot(a.x-b.x,a.y-b.y)<epsilon;

test('auto-paves normal asphalt/concrete crossings and exports road connections',()=>{
  const doc=build(['East West','asphalt',coords([100,600],[1500,600])],
    ['North South','concrete',coords([800,100],[800,1100])]);
  const junctions=buildRoadJunctions(doc.roads);
  assert.ok(junctions.some(j=>Math.abs(j.x-800)<2&&Math.abs(j.y-600)<2));
  assert.ok(junctions.every(j=>j.polygon.length>=3));
  assert.ok(buildRoadNetwork(doc).connections.some(c=>c.roads.includes(doc.roads[0].id)&&
    c.roads.includes(doc.roads[1].id)));
});

test('T junctions produce junctions; parallel touching lanes do not',()=>{
  const t=build(['Main','asphalt',coords([100,600],[1500,600])],
    ['Side','asphalt',coords([800,170],[800,565])]);
  assert.ok(buildRoadJunctions(t.roads).length>0);
  const parallel=build(['North','asphalt',coords([200,580],[1300,580])],
    ['South','asphalt',coords([210,600],[1310,600])]);
  assert.equal(buildRoadJunctions(parallel.roads).length,0);
});

test('angled paved footprints merge even without a centerline intersection',()=>{
  const doc=build(
    ['Main','asphalt',coords([100,600],[1500,600])],
    ['Shallow connector','concrete',coords([450,400],[850,555],[1250,400])]);
  const junctions=buildRoadJunctions(doc.roads);
  assert.ok(junctions.some(j=>j.roads.includes(doc.roads[0].id)&&
    j.roads.includes(doc.roads[1].id)), 'near-miss pavement should connect');
  assert.ok(buildRoadNetwork(doc).connections.length>=1);
});

test('dirt crosses pavement visually but is not a junction or turn connection',()=>{
  const doc=crossing();
  assert.ok(isLoose(doc.roads[1]));
  assert.ok(pavedVsLoose(doc.roads[0],doc.roads[1]));
  assert.deepEqual(buildRoadJunctions(doc.roads),[]);
  const segments=roadPieces(doc.roads).get(doc.roads[1].id);
  assert.equal(segments.length,2,'north and south are separate');
  assert.ok(segments[0][0].y===100 && segments[1].at(-1).y===1100);
  const northEnd=segments[0].at(-1).y;
  const southStart=segments[1][0].y;
  assert.ok(northEnd<570&&northEnd>545,northEnd);
  assert.ok(southStart>630&&southStart<655,southStart);
  assert.ok(southStart-northEnd>56,'paved surface remains uninterrupted');
  const network=buildRoadNetwork(doc);
  assert.equal(network.connections.length,0);
  assert.equal(network.roads[1].traversableCenterlines.length,2);
  assert.equal(network.roads[1].pavedPriorityCuts,true);
});

test('dirt stops even if it was drawn first; straight two-point roads are sampled densely',()=>{
  const a=crossing();
  const b={...a,roads:[a.roads[1],a.roads[0]]};
  const northA=roadPieces(a.roads).get(a.roads[1].id);
  const northB=roadPieces(b.roads).get(a.roads[1].id);
  assert.equal(northA.length,2);
  assert.deepEqual(northA,northB);
  assert.ok(northA[0].length>30,'long straight track is densified');
  assert.equal(buildRoadJunctions(b.roads).length,0);
});

test('parallel dirt overlap is masked and a dirt trail can terminate at a paved highway',()=>{
  const doc=build(
    ['Main','asphalt',coords([100,600],[1500,600])],
    ['Partly overlapping dirt','dirt',coords([200,450],[530,600],[950,600],[1320,450])]);
  const segments=roadPieces(doc.roads).get(doc.roads[1].id);
  assert.ok(segments.length>=2,'dirt enters, disappears and exits');
  for(const segment of segments){
    assert.ok(segment.every(p=>Math.abs(p.y-600)>20||p.x<400||p.x>1080));
  }
  assert.equal(buildRoadJunctions(doc.roads).length,0);
  const terminating=build(['Main','asphalt',coords([100,600],[1500,600])],
    ['Short dirt access','dirt',coords([800,100],[800,600])]);
  assert.equal(roadPieces(terminating.roads).get(terminating.roads[1].id).length,1);
});

test('gravel behaves as an unpaved approach; loose-to-loose can still join',()=>{
  const doc=build(['Main','concrete',coords([100,600],[1500,600])],
    ['Gravel','gravel',coords([800,100],[800,1100])]);
  assert.equal(buildRoadJunctions(doc.roads).length,0);
  assert.equal(roadPieces(doc.roads).get(doc.roads[1].id).length,2);
  const trails=build(['Trail 1','dirt',coords([120,600],[1480,600])],
    ['Trail 2','dirt',coords([800,100],[800,1100])]);
  assert.ok(buildRoadJunctions(trails.roads).length>=1);
});

test('exported Godot map contains exactly the dirt breaks; source JSON stays editable',async()=>{
  const doc=crossing();
  const source=parseWorld(serializeWorld(doc));
  assert.equal(source.roads[1].renderPieces,undefined,'unmodified editable splines');
  const loader=await readFile(new URL('../world_loader.gd',import.meta.url),'utf8');
  const pack=buildWorldZip(doc,loader);
  assert.ok(pack.bytes.length>100);
  const path=[...pack.files.keys()].find(x=>x.endsWith('.world.json'));
  const runtime=JSON.parse(pack.files.get(path));
  assert.equal(runtime.roads[1].renderPieces.length,2,'Godot consumes clipped pieces');
  assert.equal(runtime.roads[0].renderPieces,undefined,'paved original untouched');
  const navigation=buildRoadNetwork(doc);
  assert.equal(navigation.connections.length,0);
  assert.equal(navigation.roads[1].traversableCenterlines.length,2);
  assert.ok(pack.files.has('runtime/world_loader.gd'));
  assert.ok(loader.includes('_road_pieces_cache'));
});

test('repo-owned UI has its dependencies and Windows launcher',async()=>{
  const paths=['../index.html','../theme.css','../world-editor.css','../world-editor.js',
    '../world-model.js','../world-geometry.js','../world-renderer.js',
    '../world-junctions.js','../world-road-priority.js','../world-road-placement.js',
    '../world-edit-tools.js','../world-export.js','../zip.js','../world_loader.gd',
    '../serve.ps1','../Start Map Editor.cmd'];
  for(const name of paths){
    assert.ok((await readFile(new URL(name,import.meta.url))).length>70,name);
  }
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  assert.ok(html.includes('world-editor.js'));
  assert.ok(html.includes('./theme.css'));
  assert.ok(!html.includes('../ui/theme.css'));
  assert.ok(!html.includes('atlas-coast-overview.svg'));
  const serve=await readFile(new URL('../serve.ps1',import.meta.url),'utf8');
  assert.ok(serve.includes('IPAddress]::Loopback'));
  assert.ok(serve.includes("TrimEnd([char[]]@("),'local server path must use one char-array argument');
});

test('explicit on-ramp survives serialization and labels its merge',()=>{
  let doc=createWorld({name:'Ramp',width:1600,height:1200});
  doc=createEntity(doc,'roads',{...base,name:'Main',roadClass:'highway',width:16,lanes:4,points:coords([100,600],[1500,600])});
  doc=createEntity(doc,'roads',{...base,name:'Ramp',roadClass:'onramp',width:8,lanes:1,points:coords([600,680],[800,600])});
  const restored=parseWorld(serializeWorld(doc));
  assert.equal(restored.roads[1].roadClass,'onramp');
  assert.ok(buildRoadJunctions(restored.roads).some(j=>j.kind==='merge'));
  const twoWay=updateEntity(restored,restored.roads[1].id,{lanes:2});
  assert.equal(parseWorld(serializeWorld(twoWay)).roads[1].lanes,2);
  assert.ok(!buildRoadJunctions(twoWay.roads).some(j=>j.kind==='merge'));
  assert.throws(()=>updateEntity(twoWay,twoWay.roads[1].id,{lanes:3}),/one or two lanes/);
});

test('existing branch end swaps connection mode without changing geometry',()=>{
  let doc=build(['Main','asphalt',coords([100,600],[1500,600]),16],
    ['Branch','asphalt',coords([800,600],[800,850]),8]);
  const branch=doc.roads[1];
  doc=updateEntity(doc,branch.id,{junctionStart:'merge'});
  assert.deepEqual(doc.roads[1].points,branch.points);
  assert.equal(doc.roads[1].lanes,branch.lanes);
  const restored=parseWorld(serializeWorld(doc));
  assert.equal(restored.roads[1].junctionStart,'merge');
  assert.ok(buildRoadJunctions(restored.roads).some(j=>j.kind==='merge'));
  doc=updateEntity(doc,branch.id,{junctionStart:'intersection'});
  assert.ok(!buildRoadJunctions(doc.roads).some(j=>j.kind==='merge'));
  doc=updateEntity(doc,branch.id,{junctionStart:'auto'});
  assert.equal(doc.roads[1].junctionStart,undefined);
});

test('metric lane paint follows directional lanes and ramp edges',()=>{
  const plan=roadMarkingPlan({...base,roadClass:'highway',width:18,lanes:4});
  assert.equal(plan.length,6);
  assert.deepEqual(plan.slice(0,2).map(p=>p.color),['#e5be65','#e5be65']);
  assert.deepEqual(plan.slice(2,4).map(p=>p.dash),[[3,9],[3,9]]);
  assert.ok(plan.every(p=>p.width===.15));
  const ramp=roadMarkingPlan({...base,roadClass:'onramp',width:8,lanes:1});
  assert.equal(ramp.length,2);
  assert.ok(ramp.every(p=>p.dash.length===0));
  assert.deepEqual(roadMarkingPlan({...base,roadClass:'alley'}),[]);
  assert.deepEqual(roadMarkingPlan({...base,markings:false}),[]);
});

test('equal-width lane changes create an uncontrolled continuation, not an intersection',()=>{
  let doc=createWorld({name:'Lane transition',width:1600,height:1200});
  doc=createEntity(doc,'roads',{...base,name:'Wide',roadClass:'highway',width:18,lanes:6,points:coords([100,600],[800,600])});
  doc=createEntity(doc,'roads',{...base,name:'Narrow reversed',roadClass:'highway',width:18,lanes:2,points:coords([1500,600],[800,600])});
  const junctions=buildRoadJunctions(doc.roads);
  assert.ok(junctions.some(j=>j.kind==='lane_transition'));
});


test('selected marker ranges follow the actual prompt and contract offer geometry',()=>{
  assert.deepEqual(markerInteractionRanges({type:'fuel'}),[12]);
  assert.deepEqual(markerInteractionRanges({type:'garage',properties:{radius_m:21}}),[21]);
  assert.deepEqual(markerInteractionRanges({type:'player_spawn'}),[]);
  const target={id:'target',type:'robbery_target'};
  const sources=[{type:'contract_contact',properties:{offers:[
    {robbery_marker_id:'target',arrival_radius_m:20},
    {robbery_marker_id:'target',arrival_radius_m:8},
    {robbery_marker_id:'other',arrival_radius_m:10}
  ]}}];
  assert.deepEqual(markerInteractionRanges(target,sources),[8,20]);
  assert.deepEqual(markerInteractionRanges({type:'contract_dropoff',id:'unused'},sources),[]);
});

test('Street entrances are priority connections, not equal-priority intersections',()=>{
  let doc=build(['Main','asphalt',coords([100,600],[1500,600]),20],
    ['Branch','asphalt',coords([800,600],[800,850]),8]);
  for(const roadClass of ['street','service']){
    doc=updateEntity(doc,doc.roads[1].id,{roadClass});
    const restored=parseWorld(serializeWorld(doc));
    const j=buildRoadJunctions(restored.roads).find(j=>near(j,{x:800,y:600}));
    assert.ok(j.street_access);
    assert.equal(j.corner_style,'square');
    assert.equal(j.approaches.find(a=>a.id===doc.roads[0].id).control,'none');
    assert.equal(j.approaches.find(a=>a.id===doc.roads[1].id).control,'stop');
  }
});
test('Square intersection mode survives a map roundtrip and is optional',()=>{
  let doc=build(['Main','asphalt',coords([100,600],[1500,600]),20],
    ['Branch','asphalt',coords([800,600],[800,850]),8]);
  const j=()=>buildRoadJunctions(doc.roads).find(j=>near(j,{x:800,y:600}));
  assert.equal(j().corner_style,undefined);
  doc=updateEntity(doc,doc.roads[1].id,{junctionStart:'square'});
  doc=parseWorld(serializeWorld(doc));
  assert.equal(j().corner_style,'square');
  doc=updateEntity(doc,doc.roads[1].id,{junctionStart:'auto',junctionStyle:'square'});
  assert.equal(j().corner_style,'square');
  doc=updateEntity(doc,doc.roads[1].id,{junctionStyle:'rounded'});
  assert.equal(j().corner_style,undefined);
});

test('road render plan is reused across unchanged views and rebuilt for an edited road',()=>{
  const doc=build(['Main','asphalt',coords([100,600],[1500,600]),20],
    ['Branch','asphalt',coords([800,600],[800,850]),8]);
  const plan=roadRenderPlan(doc.roads);
  assert.strictEqual(roadRenderPlan(doc.roads),plan);
  assert.strictEqual(plan.byId.get(doc.roads[0].id),doc.roads[0]);
  const edited=updateEntity(doc,doc.roads[0].id,{width:40,drawOrder:2});
  const next=roadRenderPlan(edited.roads);
  assert.notStrictEqual(next,plan);
  assert.equal(next.byId.get(doc.roads[0].id).width,40);
  assert.equal(next.roadBounds.get(doc.roads[0].id).minY,560);
  assert.equal(next.order.at(-1).id,doc.roads[0].id);
  assert.equal(plan.byId.get(doc.roads[0].id).width,20);
  assert.strictEqual(roadRenderPlan(doc.roads),plan,'undo can reuse the old plan');
});
