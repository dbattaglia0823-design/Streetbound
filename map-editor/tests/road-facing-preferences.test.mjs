import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,normalizeWorld,serializeWorld,parseWorld} from '../world-model.js';
const house={id:'prop-house',name:'Corner house',type:'house',x:450,y:433,
  rotation:37,scale:1,assetId:'game-house',roadFacing:false,roadFront:270};
test('Per-building road alignment and artwork front survive browser save/load',()=>{
  const doc=normalizeWorld({...createWorld(),props:[house]});
  assert.deepEqual(parseWorld(serializeWorld(doc)).props[0],house);
});
test('Road-facing preferences reject malformed values without changing defaults',()=>{
  assert.throws(()=>normalizeWorld({...createWorld(),props:[{...house,roadFacing:'false'}]}));
  assert.throws(()=>normalizeWorld({...createWorld(),props:[{...house,roadFront:45}]}));
  const {roadFacing,roadFront,...old}=house;
  assert.equal(normalizeWorld({...createWorld(),props:[old]}).props[0].roadFacing,undefined);
});
