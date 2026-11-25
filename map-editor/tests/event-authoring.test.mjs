import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,normalizeWorld,parseWorld,serializeWorld} from '../world-model.js';
import {createOffer,duplicateOffer,moveOffer,presetOffer,offerWarnings,updateRaceSettings} from '../event-authoring.js';

const marker=(id,type,x,y)=>({id,name:id,type,x,y,rotation:0,properties:{}});
const contact=marker('marker-1','contract_contact',100,100);
const drop=marker('marker-2','contract_dropoff',450,200);
const target=marker('marker-3','robbery_target',300,100);
const markers=[contact,drop,target];
const race={id:'race-test',name:'Old race',mode:'circuit',laps:3,
  checkpoint_radius:16,start_radius:8,time_limit:0,
  points:[{x:100,y:100},{x:200,y:100},{x:200,y:200}],
  formation:'side_by_side',opponent_pool:['audi-rs3'],
  reward_cash:500,player_start:{x:100,y:100,rotation:0}};

test('New contracts receive valid target/dropoff and distinct permanent IDs',()=>{
  const first=createOffer([],'courier','marker-2');
  const second=createOffer([first],'robbery','marker-2','marker-3');
  assert.equal(first.id,'job_1');
  assert.equal(second.id,'job_2');
  assert.equal(second.robbery_hold_seconds,7);
  assert.equal(second.arrival_radius_m,12);
  assert.deepEqual(offerWarnings(contact,first,markers),[]);
  assert.deepEqual(offerWarnings(contact,second,markers),[]);
  assert.throws(()=>createOffer([],'robbery','marker-2'));
  assert.throws(()=>createOffer([],'courier',''));
});
test('Duplicate and reorder preserve other offers and never reuse original save ID',()=>{
  const first=createOffer([],'courier','marker-2');
  first.description='Custom words';
  const second=createOffer([first],'robbery','marker-2','marker-3');
  const copied=duplicateOffer([first,second],0);
  assert.equal(copied.length,3);
  assert.equal(copied[1].id,'job_3');
  assert.equal(copied[1].description,'Custom words');
  assert.equal(copied[0].id,'job_1');
  assert.equal(copied[2].id,'job_2');
  const moved=moveOffer(copied,1,1);
  assert.equal(moved.index,2);
  assert.deepEqual(moved.offers.map(o=>o.id),['job_1','job_2','job_3']);
  assert.equal(moveOffer(copied,0,-1).index,0);
  assert.throws(()=>duplicateOffer(Array(8).fill(first),0));
});
test('Difficulty presets change bounded payouts and level, not mission identity',()=>{
  const job=createOffer([],'robbery','marker-2','marker-3');
  job.title='Custom';
  job.description='Stay in car';
  const hardest=presetOffer(job,'elite');
  assert.equal(hardest.id,job.id);
  assert.equal(hardest.description,'Stay in car');
  assert.equal(hardest.destination_marker_id,job.destination_marker_id);
  assert.equal(hardest.cash,4625);
  assert.equal(hardest.required_player_level,40);
  assert.equal(hardest.wanted_level,5);
  assert.equal(job.difficulty,'rookie');
  assert.throws(()=>presetOffer(job,'legendary'));
});
test('Mission tuning validates on browser export and survives reload',()=>{
  const job={...createOffer([],'robbery','marker-2','marker-3'),
    title:'Custom Robbery',difficulty:'pro',arrival_radius_m:20,robbery_hold_seconds:15};
  const doc={...createWorld(),markers:[
    {...contact,properties:{contact_style:'street',offers:[job]}},drop,target]};
  const parsed=parseWorld(serializeWorld(normalizeWorld(doc)));
  assert.equal(parsed.markers[0].properties.offers[0].arrival_radius_m,20);
  assert.equal(parsed.markers[0].properties.offers[0].robbery_hold_seconds,15);
  for(const field of ['arrival_radius_m','robbery_hold_seconds']){
    const corrupted=structuredClone(doc);
    corrupted.markers[0].properties.offers[0][field]=999;
    assert.throws(()=>normalizeWorld(corrupted));
  }
});
test('Browser race quick edit preserves grid, route, car pool, original ID and reward bounds',()=>{
  const doc=normalizeWorld({...createWorld(),races:[race]});
  const edited=normalizeWorld(updateRaceSettings(doc,'race-test',{
    name:'Tournament Round',difficulty:'elite',category:'championship',
    reward_cash:30000,repeatable:false,required_player_level:30,
    first_win_reward_cash:10000,laps:5
  }));
  assert.equal(edited.races[0].name,'Tournament Round');
  assert.equal(edited.races[0].id,'race-test');
  assert.equal(edited.races[0].laps,5);
  assert.deepEqual(edited.races[0].points,race.points);
  assert.deepEqual(edited.races[0].opponent_pool,race.opponent_pool);
  assert.deepEqual(edited.races[0].player_start,race.player_start);
  assert.deepEqual(doc.races[0],race);
  assert.deepEqual(parseWorld(serializeWorld(edited)).races,edited.races);
  assert.throws(()=>normalizeWorld(updateRaceSettings(doc,'race-test',{reward_cash:1000001})));
  assert.throws(()=>updateRaceSettings(doc,'missing',{reward_cash:4}));
});
test('Race prerequisite edits reject cyclic and missing event links',()=>{
  const b={...race,id:'race-two',name:'Second Race'};
  const doc=normalizeWorld({...createWorld(),races:[race,b]});
  const linked=normalizeWorld(updateRaceSettings(doc,'race-two',{prerequisite_races:['race-test']}));
  assert.deepEqual(linked.races[1].prerequisite_races,['race-test']);
  assert.throws(()=>normalizeWorld(updateRaceSettings(linked,'race-test',{
    prerequisite_races:['race-two']
  })));
});
