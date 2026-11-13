import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=file=>readFile(new URL(file,import.meta.url),'utf8');

test('side panels no longer occupy map width; original controls remain mounted for reuse',async()=>{
  const [html,css]=await Promise.all([source('../index.html'),source('../world-editor.css')]);
  assert.match(html,/id="context-panel"/);
  assert.match(html,/id="context-body"/);
  assert.match(css,/\.world-workspace>\.left-panel,\.world-workspace>\.right-panel\{display:none!important\}/);
  assert.match(css,/\.world-workspace\{display:block;flex:1/);
  for(const id of ['road-width','biome','prop-type','marker-type','inspector','show-junctions','audit-run'])
    assert.ok(html.includes('id="'+id+'"'),id);
});

test('contextual panel reuses existing bound elements and retains access to essential tools',async()=>{
  const js=await source('../world-editor.js'),html=await source('../index.html');
  assert.match(js,/function relocateContext\(/);
  assert.match(js,/function restoreContext\(/);
  assert.match(js,/function renderContextPanel\(/);
  for(const view of ['auto','layers','objects','health','world'])
    assert.ok(html.includes('data-context-view="'+view+'"'),view);
  for(const view of ['road','terrain','prop','marker','selected','layers','health','objects'])
    assert.ok(js.includes("view==='"+view+"'"),view);
  assert.match(js,/renderContextPanel\(\);refreshAssetDock\(\);requestRender\(\)/);
  assert.match(js,/if\(key===contextKey\)return/);
});

test('context panel is collapsible and scrolls without interfering with map canvas',async()=>{
  const [html,css,js]=await Promise.all([source('../index.html'),source('../world-editor.css'),source('../world-editor.js')]);
  assert.match(html,/id="context-toggle"/);
  assert.match(css,/\.context-panel\{position:absolute/);
  assert.match(css,/\.context-body\{overflow:auto/);
  assert.match(js,/contextCollapsed=!contextCollapsed/);
  assert.match(html,/id="asset-dock"/);
});
