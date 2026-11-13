import test from 'node:test';
import assert from 'node:assert/strict';
import {sampleRoad,distance} from '../world-geometry.js';
import {createWorld,createEntity,updateEntity,removeEntity,parseWorld,serializeWorld} from '../world-model.js';
import {buildRoadJunctions} from '../world-junctions.js';

const config={name:'Loop test',roadClass:'city',surface:'asphalt',
  width:36,lanes:2,shoulder:4,smooth:true,markings:true};
const p=(x,y)=>({x,y});
const ring=[p(200,200),p(400,200),p(400,400),p(200,400),p(200,200)];
function make(){
  let world=createWorld({width:1200,height:1000});
  world=createEntity(world,'roads',{...config,points:ring});
  return world;
}
test('closed road survives JSON roundtrip as one continuous road',()=>{
  const world=parseWorld(serializeWorld(make()));
  assert.equal(world.roads.length,1);
  assert.deepEqual(world.roads[0].points[0],world.roads[0].points.at(-1));
  const path=sampleRoad(world.roads[0].points,true,8);
  assert.ok(path.length>20);
  assert.ok(distance(path[0],path.at(-1))<1e-6);
  const inTangent={x:path[1].x-path[0].x,y:path[1].y-path[0].y};
  const outTangent={x:path.at(-1).x-path.at(-2).x,y:path.at(-1).y-path.at(-2).y};
  const dot=inTangent.x*outTangent.x+inTangent.y*outTangent.y;
  assert.ok(dot>0,'loop should have a continuous tangent at closure');
});
test('junctions are derived from current road geometry, not stale saved previews',()=>{
  let world=make();
  world=createEntity(world,'roads',{...config,name:'Crossing',smooth:false,
    points:[p(100,300),p(500,300)]});
  const ringId=world.roads[0].id,crossId=world.roads[1].id;
  assert.ok(buildRoadJunctions(world.roads).some(j=>j.roads.includes(ringId)&&j.roads.includes(crossId)));
  world=updateEntity(world,crossId,{points:[p(700,700),p(900,700)]});
  assert.equal(buildRoadJunctions(world.roads).length,0);
  world=removeEntity(world,crossId);
  assert.equal(buildRoadJunctions(world.roads).length,0);
});
