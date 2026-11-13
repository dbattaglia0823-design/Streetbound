import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {convertMorrowWorld} from '../morrow-coast-bridge.js';
import {buildRuntimePreview,REPLACEABLE_KINDS,BASE_SIZE} from '../morrow-runtime-preview.js';
import {normalizeWorld} from '../world-model.js';
import {drawWorld} from '../world-renderer.js';

const file=name=>readFile(new URL(name,import.meta.url),'utf8');

test('the actual game archive draws roads, baked junctions and scenery without canvas errors',async()=>{
  const raw=JSON.parse(await file('../../worlds/morrow-coast.world.json'));
  const {doc}=convertMorrowWorld(raw),preview=buildRuntimePreview(raw);
  const coordinates=[];
  const ctx=new Proxy({}, {get(target,key){
    if(key==='measureText')return ()=>({width:20});
    if(key==='createLinearGradient'||key==='createRadialGradient')return ()=>({addColorStop(){}});
    return target[key]??((...args)=>{
      for(const value of args)if(typeof value==='number')assert.ok(Number.isFinite(value),key+' received invalid coordinates');
      if(key==='moveTo')coordinates.push(args.slice(0,2));
    });
  }});
  assert.ok(preview.junctions.some(j=>j.polygon.length>=3));
  drawWorld(ctx,doc,{runtimePreview:preview,quality:1});
  const point=preview.junctions.find(j=>j.polygon.length>=3).polygon[0];
  assert.ok(coordinates.some(([x,y])=>x===point.x&&y===point.y),'baked junction polygon must actually reach the canvas');
});

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

test('game-map imports retain source layout versions and saved racing/traffic markers',async()=>{
  const raw=JSON.parse(await file('../../worlds/morrow-coast.world.json'));
  raw.editor_source_road_count=126;raw.editor_source_poi_count=18;
  raw.editor_markers=[{kind:'race_start',name:'My race',p:[2420,3035]},
    {kind:'traffic_spawn',name:'My traffic',p:[2500,3000]}];
  const {doc}=convertMorrowWorld(raw);
  assert.equal(doc.morrowSourceRoadCount,126);
  assert.equal(doc.morrowSourcePoiCount,18);
  assert.deepEqual(doc.markers.slice(-2).map(m=>[m.type,m.name,m.x,m.y]),
    [['race_start','My race',2420,3035],['traffic_spawn','My traffic',2500,3000]]);
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
  assert.match(renderer,/exact saved junction pavement/i);
  assert.match(renderer,/ctx\.clip\('evenodd'\)/);
  assert.doesNotMatch(renderer,/j\.polygon\.map\(\(\[x,y\]\)/);
  assert.doesNotMatch(html,/id="export-png"/);
  assert.doesNotMatch(html,/>Guide<\/a>/);
});
