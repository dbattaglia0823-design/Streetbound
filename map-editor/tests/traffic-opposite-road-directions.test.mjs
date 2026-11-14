import test from 'node:test';
import assert from 'node:assert/strict';
import {lanePatterns} from '../traffic-patterns.js';

const road=(id,points)=>({
  id,name:id,roadClass:'city',surface:'asphalt',width:12,lanes:2,
  shoulder:1,smooth:false,markings:true,points
});
const x=(x,y=300)=>({x,y});
const lane=(lanes,roadId,direction)=>lanes.find(p=>p.roadId===roadId&&p.direction===direction);

test('single and odd lane counts keep every traffic lane inside the road edges',()=>{
  for(const count of [1,3,5]){
    const lanes=lanePatterns([{...road('odd',[x(100),x(500)]),width:18,lanes:count}]);
    assert.equal(lanes.length,Math.max(2,count));
    for(const lane of lanes)for(const p of lane.points)assert.ok(Math.abs(p.y-300)<9);
    const centers=lanes.map(l=>l.points[0].y).sort((a,b)=>a-b);
    assert.equal(new Set(centers).size,centers.length);
  }
});

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

test('editor previews keep right in every compass direction on two, four and six lane roads',()=>{
  for(const [start,end,right] of [
    [x(100),x(500),{x:0,y:1}], [x(500),x(100),{x:0,y:-1}],
    [x(300,100),x(300,500),{x:-1,y:0}], [x(300,500),x(300,100),{x:1,y:0}]
  ])for(const count of [2,4,6]){
    const lanes=lanePatterns([{...road('test',[start,end]),width:18,lanes:count}]);
    assert.equal(lanes.length,count);
    for(const lane of lanes)for(const point of lane.points){
      const side=((point.x-start.x)*right.x+(point.y-start.y)*right.y)*lane.direction;
      assert.ok(Math.abs(side-18/count*(lane.lane+.5))<1e-6);
    }
  }
});
