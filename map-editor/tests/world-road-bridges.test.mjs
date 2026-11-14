import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {WaterMask,buildBridgeSpans,bridgesForDocument,bridgeRailPieces} from '../world-road-bridges.js';
const cases=JSON.parse(readFileSync(new URL('../../tests/fixtures/road_bridges.json',import.meta.url)));
for(const c of cases)test('Automatic bridge: '+c.name,()=>{
  const mask=new WaterMask(c.terrain),path=c.path.map(([x,y])=>({x,y})),wet=mask.intervals(path);
  assert.equal(wet.length,c.wet.length);
  wet.forEach((span,i)=>span.forEach((value,j)=>assert.ok(Math.abs(value-c.wet[i][j])<1e-4)));
  const spans=buildBridgeSpans([{id:0,points:path,width:10,kind:'rural'}],c.terrain);
  assert.equal(spans.length,wet.length);
  assert.ok(spans.every(span=>span.points.length>=2&&span.start>=0&&span.end>span.start));
});
test('Editor bridges regenerate after roads and terrain move, and reuse unchanged plans',()=>{
  const road={id:'road-0',roadClass:'country',width:10,surface:'asphalt',smooth:false,points:[{x:0,y:0},{x:100,y:0}]};
  const region={id:'region-0',biome:'lake',points:[{x:49,y:-5},{x:51,y:-5},{x:51,y:5},{x:49,y:5}]};
  const doc={roads:[road],regions:[region]};
  const first=bridgesForDocument(doc);
  assert.equal(first.length,1);assert.equal(first,bridgesForDocument(doc));
  const moved={...doc,roads:[{...road,points:road.points.map(p=>({...p,y:100}))}]};
  assert.equal(bridgesForDocument(moved).length,0);
  assert.equal(bridgesForDocument({...doc,regions:[{...region,biome:'grass'}]}).length,0);
});
test('Bridge rails leave a crossing road mouth open',()=>{
  const bridge={points:[{x:0,y:0},{x:100,y:0}],width:10,kind:'rural'};
  const junction={polygon:[{x:40,y:-20},{x:60,y:-20},{x:60,y:20},{x:40,y:20}]};
  const pieces=bridgeRailPieces(bridge,[junction]);
  assert.equal(pieces.length,4);
  assert.ok(pieces.every(piece=>piece.points[1].x<=40||piece.points[0].x>=60));
});
