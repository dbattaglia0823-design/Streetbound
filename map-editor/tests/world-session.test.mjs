import test from 'node:test';
import assert from 'node:assert/strict';
import {createWorld,serializeWorld} from '../world-model.js';
import {encodeSession,decodeSession,shouldRestoreSession} from '../world-session.js';

test('autosave roundtrip retains pending edits and the exact source revision',()=>{
  const doc=createWorld({name:'Morrow Coast',width:6400,height:4800});
  const restored=decodeSession(encodeSession(doc,{dirty:true,worldSha:'a'.repeat(64)}));
  assert.equal(serializeWorld(restored.doc),serializeWorld(doc));
  assert.equal(restored.dirty,true);
  assert.equal(restored.worldSha,'a'.repeat(64));
  assert.ok(shouldRestoreSession(restored,true),'connecting to game must not discard pending edits');
});
test('a clean game session reloads the current archive, while standalone saves reopen',()=>{
  for(const name of ['Morrow Coast','My track']){
    const saved=decodeSession(encodeSession(createWorld({name})));
    assert.equal(shouldRestoreSession(saved,true),name!=='Morrow Coast');
    assert.equal(shouldRestoreSession(saved,false),true);
  }
  assert.equal(shouldRestoreSession(null,true),false);
});
test('legacy drafts remain recoverable without inventing a current game revision',()=>{
  const restored=decodeSession(serializeWorld(createWorld({name:'Morrow Coast'})));
  assert.equal(restored.dirty,true);
  assert.equal(restored.worldSha,'');
  assert.ok(shouldRestoreSession(restored,true));
  assert.throws(()=>decodeSession('{broken'));
  assert.throws(()=>decodeSession('{"format":"streetbound.editor-session","version":99}'));
});
test('recovery preserves the map view, rejecting corrupt camera values',()=>{
  const doc=createWorld({name:'Track'}),view={x:840,y:700,zoom:.65};
  assert.deepEqual(decodeSession(encodeSession(doc,{view})).view,view);
  for(const invalid of [{x:0,y:0,zoom:0},{x:'bad',y:0,zoom:1},{x:0,y:0,zoom:999}])
    assert.equal(decodeSession(encodeSession(doc,{view:invalid})).view,null);
});
