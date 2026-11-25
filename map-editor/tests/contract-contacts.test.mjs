import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,normalizeWorld,serializeWorld,parseWorld} from '../world-model.js';

const marker=(id,type,x,y,properties={})=>({
  id,type,name:id,x,y,rotation:0,properties
});
const robbery={
  id:'job_1',title:'Downtown Bank Pickup',kind:'robbery',difficulty:'pro',
  destination_marker_id:'marker-3',robbery_marker_id:'marker-2',
  cash:4200,player_xp:700,car_xp:400,underground_rep:15,
  wanted_level:3,time_limit_seconds:540,required_player_level:12,
  required_underground_rep:10,repeatable:false
};
const courier={
  id:'job_2',title:'Parts Delivery',kind:'courier',difficulty:'rookie',
  destination_marker_id:'marker-3',repeatable:true,cash:550
};
const source=()=>({...createWorld(),markers:[
  marker('marker-1','contract_contact',100,100,{
    contact_style:'business',description:'Talk to the dispatcher.',radius_m:18,
    offers:[robbery,courier]
  }),
  marker('marker-2','robbery_target',320,200),
  marker('marker-3','contract_dropoff',700,500)
]});

test('Named NPC contacts with multiple jobs round-trip through browser map export',()=>{
  const doc=source();
  const normalized=normalizeWorld(doc);
  assert.deepEqual(normalized.markers,doc.markers);
  assert.deepEqual(parseWorld(serializeWorld(normalized)).markers,doc.markers);
});
test('Contact can be placed before its first job is authored',()=>{
  const doc=source();
  doc.markers[0].properties.offers=[];
  assert.deepEqual(normalizeWorld(doc).markers[0].properties.offers,[]);
});
test('Robbery source and exit must reference real and distinct map markers',()=>{
  for(const diff of [
    {robbery_marker_id:'missing'},
    {destination_marker_id:'missing'},
    {robbery_marker_id:'marker-3'},
    {destination_marker_id:'marker-2'}
  ]){
    const doc=source();
    doc.markers[0].properties.offers[0]={...robbery,...diff};
    assert.throws(()=>normalizeWorld(doc));
  }
});
test('Contact limits job IDs, counts, categories, and numeric reward bounds',()=>{
  for(const diff of [
    {cash:999999},{player_xp:99999},{car_xp:99999},
    {underground_rep:40},{wanted_level:6},{time_limit_seconds:40},
    {required_player_level:0},{required_underground_rep:-1},
    {kind:'on_foot'},{difficulty:'unranked'},{title:''},{id:'invalid-id'}
  ]){
    const doc=source();
    doc.markers[0].properties.offers[0]={...robbery,...diff};
    assert.throws(()=>normalizeWorld(doc),JSON.stringify(diff));
  }
  const duplicate=source();
  duplicate.markers[0].properties.offers=[robbery,robbery];
  assert.throws(()=>normalizeWorld(duplicate));
  duplicate.markers[0].properties.offers=Array(9).fill(courier);
  assert.throws(()=>normalizeWorld(duplicate));
});
test('Mission targets too close to contact or escape cannot be published',()=>{
  const near=source();
  near.markers[1].x=115;near.markers[1].y=105;
  assert.throws(()=>normalizeWorld(near),/100m/i);
  const nearExit=source();
  nearExit.markers[2].x=330;nearExit.markers[2].y=210;
  assert.throws(()=>normalizeWorld(nearExit),/100m/i);
});
test('Legacy single job marker remains compatible with current marker schema',()=>{
  const doc=source();
  doc.markers.push(marker('marker-4','contract',400,400,{
    contract_kind:'courier',destination_marker_id:'marker-3'
  }));
  assert.equal(normalizeWorld(doc).markers.length,4);
});

test('Contact personality and bespoke job descriptions survive map save/reload',()=>{
  const doc=source();
  const npc=doc.markers[0].properties;
  npc.contact_role='PRIVATE FIXER';
  npc.contact_greeting='I only work with reliable drivers.';
  npc.contact_bio='Coordinates premium driving jobs around the marina.';
  npc.offers[0]={...npc.offers[0],description:'Stay in the car while the crew collects the money.'};
  const rebuilt=parseWorld(serializeWorld(normalizeWorld(doc)));
  assert.equal(rebuilt.markers[0].properties.contact_role,'PRIVATE FIXER');
  assert.equal(rebuilt.markers[0].properties.contact_greeting,'I only work with reliable drivers.');
  assert.equal(rebuilt.markers[0].properties.contact_bio,'Coordinates premium driving jobs around the marina.');
  assert.equal(rebuilt.markers[0].properties.offers[0].description,
    'Stay in the car while the crew collects the money.');
});
test('Oversized and invalid contact personality or briefing metadata are rejected',()=>{
  for(const [key,value] of [
    ['contact_role','x'.repeat(61)],['contact_greeting','x'.repeat(181)],
    ['contact_bio','x'.repeat(241)],['contact_role',12]
  ]){
    const doc=source();
    doc.markers[0].properties[key]=value;
    assert.throws(()=>normalizeWorld(doc),key);
  }
  for(const value of ['x'.repeat(401),123]){
    const doc=source();
    doc.markers[0].properties.offers[0]={...robbery,description:value};
    assert.throws(()=>normalizeWorld(doc));
  }
});
