import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {convertMorrowWorld} from '../morrow-coast-bridge.js';
import {buildRuntimePreview,REPLACEABLE_KINDS,BASE_SIZE} from '../morrow-runtime-preview.js';
import {normalizeWorld} from '../world-model.js';

const file=name=>readFile(new URL(name,import.meta.url),'utf8');

test('runtime preview retains true baked intersection geometry and rules',()=>{
  const raw={
    format:'streetbound.streamed-world',version:1,size:[6400,4800],
    roads:[],terrain:[],props:[],
    junctions:[{roads:[0,1],p:[120,130],radius:22,control:'priority',
      polygon:[[100,120],[140,120],[140,140],[100,140]],
      approaches:[{road:0,control:'none'},{road:1,control:'stop'}],
      curbs:[[[100,120],[110,120]]]}]
  };
  const preview=buildRuntimePreview(raw);
  assert.equal(preview.junctions.length,1);
  assert.deepEqual(preview.junctions[0].roads,['road-0','road-1']);
  assert.deepEqual(preview.junctions[0].polygon[0],{x:100,y:120});
  assert.equal(preview.junctions[0].approaches[1].control,'stop');
  assert.equal(preview.junctions[0].curbs.length,1);
});

test('supported native game scenery can be adopted and validated',()=>{
  for(const [kind,type] of Object.entries(REPLACEABLE_KINDS)){
    assert.ok(BASE_SIZE[type],kind+' lacks a physical editor size');
    const doc=normalizeWorld({
      format:'gdt.racing-world',version:2,name:'Asset test',
      world:{width:1000,height:1000,seed:1,base:'grass'},
      roads:[],regions:[],markers:[],assets:[],
      props:[{id:'prop-1',name:kind,type,x:500,y:500,
        rotation:0,scale:1,assetId:'',replaces:{kind,seed:23,p:[500,500]}}]
    });
    assert.equal(doc.props[0].replaces.kind,kind);
  }
});

test('Save to Game uses the live project transaction, not browser-only storage',async()=>{
  const editor=await file('../world-editor.js');
  const server=await file('../../tools/map_editor_server.py');
  const renderer=await file('../world-renderer.js');
  assert.match(editor,/if\(isMorrowEdit\(doc\)&&liveSession&&loadedWorldSha\)/);
  assert.match(editor,/\$\('save-morrow'\)\.click\(\)/);
  assert.match(server,/def transactional_rebuild\(/);
  assert.match(server,/os\.replace\(tmp, EDIT\)/);
  assert.match(renderer,/options\?\.runtimePreview\?\.junctions/);
  assert.match(renderer,/j\.roads\.every\(unchanged\)/);
});

test('game preview does not overlay square intersection polygons or simplify ocean',async()=>{
  const renderer=await file('../world-renderer.js');
  const runtime=await file('../morrow-runtime-preview.js');
  const html=await file('../index.html');
  assert.match(renderer,/drawRuntimeTerrain\(ctx,options\.runtimePreview,doc,drawEdited\)/);
  assert.match(runtime,/sourceTerrain=\(raw\.terrain\|\|\[\]\)/);
  assert.match(runtime,/for\(const terrain of preview\.sourceTerrain\)/);
  assert.match(renderer,/exact saved junction pavement/i);\n  assert.match(renderer,/ctx\.clip\('evenodd'\)/);
  assert.doesNotMatch(renderer,/stroke\(ctx,j\.polygon,true\)/);
  assert.doesNotMatch(html,/id="export-png"/);
  assert.doesNotMatch(html,/>Guide<\/a>/);
});
