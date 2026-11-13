import test from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,createEntity,parseWorld,serializeWorld} from '../world-model.js';
import {joinRoadEndpoints,splitRoadAt} from '../world-road-topology.js';

const point=(x,y)=>({x,y});
const attrs={roadClass:'city',surface:'asphalt',width:36,shoulder:4,
  lanes:2,smooth:false,markings:true};
function world(...roads){
  let doc=createWorld({width:1600,height:1200});
  for(const road of roads)
    doc=createEntity(doc,'roads',{...attrs,name:road.name||'Street',...road});
  return doc;
}

test('two independent roads merge into a single road regardless of authoring direction',()=>{
  const old=world(
    {points:[point(100,250),point(300,250)]},
    {points:[point(550,250),point(300,250)]}
  );
  const id=old.roads[0].id;
  const result=joinRoadEndpoints(old,id);
  assert.equal(result.joined,true);
  assert.equal(result.doc.roads.length,1);
  assert.equal(result.doc.roads[0].id,id);
  assert.deepEqual(result.doc.roads[0].points,
    [point(100,250),point(300,250),point(550,250)]);
  assert.equal(old.roads.length,2,'undo source is unchanged');
  assert.deepEqual(parseWorld(serializeWorld(result.doc)),result.doc);
});

test('a connector with two endpoint joins can combine three roads in one sequence',()=>{
  const source=world(
    {points:[point(100,250),point(300,250)]},
    {points:[point(550,250),point(750,250)]},
    {points:[point(300,250),point(550,250)]}
  );
  const connector=source.roads[2].id;
  const first=joinRoadEndpoints(source,connector);
  assert.equal(first.joined,true);
  const second=joinRoadEndpoints(first.doc,connector);
  assert.equal(second.joined,true);
  assert.equal(second.doc.roads.length,1);
  assert.equal(second.doc.roads[0].points.length,4);
});

test('roads joined at both ends form one closed loop',()=>{
  const input=world(
    {points:[point(200,200),point(400,200),point(400,400)]},
    {points:[point(200,200),point(200,400),point(400,400)]}
  );
  const result=joinRoadEndpoints(input,input.roads[0].id);
  assert.equal(result.joined,true);
  assert.equal(result.doc.roads.length,1);
  assert.deepEqual(result.doc.roads[0].points[0],result.doc.roads[0].points.at(-1));
});

test('T junction endpoints and incompatible roads remain separate',()=>{
  const tee=world(
    {points:[point(100,250),point(300,250)]},
    {points:[point(300,250),point(550,250)]},
    {points:[point(300,250),point(300,450)]}
  );
  assert.equal(joinRoadEndpoints(tee,tee.roads[0].id).joined,false);
  const mismatch=world(
    {points:[point(100,250),point(300,250)]},
    {surface:'gravel',points:[point(300,250),point(550,250)]}
  );
  assert.equal(joinRoadEndpoints(mismatch,mismatch.roads[0].id).joined,false);
});

test('snap gap produces one shared coordinate and no duplicate seam point',()=>{
  const source=world(
    {points:[point(100,250),point(300,250)]},
    {points:[point(306,250),point(550,250)]}
  );
  const result=joinRoadEndpoints(source,source.roads[0].id,{radius:8});
  assert.equal(result.joined,true);
  assert.deepEqual(result.doc.roads[0].points,
    [point(100,250),point(300,250),point(550,250)]);
});

test('split existing interior control point preserves editable halves and IDs',()=>{
  const source=world({points:[point(100,250),point(300,250),point(550,250)]});
  const id=source.roads[0].id;
  const result=splitRoadAt(source,id,1);
  assert.equal(result.doc.roads.length,2);
  assert.equal(result.doc.roads[0].id,id);
  assert.notEqual(result.newRoadId,id);
  assert.deepEqual(result.doc.roads[0].points.at(-1),result.doc.roads[1].points[0]);
  assert.deepEqual(source.roads[0].points,[point(100,250),point(300,250),point(550,250)]);
  assert.deepEqual(parseWorld(serializeWorld(result.doc)),result.doc);
});

test('click anywhere along a segment to split and rejoin independently',()=>{
  const source=world({points:[point(100,250),point(550,250)]});
  const id=source.roads[0].id;
  const result=splitRoadAt(source,id,point(360,253),{maxDistance:10});
  assert.equal(result.doc.roads.length,2);
  assert.deepEqual(result.point,point(360,250));
  const joined=joinRoadEndpoints(result.doc,id);
  assert.equal(joined.joined,true);
  assert.equal(joined.doc.roads.length,1);
});

test('splitting at terminal point or off-road point is rejected',()=>{
  const source=world({points:[point(100,250),point(550,250)]});
  assert.throws(()=>splitRoadAt(source,source.roads[0].id,0),/interior/);
  assert.throws(()=>splitRoadAt(source,source.roads[0].id,point(360,500),{maxDistance:10}),/Click on/);
});
