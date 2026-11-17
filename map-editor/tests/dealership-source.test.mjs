import test from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,normalizeWorld,parseWorld,serializeWorld} from '../world-model.js';

test('browser source editor preserves dealership locations and catalog ID lists',()=>{
  const world=createWorld({name:'Dealership test',width:6400,height:4800});
  world.dealerships=[
    {id:'budget',x:1200,y:3000,lot_width_m:36,lot_depth_m:22,
      inventory_mode:'manual',inventory:['test-car-a','test-car-b']},
    {id:'custom-dealer-1',name:'New showroom',tier:'USED VEHICLES',
      texture:'res://assets/Map Building Assets/Buildings/Dealerships/04_modern_dealership.png',
      x:3200,y:2400,lot_width_m:45,lot_depth_m:30,
      inventory_mode:'automatic',inventory:[]}
  ];
  assert.deepEqual(normalizeWorld(world).dealerships,world.dealerships);
  assert.deepEqual(parseWorld(serializeWorld(world)).dealerships,world.dealerships);
});

test('browser source rejects unsafe or impossible dealer definitions',()=>{
  const make=()=>createWorld({name:'Dealer validation',width:6400,height:4800});
  for(const dealers of [
    [{id:'budget',x:-1,y:10}],
    [{id:'budget',x:20}],
    [{id:'budget',lot_width_m:1}],
    [{id:'budget',lot_depth_m:600}],
    [{id:'budget',inventory:['duplicated','duplicated']}],
    [{id:'budget',inventory_mode:'all'}],
    [{id:'budget'},{id:'budget'}],
  ]){
    const world=make();
    world.dealerships=dealers;
    assert.throws(()=>normalizeWorld(world));
  }
});
