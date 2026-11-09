import test from 'node:test';
import assert from 'node:assert/strict';
import {openMorrowWorld,buildMorrowPatch} from '../morrow-bridge.js';
import {createEntity,normalizeWorld} from '../world-model.js';

const original={
  format:'streetbound.streamed-world',version:1,name:'Morrow Coast',
  size:[6400,4800],roads:[
    {id:0,name:'Main Street',kind:'arterial',width:12,lanes:2,
      surface:'ASPHALT',anchors:[[400,400],[900,400],[1400,400]]},
    {id:1,name:'Dirt Byway',kind:'gravel',width:6,lanes:2,
      surface:'GRAVEL',anchors:[[950,200],[950,900]]}
  ]
};

test('Morrow production roads open as editor roads preserving stable identities and endpoints',()=>{
  const {doc,reference}=openMorrowWorld(original);
  assert.equal(doc.roads.length,2);
  assert.equal(doc.world.width,6400);
  assert.equal(doc.roads[0].id,'mc-road-0');
  assert.equal(doc.roads[0].roadClass,'city');
  assert.deepEqual(doc.roads[0].points[0],{x:400,y:400});
  assert.equal(doc.roads[1].surface,'gravel');
  const blank=buildMorrowPatch(doc,reference);
  assert.deepEqual(blank.updated_roads,[]);
  assert.deepEqual(blank.new_roads,[]);
});

test('altering arterial curvature and width preserves its special production road kind',()=>{
  const {doc,reference}=openMorrowWorld(original);
  const changed=normalizeWorld({...doc,roads:doc.roads.map(r=>
    r.id==='mc-road-0'?{...r,width:14,points:[
      {x:400,y:400},{x:800,y:360},{x:1200,y:390},{x:1400,y:400}]}:r)});
  const patch=buildMorrowPatch(changed,reference);
  assert.equal(patch.updated_roads.length,1);
  assert.equal(patch.updated_roads[0].kind,'arterial');
  assert.equal(patch.updated_roads[0].width,14);
  assert.equal(patch.updated_roads[0].anchors.length,4);
  assert.equal(original.roads[0].width,12);
});

test('removing a production road or moving shared endpoints cannot silently damage the bake',()=>{
  const {doc,reference}=openMorrowWorld(original);
  assert.throws(()=>buildMorrowPatch({...doc,roads:[doc.roads[0]]},reference),/removed/);
  const broken={...doc,roads:doc.roads.map(r=>
    r.id==='mc-road-0'?{...r,points:[{x:425,y:400},...r.points.slice(1)]}:r)};
  assert.throws(()=>buildMorrowPatch(broken,reference),/shared node/);
});

test('new roads export as additions without reassigning existing production IDs',()=>{
  const {doc,reference}=openMorrowWorld(original);
  const extended=createEntity(doc,'roads',{name:'New City Link',
    roadClass:'city',surface:'asphalt',width:10,lanes:2,
    shoulder:2,markings:true,smooth:true,
    points:[{x:600,y:400},{x:600,y:900}]});
  const patch=buildMorrowPatch(extended,reference);
  assert.equal(patch.new_roads.length,1);
  assert.equal(patch.new_roads[0].surface,'ASPHALT');
  assert.equal(patch.updated_roads.length,0);
});

test('reject truncated source instead of hiding production roads in editable preview',()=>{
  const tooMany={...original,roads:Array.from({length:181},(_,id)=>({...original.roads[0],id}))};
  assert.throws(()=>openMorrowWorld(tooMany),/180 roads/);
});

test('repository UI offers Morrow open and patch export and server only allowlists source',async()=>{
  const fs=await import('node:fs/promises');
  const files=['../index.html','../world-editor.js','../serve.ps1','../morrow-bridge.js'];
  const [html,editor,server]=await Promise.all(files.slice(0,3).map(p=>fs.readFile(new URL(p,import.meta.url),'utf8')));
  assert.ok(html.includes('id="open-morrow"'));
  assert.ok(html.includes('id="export-morrow-patch"'));
  assert.ok(editor.includes('buildMorrowPatch(doc,morrowReference)'));
  assert.ok(server.includes("$relative -eq '__morrow_coast__'"));
  assert.ok(server.includes('morrow-coast.world.json'));
});
