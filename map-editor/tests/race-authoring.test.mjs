import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,normalizeWorld,serializeWorld,parseWorld} from '../world-model.js';
const race={id:'race-0',name:'City loop',mode:'circuit',laps:3,checkpoint_radius:16,start_radius:8,time_limit:0,
  points:[{x:100,y:100},{x:500,y:100},{x:500,y:500}]};
const configured={...race,race_kind:'circuit',formation:'single_file',player_start:{x:100,y:110,rotation:0},
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
test('Native configurable multiplayer prizes survive browser export and import',()=>{
  const custom={...configured,multiplayer_reward_custom:true,
    multiplayer_reward_cash:9600,multiplayer_reward_player_xp:2800,
    multiplayer_reward_car_xp:1600,multiplayer_reward_part_chance:25};
  const doc=normalizeWorld({...createWorld(),races:[custom]});
  assert.deepEqual(parseWorld(serializeWorld(doc)).races,[custom]);
  assert.equal(doc.races[0].reward_cash,12500,'Solo cash must stay separate');
  assert.equal(normalizeWorld({...createWorld(),races:[race]}).races[0].multiplayer_reward_custom,
    undefined,'Legacy races retain defaults');
});

test('Large multiplayer cash and XP rewards round-trip without an arbitrary cap',()=>{
  const high={...configured,multiplayer_reward_custom:true,
    multiplayer_reward_cash:250000000,multiplayer_reward_player_xp:2800000,
    multiplayer_reward_car_xp:1600000,multiplayer_reward_part_chance:25};
  assert.deepEqual(parseWorld(serializeWorld(normalizeWorld({...createWorld(),races:[high]}))).races[0],high);
  const exact={...high,multiplayer_reward_cash:Number.MAX_SAFE_INTEGER,
    multiplayer_reward_player_xp:Number.MAX_SAFE_INTEGER,
    multiplayer_reward_car_xp:Number.MAX_SAFE_INTEGER};
  assert.deepEqual(parseWorld(serializeWorld(normalizeWorld({...createWorld(),races:[exact]}))).races[0],exact);
});

test('Invalid custom multiplayer awards are rejected rather than imported',()=>{
  const custom={...configured,multiplayer_reward_custom:true,
    multiplayer_reward_cash:9600,multiplayer_reward_player_xp:2800,
    multiplayer_reward_car_xp:1600,multiplayer_reward_part_chance:25};
  for(const changed of [
    {multiplayer_reward_custom:'true'}, {multiplayer_reward_cash:Number.MAX_SAFE_INTEGER+1},
    {multiplayer_reward_cash:-1}, {multiplayer_reward_cash:1.5},
    {multiplayer_reward_player_xp:Number.MAX_SAFE_INTEGER+1},
    {multiplayer_reward_car_xp:Number.MAX_SAFE_INTEGER+1},
    {multiplayer_reward_part_chance:101}, {multiplayer_reward_part_chance:-1},
    {multiplayer_reward_part_chance:NaN}]){
    assert.throws(()=>normalizeWorld({...createWorld(),races:[{...custom,...changed}]}));
  }
  const missing={...custom};delete missing.multiplayer_reward_car_xp;
  assert.throws(()=>normalizeWorld({...createWorld(),races:[missing]}));
});

test('Invalid race geometry and settings are rejected',()=>{
  for(const changed of [{laps:1.5},{points:[{x:0,y:0},{x:1,y:1}]},
    {opponent_pool:['audi-rs3','audi-rs3']},{reward_cash:-1},
    {reward_player_xp:100001},{race_kind:'time_trial'},
    {enemy_starts:Array(7).fill({x:100,y:100,rotation:0})}]){
    assert.throws(()=>normalizeWorld({...createWorld(),races:[{...configured,...changed}]}));
  }
  assert.throws(()=>normalizeWorld({...createWorld(),races:[race,race]}));
});

test('Career categories, unlock rules and first-win rewards survive source serialization',()=>{
  const source={...createWorld(),races:[{...configured,category:'championship',difficulty:'elite',
    required_player_level:25,required_car_level:12,repeatable:false,
    prerequisite_races:[],required_vehicle_ids:['audi-rs3'],
    first_win_reward_cash:125000,first_win_reward_player_xp:7000,first_win_reward_car_xp:2000}]};
  const parsed=parseWorld(serializeWorld(source));
  assert.deepEqual(parsed.races[0],source.races[0]);
});
test('Career rejects missing, cyclic, and self prerequisites',()=>{
  const a={...race,id:'race-a',prerequisite_races:['race-b']};
  const b={...race,id:'race-b',prerequisite_races:['race-a']};
  assert.throws(()=>normalizeWorld({...createWorld(),races:[a,b]}),/cyclic/i);
  assert.throws(()=>normalizeWorld({...createWorld(),races:[a]}),/missing/i);
  assert.throws(()=>normalizeWorld({...createWorld(),races:[{...a,prerequisite_races:['race-a']}]}));
});
test('Mission, travel and dealership marker links round-trip; missing links are rejected',()=>{
  const doc={...createWorld(),races:[race],dealerships:[{id:'dealer-1',name:'Downtown Motors'}],
    markers:[{id:'marker-0',name:'Start',type:'player_spawn',x:100,y:100,rotation:0,properties:{}},
      {id:'marker-1',name:'Mission Start',type:'mission',x:120,y:120,rotation:0,
        properties:{race_id:'race-0',enabled:true,radius_m:12}},
      {id:'marker-2',name:'Fast travel',type:'fast_travel',x:200,y:200,rotation:0,
        properties:{required_race:'race-0'}},
      {id:'marker-3',name:'Dealer',type:'dealership',x:300,y:300,rotation:0,
        properties:{dealer_id:'dealer-1'}},
      {id:'marker-4',name:'Traffic',type:'traffic_spawn',x:400,y:400,rotation:0,
        properties:{traffic_weight:6}}]};
  assert.deepEqual(parseWorld(serializeWorld(doc)).markers,doc.markers);
  const invalid=structuredClone(doc);
  invalid.markers[1].properties.race_id='race-nothing';
  assert.throws(()=>normalizeWorld(invalid),/unknown race/i);
  invalid.markers[1].properties.race_id='race-0';
  invalid.markers[3].properties.dealer_id='dealer-nothing';
  assert.throws(()=>normalizeWorld(invalid),/unknown dealership/i);
});
