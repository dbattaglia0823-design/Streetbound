import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,createEntity,parseWorld,serializeWorld} from '../world-model.js';
test('Sidewalk paths survive browser source normalization without becoming traffic roads',()=>{
  let doc=createEntity(createWorld(),'props',{type:'sidewalk',name:'Walk',x:500,y:500,rotation:0,scale:1,assetId:'',assetSize:[203,103],sidewalkWidth:3,sidewalkPoints:[[-100,-50],[100,-50],[100,50]]});
  doc=parseWorld(serializeWorld(doc));assert.equal(doc.roads.length,0);
  assert.equal(doc.props[0].sidewalkPoints.length,3);assert.equal(doc.props[0].sidewalkWidth,3);
  assert.deepEqual(doc.props[0].assetSize,[203,103]);
});
