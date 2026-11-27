import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,createEntity,parseWorld,serializeWorld} from '../world-model.js';

const rail={
  type:'guardrail',name:'Steel rail',x:300,y:400,rotation:0,scale:1,
  assetId:'',assetSize:[150.65,50.65],guardrailWidth:.65,
  guardrailPoints:[[-75,-25],[0,-25],[75,25]]
};

test('Guardrail is an editable solid path prop, not a traffic road',()=>{
  const doc=createEntity(createWorld({width:1000,height:800}),'props',rail);
  const saved=parseWorld(serializeWorld(doc));
  assert.equal(saved.roads.length,0);
  assert.equal(saved.props.length,1);
  assert.equal(saved.props[0].type,'guardrail');
  assert.deepEqual(saved.props[0].guardrailPoints,rail.guardrailPoints);
  assert.equal(saved.props[0].guardrailWidth,.65);
  assert.deepEqual(saved.props[0].assetSize,rail.assetSize);
});

test('Guardrail geometry and width are bounded',()=>{
  const world=createWorld({width:1000,height:800});
  for(const patch of [
    {guardrailWidth:3},{guardrailWidth:.2},
    {guardrailPoints:[[0,0]]},
    {guardrailPoints:[[0,0],[.1,.1]]},
    {guardrailPoints:[[0,0],[2000,0]]},
    {x:1,guardrailPoints:[[-75,-25],[75,25]]},
  ]){
    assert.throws(()=>createEntity(world,'props',{...rail,...patch}));
  }
});

test('Road-linked guardrail side intervals round-trip, reject invalid ranges',()=>{
  const doc=createWorld({width:1000,height:800});
  doc.roads.push({id:'road-0',name:'Fixture road',roadClass:'city',surface:'asphalt',width:10,lanes:2,shoulder:2,smooth:true,markings:true,points:[{x:100,y:300},{x:800,y:300}],autoGuardrails:{left:[10,80],right:[0,25]}});
  const saved=parseWorld(serializeWorld(doc));
  assert.deepEqual(saved.roads[0].autoGuardrails,doc.roads[0].autoGuardrails);
  assert.equal(saved.props.length,0);
  for(const rails of [{left:[80,10]},{right:[0,101]},{middle:[0,100]}]){
    const invalid=structuredClone(doc);invalid.roads[0].autoGuardrails=rails;
    assert.throws(()=>parseWorld(JSON.stringify(invalid)));
  }
});
