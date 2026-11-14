import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,createEntity,parseWorld,serializeWorld,updateEntity} from '../world-model.js';
import {mountainPlan,isMountainBarrier} from '../world-mountain-barriers.js';
import {convertMorrowWorld} from '../morrow-coast-bridge.js';
const mountain={name:'West ridge',biome:'mountain',elevation:90,barrier:true,points:[{x:0,y:100},{x:80,y:100},{x:80,y:500},{x:0,y:500}]};
test('Solid mountain metadata survives normal save, load and source editing',()=>{
  let doc=createEntity(createWorld(),'regions',mountain);
  doc=parseWorld(serializeWorld(doc));assert.equal(doc.regions[0].barrier,true);assert.equal(doc.regions[0].elevation,90);
  const id=doc.regions[0].id;doc=updateEntity(doc,id,{elevation:140});assert.equal(doc.regions[0].elevation,140);
  doc=updateEntity(doc,id,{barrier:false});assert.equal(isMountainBarrier(doc.regions[0]),false);
});
test('Existing mountain terrain stays decorative until made solid',()=>{
  const region={...mountain,barrier:false};const doc=createEntity(createWorld(),'regions',region);
  assert.equal(doc.regions[0].barrier,undefined);
  assert.throws(()=>createEntity(createWorld(),'regions',{...mountain,biome:'grass'}),/mountain/i);
  assert.throws(()=>createEntity(createWorld(),'regions',{...mountain,elevation:0}),/height/i);
});
test('Mountain outline can close on the first point without duplicate collision vertices',()=>{
  const doc=createEntity(createWorld(),'regions',{...mountain,points:[...mountain.points,mountain.points[0]]});
  assert.equal(doc.regions[0].points.length,4);
  assert.throws(()=>createEntity(createWorld(),'regions',{...mountain,points:[{x:0,y:0},{x:100,y:100},{x:0,y:100},{x:100,y:0}]}));
});
test('Mountain preview has cached shaded facets and changes with height',()=>{
  const region={...mountain,id:'region-12'};const a=mountainPlan(region),b=mountainPlan(region);
  assert.equal(a.triangles,b.triangles);assert.ok(a.triangles.length>12);
  assert.ok(new Set(a.triangles.map(t=>t.color)).size>3);
  const moved=mountainPlan({...region,points:region.points.map(p=>({x:p.x+10,y:p.y+20}))});
  assert.equal(moved.triangles,a.triangles);
  assert.notEqual(mountainPlan({...region,elevation:180}).triangles,a.triangles);
});
test('Opening a saved game map preserves sparse mountain IDs, height and collision intent',()=>{
  const raw={format:'streetbound.streamed-world',version:1,size:[6400,4800],roads:[],terrain:[{kind:'mountain',color:'87917d',authoring_id:'region-200',barrier:true,elevation:90,points:mountain.points.map(p=>[p.x,p.y])}],
    spawn:{position:[1000,1000],rotation:0},pois:[]};
  const {doc}=convertMorrowWorld(raw);assert.equal(doc.regions[0].id,'region-200');assert.equal(doc.regions[0].barrier,true);assert.equal(doc.regions[0].elevation,90);
});
