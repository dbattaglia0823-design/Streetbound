import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,normalizeWorld,serializeWorld,parseWorld} from '../world-model.js';
const race={id:'race-0',name:'City loop',mode:'circuit',laps:3,checkpoint_radius:16,start_radius:8,time_limit:0,
  points:[{x:100,y:100},{x:500,y:100},{x:500,y:500}]};
const configured={...race,formation:'single_file',player_start:{x:100,y:110,rotation:0},
  enemy_starts:[{x:100,y:120,rotation:0},{x:100,y:130,rotation:0}],
  opponent_pool:['audi-rs3','acura-integra'],reward_cash:12500,reward_player_xp:275,reward_car_xp:150};
test('Legacy native editor races survive browser normalization and save/load',()=>{
  const doc=normalizeWorld({...createWorld(),races:[race]});
  assert.deepEqual(parseWorld(serializeWorld(doc)).races,[race]);
});
test('Configured race pools, starting grids and payouts round-trip without loss',()=>{
  const doc=normalizeWorld({...createWorld(),races:[configured]});
  assert.deepEqual(parseWorld(serializeWorld(doc)).races,[configured]);
});
test('Invalid race geometry and settings are rejected',()=>{
  for(const changed of [{laps:1.5},{points:[{x:0,y:0},{x:1,y:1}]},
    {opponent_pool:['audi-rs3','audi-rs3']},{reward_cash:-1},
    {reward_player_xp:100001},{enemy_starts:Array(7).fill({x:100,y:100,rotation:0})}]){
    assert.throws(()=>normalizeWorld({...createWorld(),races:[{...configured,...changed}]}));
  }
  assert.throws(()=>normalizeWorld({...createWorld(),races:[race,race]}));
});
