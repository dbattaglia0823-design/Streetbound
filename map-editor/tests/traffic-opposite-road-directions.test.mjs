import test from 'node:test';
import assert from 'node:assert/strict';
import {lanePatterns} from '../traffic-patterns.js';

const road=(id,points)=>({
  id,name:id,roadClass:'city',surface:'asphalt',width:12,lanes:2,
  shoulder:1,smooth:false,markings:true,points
});
const x=(x,y=300)=>({x,y});
const lane=(lanes,roadId,direction)=>lanes.find(p=>p.roadId===roadId&&p.direction===direction);

test('opposite authored point orders preserve the same physical right-hand traffic lanes at a join',()=>{
  const lanes=lanePatterns([
    road('east-drawn',[x(100),x(300)]),
    road('west-drawn',[x(500),x(300)])
  ]);
  assert.equal(lanes.length,4);
  const eastA=lane(lanes,'east-drawn',1);
  const eastB=lane(lanes,'west-drawn',-1);
  const westA=lane(lanes,'east-drawn',-1);
  const westB=lane(lanes,'west-drawn',1);
  assert.ok(eastA.points.every(p=>p.y>300));
  assert.ok(eastB.points.every(p=>p.y>300));
  assert.ok(westA.points.every(p=>p.y<300));
  assert.ok(westB.points.every(p=>p.y<300));
  assert.ok(Math.abs(eastA.points.at(-1).y-eastB.points[0].y)<1e-6);
});

test('traffic direction visualization uses travel arrows instead of authoring-order lane colors',async()=>{
  const {readFile}=await import('node:fs/promises');
  const source=await readFile(new URL('../traffic-patterns.js',import.meta.url),'utf8');
  assert.match(source,/ctx\.strokeStyle='#78e7fa99'/);
  assert.match(source,/ctx\.fillStyle='#b4f0fa'/);
});
