import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {parseWorld,serializeWorld} from '../world-model.js';
import {buildRoadNetwork} from '../world-export.js';

const source=readFileSync(new URL('../maps/compact-boroughs.world.json',import.meta.url),'utf8');

test('compact starter survives full browser import/export without losing native customMap',()=>{
  const map=parseWorld(source);
  assert.equal(map.format,'gdt.racing-world');
  assert.equal(map.version,2);
  assert.equal(map.customMap,true);
  assert.equal(map.world.width,960);
  assert.equal(map.world.height,720);
  assert.equal(map.roads.length,9);
  assert.equal(map.races.length,2);
  assert.equal(map.markers.filter(p=>p.type==='player_spawn').length,1);
  assert.ok(map.props.length>=300);
  const reloaded=parseWorld(serializeWorld(map));
  assert.deepEqual(reloaded,map);
});

test('dense preset roads form a valid traffic network',()=>{
  const map=parseWorld(source);
  const network=buildRoadNetwork(map);
  assert.equal(network.format,'gdt.racing-road-network');
  assert.equal(network.roads.length,9);
  assert.ok(network.junctions.length>=10);
});

test('guardrail remains independent of roads',()=>{
  const map=parseWorld(source);
  const rails=map.props.filter(p=>p.type==='guardrail');
  assert.equal(rails.length,1);
  assert.equal(rails[0].guardrailWidth,.65);
  assert.ok(rails[0].guardrailPoints.length>=2);
  assert.equal(map.roads.some(r=>r.id==='prop-'+rails[0].id),false);
});
