import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWorld,createEntity,parseWorld,serializeWorld} from '../world-model.js';
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
});
