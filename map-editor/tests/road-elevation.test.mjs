import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {normalizeWorld,updateEntity} from '../world-model.js';
import {buildRoadJunctions} from '../world-junctions.js';
import {joinRoadEndpoints,splitRoadAt,applyPointElevations,pointElevationLayers,convertRoadToTunnel,roadStructure,setRoadStructure} from '../world-road-topology.js';

const fixture=()=>normalizeWorld(JSON.parse(readFileSync(
  new URL('../../tests/fixtures/road-elevation.world.json',import.meta.url),'utf8')));
const connects=(junctions,a,b)=>junctions.some(j=>j.roads.includes('road-'+a)&&j.roads.includes('road-'+b));

test('same-layer junctions and ramp mouths connect, stacked crossings stay separate',()=>{
  const doc=fixture(),junctions=buildRoadJunctions(doc.roads);
  for(const [a,b] of [[0,1],[0,2],[1,2],[1,8],[2,4],[2,8],[3,9]])
    assert.equal(connects(junctions,a,b),false,a+' and '+b);
  for(const [a,b] of [[0,6],[1,3],[1,4],[2,7],[4,5]])
    assert.equal(connects(junctions,a,b),true,a+' and '+b);
});

test('road profiles survive normalization and edits, with bounded ramps',()=>{
  const doc=fixture(),roundTrip=normalizeWorld(JSON.parse(JSON.stringify(doc)));
  assert.deepEqual(roundTrip.roads,doc.roads);
  assert.throws(()=>updateEntity(doc,'road-4',{points:[{x:500,y:600},{x:500,y:640}]}),/50 m/);
  assert.throws(()=>updateEntity(doc,'road-4',{elevation:{start_layer:-1,end_layer:1}}),/adjacent/);
  assert.throws(()=>splitRoadAt(doc,'road-4',{x:500,y:660}),/flat layer/);
  assert.equal(joinRoadEndpoints(doc,'road-2').joined,false);
  const ground=updateEntity(doc,'road-1',{elevation:{start_layer:0,end_layer:0}});
  assert.equal('elevation' in ground.roads[1],false);
});

test('on-ramp preview stays separate from stacked roads and preserves hot-swap mode',()=>{
  const doc=fixture();
  const ground={...doc.roads[0]};
  const deck={...doc.roads[1],points:[{x:700,y:250},{x:700,y:600}]};
  const ramp={...ground,id:'road-2',name:'Directional Ramp',roadClass:'onramp',
    lanes:1,width:8,points:[{x:520,y:480},{x:700,y:400}]};
  const authored=normalizeWorld({...doc,roads:[ground,deck,ramp]});
  const junctions=buildRoadJunctions(authored.roads);
  assert.ok(junctions.some(j=>j.kind==='merge'&&j.roads.includes(ground.id)&&j.roads.includes(ramp.id)));
  assert.equal(connects(junctions,0,1),false);
  assert.equal(connects(junctions,1,2),false);
  const changed=updateEntity(authored,ramp.id,{junctionEnd:'intersection'});
  assert.equal(changed.roads[2].junctionEnd,'intersection');
  assert.equal(buildRoadJunctions(changed.roads).some(j=>j.kind==='merge'),false);
});

test('point heights persist on a single source road without mutating the original',()=>{
  const doc=fixture();
  const points=[{x:100,y:700},{x:200,y:700},{x:300,y:700},{x:400,y:700},{x:500,y:700},{x:600,y:700}];
  const source=normalizeWorld({...doc,roads:[{...doc.roads[0],points}]});
  const before=JSON.stringify(source);
  assert.deepEqual(pointElevationLayers(source.roads[0]),[0,0,0,0,0,0]);
  const result=applyPointElevations(source,'road-0',[0,1,1,0,-1,-1]);
  assert.equal(JSON.stringify(source),before);
  assert.equal(result.roads.length,1);
  assert.equal(result.roads[0].id,'road-0');
  assert.deepEqual(result.roads[0].points,points);
  assert.deepEqual(pointElevationLayers(result.roads[0]),[0,1,1,0,-1,-1]);
  assert.deepEqual(normalizeWorld(JSON.parse(JSON.stringify(result))).roads,result.roads);
  assert.throws(()=>applyPointElevations(source,'road-0',[0,2,1,0,-1,-1]),/adjacent/);
  assert.throws(()=>applyPointElevations(source,'road-0',[0,1]),/every road point/);
  const short=updateEntity(source,'road-0',{points:[{x:100,y:700},{x:120,y:700}]});
  assert.throws(()=>applyPointElevations(short,'road-0',[0,1]),/50 m/);
});

test('race and contract objective elevations round trip independently',()=>{
  const source=fixture();
  const raw={...source,races:[{id:'race-grade',name:'Grade trial',mode:'sprint',
    points:[{x:500,y:400,road_layer:1},{x:500,y:450,road_layer:-1}]}],
    markers:[...source.markers,{id:'marker-grade',name:'Tunnel drop',type:'contract_dropoff',
      x:500,y:400,rotation:0,properties:{road_layer:-1}}]};
  const doc=normalizeWorld(raw);
  assert.deepEqual(doc.races[0].points.map(p=>p.road_layer),[1,-1]);
  assert.equal(doc.markers.at(-1).properties.road_layer,-1);
  assert.deepEqual(normalizeWorld(JSON.parse(JSON.stringify(doc))).races,doc.races);
  assert.throws(()=>updateEntity(doc,'marker-grade',{properties:{road_layer:2.5}}),/marker road layer/);
  assert.throws(()=>normalizeWorld({...raw,races:[{...raw.races[0],points:[{x:500,y:400,road_layer:true},{x:500,y:450}]}]}),/checkpoint road layer/);
});

test('authored height fields survive browser source round trips',()=>{
  const doc=fixture(),values=Array(129*129).fill(0);values[64*129+64]=125.5;
  const sculpted=normalizeWorld({...doc,terrainHeight:{size:129,values}});
  assert.deepEqual(normalizeWorld(JSON.parse(JSON.stringify(sculpted))).terrainHeight,{size:129,values});
  assert.throws(()=>normalizeWorld({...doc,terrainHeight:{size:129,values:[0]}}),/height field/);
  values[0]=1201;assert.throws(()=>normalizeWorld({...doc,terrainHeight:{size:129,values}}),/height field/);
});

test('named layers survive browser round trip and reject duplicate membership',()=>{
  const doc=fixture();
  const editorLayers=[{name:'Downtown',ids:['road-0'],visible:false,locked:true}];
  const result=normalizeWorld({...doc,editorLayers});
  assert.deepEqual(normalizeWorld(JSON.parse(JSON.stringify(result))).editorLayers,editorLayers);
  assert.throws(()=>normalizeWorld({...doc,editorLayers:[...editorLayers,{name:'Other',ids:['road-0'],visible:true,locked:false}]}),/layer member/);
});

test('whole-road tunnel conversion retains identity and creates two ground-level portals',()=>{
  const doc=fixture();
  const source=normalizeWorld({...doc,roads:[{...doc.roads[0],points:[{x:100,y:700},{x:500,y:700}]}]});
  const before=JSON.stringify(source);
  const result=convertRoadToTunnel(source,'road-0'),road=result.roads[0];
  assert.equal(JSON.stringify(source),before);
  assert.equal(result.roads.length,1);
  assert.equal(road.id,'road-0');
  assert.equal(road.lanes,source.roads[0].lanes);
  assert.deepEqual(road.elevation,{start_layer:0,end_layer:0,point_layers:[0,-1,-1,0]});
  assert.deepEqual(road.points,[{x:100,y:700},{x:175,y:700},{x:425,y:700},{x:500,y:700}]);
  assert.deepEqual(normalizeWorld(JSON.parse(JSON.stringify(result))).roads,result.roads);
  assert.throws(()=>convertRoadToTunnel(result,'road-0'),/Reset existing/);
  const short=updateEntity(source,'road-0',{points:[{x:100,y:700},{x:200,y:700}]});
  assert.throws(()=>convertRoadToTunnel(short,'road-0'),/110 m/);
  const curved=updateEntity(source,'road-0',{points:[{x:100,y:700},{x:200,y:700},{x:300,y:750},{x:500,y:750}]});
  const converted=convertRoadToTunnel(curved,'road-0').roads[0];
  assert.ok(curved.roads[0].points.every(p=>converted.points.some(q=>p.x===q.x&&p.y===q.y)));
  assert.deepEqual(converted.elevation.point_layers,[0,-1,-1,-1,-1,0]);
});


test('simple road structures derive heights and retain stable identity',()=>{
  const doc=fixture();
  const source=normalizeWorld({...doc,roads:[{...doc.roads[0],points:[{x:100,y:700},{x:500,y:700}]}]});
  const tunnel=setRoadStructure(source,'road-0','tunnel');
  assert.equal(roadStructure(tunnel.roads[0]),'tunnel');
  const bridge=setRoadStructure(tunnel,'road-0','overpass');
  assert.deepEqual(bridge.roads[0].points,tunnel.roads[0].points);
  assert.deepEqual(bridge.roads[0].elevation.point_layers,[0,1,1,0]);
  const room=setRoadStructure(source,'road-0','underground');
  assert.equal(roadStructure(room.roads[0]),'underground');
  assert.ok(room.roads[0].width>=36);
  assert.deepEqual(room.roads[0].elevation,{start_layer:-1,end_layer:-1});
  const regular=setRoadStructure(room,'road-0','regular');
  assert.equal(roadStructure(regular.roads[0]),'regular');
  assert.equal(regular.roads[0].id,source.roads[0].id);
  assert.equal(source.roads[0].elevation,undefined);
});


test('a tunnel approach automatically joins a previously authored underground area',()=>{
  const doc=fixture(),base=doc.roads[0];
  const source=normalizeWorld({...doc,roads:[
    {...base,id:'road-0',points:[{x:100,y:700},{x:500,y:700}]},
    {...base,id:'road-1',points:[{x:500,y:700},{x:750,y:700}]}
  ]});
  const area=setRoadStructure(source,'road-1','underground');
  const entrance=setRoadStructure(area,'road-0','tunnel');
  assert.deepEqual(entrance.roads[0].elevation,{start_layer:0,end_layer:-1});
  assert.equal(roadStructure(entrance.roads[0]),'tunnel');
});
