import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {normalizeWorld,updateEntity} from '../world-model.js';
import {buildRoadJunctions} from '../world-junctions.js';
import {joinRoadEndpoints,splitRoadAt} from '../world-road-topology.js';

const fixture=()=>normalizeWorld(JSON.parse(readFileSync(
  new URL('../../tests/fixtures/road-elevation.world.json',import.meta.url),'utf8')));
const connects=(junctions,a,b)=>junctions.some(j=>j.roads.includes('road-'+a)&&j.roads.includes('road-'+b));

test('same-layer junctions and ramp mouths connect, stacked crossings stay separate',()=>{
  const doc=fixture(),junctions=buildRoadJunctions(doc.roads);
  for(const [a,b] of [[0,1],[0,2],[1,2],[1,8],[2,4],[2,8],[3,9]])
    assert.equal(connects(junctions,a,b),false,a+' and '+b);
  for(const [a,b] of [[0,6],[1,3],[1,4],[2,7],[4,5]])
    assert.equal(connects(junctions,a,b),true,a+' and '+b);
});

test('road profiles survive normalization and edits, with bounded ramps',()=>{
  const doc=fixture(),roundTrip=normalizeWorld(JSON.parse(JSON.stringify(doc)));
  assert.deepEqual(roundTrip.roads,doc.roads);
  assert.throws(()=>updateEntity(doc,'road-4',{points:[{x:500,y:600},{x:500,y:640}]}),/50 m/);
  assert.throws(()=>updateEntity(doc,'road-4',{elevation:{start_layer:-1,end_layer:1}}),/adjacent/);
  assert.throws(()=>splitRoadAt(doc,'road-4',{x:500,y:660}),/flat layer/);
  assert.equal(joinRoadEndpoints(doc,'road-2').joined,false);
  const ground=updateEntity(doc,'road-1',{elevation:{start_layer:0,end_layer:0}});
  assert.equal('elevation' in ground.roads[1],false);
});
