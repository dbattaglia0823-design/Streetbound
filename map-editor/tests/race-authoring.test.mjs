import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,normalizeWorld,serializeWorld,parseWorld} from '../world-model.js';
const race={id:'race-0',name:'City loop',mode:'circuit',laps:3,checkpoint_radius:16,start_radius:8,time_limit:0,
  points:[{x:100,y:100},{x:500,y:100},{x:500,y:500}]};
test('Native editor races survive browser normalization and save/load',()=>{
  const doc=normalizeWorld({...createWorld(),races:[race]});
  assert.deepEqual(parseWorld(serializeWorld(doc)).races,[race]);
});
test('Invalid race geometry and settings are rejected',()=>{
  assert.throws(()=>normalizeWorld({...createWorld(),races:[{...race,laps:1.5}]}));
  assert.throws(()=>normalizeWorld({...createWorld(),races:[{...race,points:[{x:0,y:0},{x:1,y:1}]}]}));
  assert.throws(()=>normalizeWorld({...createWorld(),races:[race,race]}));
});
