import {test} from 'node:test';
import assert from 'node:assert/strict';
import {junctionFixtures,drawJunctionFixtures} from '../world-junction-fixtures.js';
import {readFileSync} from 'node:fs';
test('Every authored junction approach receives a neutral fixture without changing traffic data',()=>{
  const junctions=[{approaches:[{p:[10,20],direction:[1,0],width:10},{p:[20,10],direction:[0,1],width:12}]}];
  const original=JSON.stringify(junctions),fixtures=junctionFixtures(junctions);
  assert.equal(fixtures.length,2);assert.equal(JSON.stringify(junctions),original);
  assert.ok(fixtures.every(f=>!('phase' in f)&&!('state' in f)));
});
test('Fresh editor junctions also generate fixtures from road-relative tangents',()=>{
  const fixtures=junctionFixtures([{x:100,y:200,radius:15,approaches:[{tangent:{x:1,y:0},width:10},{tangent:{x:0,y:1},width:12}]}]);
  assert.equal(fixtures.length,4);assert.ok(fixtures.every(f=>Number.isFinite(f.p.x)&&Number.isFinite(f.p.y)));
});
test('A terminating branch gets no fixture on its nonexistent fourth arm',()=>{
  const roads=[{id:'main',points:[{x:-100,y:0},{x:100,y:0}]},
    {id:'branch',points:[{x:0,y:0},{x:0,y:100}]}];
  const j={x:0,y:0,radius:12,approaches:[{id:'main',tangent:{x:1,y:0},width:10},
    {id:'branch',tangent:{x:0,y:1},width:10}]};
  const fixtures=junctionFixtures([j],roads);
  assert.equal(fixtures.length,3);
  assert.ok(fixtures.every(f=>f.p.y>=0));
});
test('Every real map approach gets an unlit fixture on the incoming right-hand roadside',()=>{
  const data=JSON.parse(readFileSync(new URL('../../worlds/morrow-coast.world.json',import.meta.url)));
  const fixtures=junctionFixtures(data.junctions);
  assert.equal(fixtures.length,data.junctions.reduce((n,j)=>n+j.approaches.length,0));
  const positions=[],lensColors=[];
  const ctx={save(){},restore(){},translate(x,y){positions.push({x,y});},rotate(){},
    fillRect(){},beginPath(){},arc(){},fill(){lensColors.push(this.fillStyle);}};
  drawJunctionFixtures(ctx,data.junctions);
  assert.equal(lensColors.length,fixtures.length*3);
  assert.deepEqual([...new Set(lensColors)],['#101a1c']);
  for(let i=0;i<fixtures.length;i++){
    const {p,d,width}=fixtures[i],offset={x:positions[i].x-p.x,y:positions[i].y-p.y};
    const incomingRight={x:d.y,y:-d.x};
    assert.ok(offset.x*incomingRight.x+offset.y*incomingRight.y>width/2,
      'Fixture must stay outside the incoming lane');
  }
});
