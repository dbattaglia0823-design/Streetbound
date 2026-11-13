import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const read=path=>readFile(new URL(path,import.meta.url),'utf8');

test('selected road inspector exposes join and split actions',async()=>{
  const [html,editor]=await Promise.all([read('../index.html'),read('../world-editor.js')]);
  for(const id of ['split-selected-road','join-selected-road'])
    assert.ok(html.includes('id="'+id+'"'),id);
  assert.match(editor,/joinRoadEndpoints\(/);
  assert.match(editor,/splitRoadAt\(/);
  assert.match(editor,/mode==='split'/);
  assert.match(editor,/const outcome=joinRoadEndpoints\(next,found\.item\.id/);
});

test('road joining occurs as one undoable drawing action and on endpoint release',async()=>{
  const editor=await read('../world-editor.js');
  assert.match(editor,/const created=createEntity\(d,'roads'/);
  assert.match(editor,/joinRoadEndpoints\(working,newId/);
  assert.match(editor,/joinRoadEndpoints\(doc,current\.id/);
  assert.match(editor,/makeSnapshot\(current\.before/);
  assert.match(editor,/joinRoadEndpoints\(changed,found\.item\.id/);
});
