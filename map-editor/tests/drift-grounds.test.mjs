import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseWorld,serializeWorld} from '../world-model.js';
import {buildRoadNetwork} from '../world-export.js';
import {sampleRoad,nearestOnPath} from '../world-geometry.js';

const content=readFileSync(new URL('../maps/drift-grounds.world.json',import.meta.url),'utf8');
const doc=parseWorld(content);

test('Drift Grounds starter stays an independent, editable Godot custom map',()=>{
  assert.equal(doc.format,'gdt.racing-world');
  assert.equal(doc.version,2);
  assert.equal(doc.customMap,true);
  assert.deepEqual(doc.world,{width:820,height:700,seed:48219,base:'city'});
  assert.equal(doc.roads.length,8);
  assert.equal(doc.races.length,3);
  assert.equal(doc.markers.filter(m=>m.type==='player_spawn').length,1);
  assert.deepEqual(parseWorld(serializeWorld(doc)),doc);
});

test('one tandem circuit, linked figure transitions, two donut practice circles',()=>{
  const names=doc.roads.map(r=>r.name);
  for(const wanted of ['Tandem Outer Circuit','Outer Drift Skidpad',
      'Inner Donut Ring','Training Link','Technical S Transitions',
      'Infield Reverse Transitions','Pit Lane']){
    assert.ok(names.includes(wanted),wanted);
  }
  assert.ok(doc.roads.filter(r=>r.roadClass==='track').length>=5);
  for(const title of ['Tandem Outer Circuit','Outer Drift Skidpad','Inner Donut Ring']){
    const r=doc.roads.find(r=>r.name===title);
    assert.deepEqual(r.points[0],r.points.at(-1));
    assert.ok(sampleRoad(r.points,r.smooth,9).length>r.points.length);
  }
});

test('browser road network covers all eight connected drift routes',()=>{
  const network=buildRoadNetwork(doc);
  assert.equal(network.format,'gdt.racing-road-network');
  assert.equal(network.roads.length,8);
  assert.ok(network.junctions.length>=4);
  assert.ok(network.connections.length>=7);
});

test('practice events and spawn are within actual drivable roads',()=>{
  const roadpaths=doc.roads.map(road=>({road,points:sampleRoad(road.points,road.smooth,6)}));
  for(const m of doc.markers.filter(m=>m.type==='player_spawn')){
    assert.ok(roadpaths.some(({road,points})=>nearestOnPath(m,points).distance<road.width/2-1));
  }
  for(const race of doc.races)for(const point of race.points){
    assert.ok(roadpaths.some(({road,points})=>nearestOnPath(point,points).distance<road.width/2),
      race.name+': '+JSON.stringify(point));
  }
  assert.ok(doc.races.some(r=>r.race_kind==='time_trial'));
  assert.ok(doc.races.some(r=>r.race_kind==='circuit'));
});

test('safety guardrails are editable paths with independently retained hitboxes',()=>{
  const barriers=doc.props.filter(p=>p.type==='guardrail');
  assert.equal(barriers.length,5);
  for(const p of barriers){
    assert.equal(p.assetId,'');
    assert.ok(p.guardrailPoints.length>=2);
    assert.equal(p.guardrailWidth,.65);
  }
  assert.ok(doc.props.some(p=>p.type==='garage'));
  assert.ok(doc.props.some(p=>p.type==='gas_station'));
});
