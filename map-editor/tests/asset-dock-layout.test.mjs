import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const read=path=>readFile(new URL(path,import.meta.url),'utf8');

test('world tools are located in persistent top dock rather than the scrolling left panel',async()=>{
  const html=await read('../index.html');
  const dock=html.indexOf('class="world-tool-dock"');
  const workspace=html.indexOf('class="world-workspace"');
  const toolbar=html.indexOf('class="tool-buttons"');
  assert.ok(dock>0&&dock<workspace);
  assert.ok(toolbar>dock&&toolbar<workspace);
  for(const tool of ['select','road','terrain','prop','marker','pan']){
    assert.match(html,new RegExp('data-tool="'+tool+'"'));
  }
});

test('bottom asset browser has category, search, scroll region and selection wiring',async()=>{
  const html=await read('../index.html'),js=await read('../world-editor.js');
  const workspaceEnd=html.indexOf('id="asset-dock"');
  assert.ok(workspaceEnd>html.indexOf('class="world-workspace"'));
  for(const id of ['asset-dock-category','asset-dock-search','asset-dock-scroller','asset-dock-collapse'])
    assert.ok(html.includes('id="'+id+'"'));
  assert.match(js,/function refreshAssetDock\(/);
  assert.match(js,/drawProp\(ctx,/);
  assert.match(js,/setTool\('prop'\);refreshAssetDock\(\)/);
  assert.match(js,/\$\('prop-asset'\)\.value=item\.assetId/);
  assert.match(js,/gdt-world-asset-ready/);
});

test('desktop dock remains scrollable and narrow screens keep world controls accessible',async()=>{
  const css=await read('../world-editor.css');
  assert.match(css,/\.asset-dock-scroller\{[^}]*overflow-x:auto/);
  assert.match(css,/\.world-tool-dock \.tool-buttons\{[^}]*overflow-x:auto/);
  assert.match(css,/@media\(max-width:690px\)/);
});
