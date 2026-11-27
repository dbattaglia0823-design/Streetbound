import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {normalizeWorld,updateEntity} from '../world-model.js';
import {roadJumpPreview} from '../world-road-jump.js';
import {splitRoadAt} from '../world-road-topology.js';

const fixture=()=>normalizeWorld(JSON.parse(readFileSync(
  new URL('../../tests/fixtures/road-jumps.world.json',import.meta.url),'utf8')));

test('Jump authoring preserves the road and round-trips its landing strip',()=>{
  const doc=fixture(),road=doc.roads[0];
  assert.deepEqual(normalizeWorld(JSON.parse(JSON.stringify(doc))).roads[0],road);
  const preview=roadJumpPreview(road);
  assert.deepEqual(preview.lip,{x:200,y:400});
  assert.ok(preview.end>preview.start+10);
  const updated=updateEntity(doc,road.id,{jump:{...road.jump,reverse:true}});
  assert.equal(roadJumpPreview(updated.roads[0]).direction.x,-1);
  assert.deepEqual(road.points,updated.roads[0].points);
  const cleared=updateEntity(doc,road.id,{jump:undefined});
  assert.equal('jump' in cleared.roads[0],false);
});

test('A narrow runway, unsafe trajectory or split leaves the draft intact',()=>{
  const doc=fixture(),road=doc.roads[0];
  assert.throws(()=>updateEntity(doc,road.id,{width:6}),/clearance/);
  assert.throws(()=>updateEntity(doc,road.id,{jump:{...road.jump,landing_length_m:6}}),/Landing zone/);
  assert.throws(()=>splitRoadAt(doc,road.id,{x:300,y:400}),/Remove the jump/);
  assert.equal(road.jump.at_m,100);
});

test('standalone stunt ramp is independent of road geometry and survives round-trip',async()=>{
  const {parseWorld,serializeWorld,createEntity}=await import('../world-model.js');
  const {readFile}=await import('node:fs/promises');
  const map=parseWorld(await readFile(new URL('../../tests/fixtures/road-jumps.world.json',import.meta.url),'utf8'));
  const next=createEntity(map,'props',{name:'Stunt ramp',type:'stunt_ramp',x:350,y:320,rotation:90,scale:1,assetId:''});
  assert.deepEqual(next.roads,map.roads);
  assert.deepEqual(parseWorld(serializeWorld(next)).props.at(-1),next.props.at(-1));
});
