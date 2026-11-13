import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const read=path=>readFile(new URL(path,import.meta.url),'utf8');
test('asset dock uses compact dimensions and keeps thumbnail labels visible',async()=>{
  const css=await read('../world-editor.css');
  assert.match(css,/\.asset-dock\{height:136px;flex-shrink:0\}/);
  assert.match(css,/\.asset-dock-card\{flex:0 0 88px;min-height:82px;height:82px/);
  assert.match(css,/\.asset-dock-name\{display:block;width:100%;max-width:80px;line-height:13px;height:13px/);
  assert.match(css,/\.asset-dock-scroller\{align-items:flex-start/);
  assert.match(css,/\.asset-dock-card small\{display:none\}/);
});
test('connected project map has a single visible save action while retaining project save handler',async()=>{
  const js=await read('../world-editor.js');
  assert.match(js,/\$\('save-morrow'\)\.hidden=true/);
  assert.match(js,/\$\('save-morrow'\)\.click\(\)/);
  assert.match(js,/\$\('save-world'\)\.textContent=isMorrowEdit\(doc\)&&liveSession\?'Save to Game':'Save'/);
});
