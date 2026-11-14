import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,createEntity,serializeWorld,parseWorld,updateEntity} from '../world-model.js';
import {pickEditableScenery} from '../world-selection.js';

test('Adopted house dimensions and exact artwork survive edits and serialization',()=>{
  let doc=createEntity(createWorld(),'props',{type:'house',name:'House',x:200,y:200,scale:1,
    scaleX:2,scaleY:.5,rotation:0,assetId:'',assetSize:[20,30],
    replaces:{kind:'house',seed:9834,p:[200,200]},
    sourceAppearance:{kind:'house',seed:9834,size:[20,30],asset_kind:'coastal_house'}});
  const id=doc.props[0].id;
  doc=updateEntity(doc,id,{x:220});doc=parseWorld(serializeWorld(doc));
  assert.equal(doc.props[0].scaleX,2);assert.equal(doc.props[0].scaleY,.5);
  assert.deepEqual(doc.props[0].assetSize,[20,30]);
  assert.equal(doc.props[0].sourceAppearance.seed,9834);
  assert.equal(doc.props[0].sourceAppearance.asset_kind,'coastal_house');
  assert.equal(pickEditableScenery(doc.props,{x:239,y:200},{gameArt:true})?.id,id);
  assert.equal(pickEditableScenery(doc.props,{x:220,y:209},{gameArt:true}),null);
});
test('Independent road ends survive browser normalization and round trips',()=>{
  let doc=createEntity(createWorld(),'roads',{name:'Detached',roadClass:'city',surface:'asphalt',
    width:10,lanes:2,shoulder:2,points:[{x:100,y:100},{x:300,y:100}],independentEnds:true});
  doc=parseWorld(serializeWorld(doc));assert.equal(doc.roads[0].independentEnds,true);
});
