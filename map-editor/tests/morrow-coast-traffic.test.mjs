import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {convertMorrowWorld,isMorrowEdit,morrowEditText} from '../morrow-coast-bridge.js';
import {lanePatterns} from '../traffic-patterns.js';

const runtime=()=>({
  format:'streetbound.streamed-world',version:1,size:[6400,4800],
  roads:[
    {id:0,name:'Main',kind:'local',surface:'ASPHALT',width:10,lanes:2,
      anchors:[[100,600],[900,600]],points:[[100,600],[500,600],[900,600]]},
    {id:1,name:'Highway',kind:'highway',surface:'ASPHALT',width:18,lanes:4,
      anchors:[[500,200],[500,1000]],points:[[500,200],[500,1000]]},
    {id:2,name:'Gravel cutoff',kind:'gravel',surface:'GRAVEL',width:6,lanes:1,
      anchors:[[700,200],[700,1000]],points:[[700,200],[700,1000]]}
  ],
  terrain:[{kind:'ocean',color:'82b5b5',points:[[1000,100],[1400,100],[1400,1100],[1000,1100]]}],
  spawn:{position:[105,600],rotation:0},
  pois:[{name:'Garage',category:'START / GARAGE',position:[100,600]}],
  props:[{kind:'tree',p:[100,100]}],junctions:[{p:[500,600]}]
});

test('actual streamed Morrow roads convert to editable normalized stable-ID world',()=>{
  const {doc,stats}=convertMorrowWorld(runtime());
  assert.equal(doc.format,'gdt.racing-world');
  assert.equal(doc.version,2);
  assert.deepEqual(doc.world,{width:6400,height:4800,seed:28114,base:'grass'});
  assert.equal(doc.roads.length,3);
  assert.deepEqual(doc.roads.map(r=>r.id),['road-0','road-1','road-2']);
  assert.equal(doc.roads[0].points.length,2,'only authored anchors, not the baked route samples');
  assert.equal(doc.roads[2].surface,'gravel');
  assert.equal(doc.roads[1].lanes,4);
  assert.equal(stats.proceduralProps,1);
  assert.equal(doc.regions.length,1);
  assert.equal(doc.markers.length,2);
  assert.equal(doc.props.length,0,'regenerated props are not falsely editable');
  assert.equal(isMorrowEdit(doc),true);
  const edit=JSON.parse(morrowEditText(doc));
  assert.equal(edit.roads[0].id,'road-0');
});

test('reject non-Morrow data rather than overwriting another project',()=>{
  assert.throws(()=>convertMorrowWorld({format:'gdt.racing-world',version:2}),/Morrow Coast/);
  assert.throws(()=>morrowEditText({name:'Other',world:{width:6400,height:4800},roads:[]}),/Morrow Coast/);
});

test('lane preview follows actual right-hand travel direction and lane count',()=>{
  const {doc}=convertMorrowWorld(runtime());
  const all=lanePatterns(doc.roads);
  assert.equal(all.length,6,'local 2, highway 4, gravel excluded');
  const east=all.find(e=>e.roadId==='road-0'&&e.direction===1);
  const west=all.find(e=>e.roadId==='road-0'&&e.direction===-1);
  assert.ok(Math.abs(east.points[0].y-602.5)<0.1);
  assert.ok(Math.abs(west.points[0].y-597.5)<0.1);
  assert.ok(all.filter(e=>e.roadId==='road-1').length===4);
  assert.ok(all.every(e=>e.roadId!=='road-2'));
});

test('Morrow editor opens actual world reference via allowlisted local server',async()=>{
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const editor=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  const server=await readFile(new URL('../serve.ps1',import.meta.url),'utf8');
  assert.ok(html.includes('id="load-morrow"'));
  assert.ok(html.includes('id="save-morrow"'));
  assert.ok(html.includes('id="show-traffic"'));
  assert.ok(editor.includes('loadMorrowCoast()'));
  assert.ok(editor.includes('morrowEditText(doc)'));
  assert.ok(server.includes("worlds/morrow-coast.world.json"));
  assert.ok(server.includes('403 Forbidden'),'other parent paths are not exposed');
});


test('real committed Morrow Coast streams into editor without losing road IDs or control points',async()=>{
  const raw=JSON.parse(await readFile(new URL('../../worlds/morrow-coast.world.json',import.meta.url),'utf8'));
  const {doc,stats}=convertMorrowWorld(raw);
  assert.equal(doc.name,'Morrow Coast');
  assert.equal(doc.roads.length,raw.roads.length);
  assert.equal(stats.generatedJunctions,raw.junctions.length);
  assert.ok(doc.roads.length>50);
  assert.ok(doc.regions.length>5);
  assert.equal(doc.markers.length,raw.pois.length+1);
  for(let i=0;i<raw.roads.length;i++){
    assert.equal(doc.roads[i].id,'road-'+i);
    assert.deepEqual(doc.roads[i].points,raw.roads[i].anchors.map(([x,y])=>({x,y})));
  }
  const overlay=JSON.parse(morrowEditText(doc));
  assert.equal(overlay.roads.length,raw.roads.length);
  assert.ok(overlay.world.width===6400 && overlay.world.height===4800);
});
