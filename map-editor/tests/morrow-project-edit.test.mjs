import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWorld,normalizeWorld,serializeWorld} from '../world-model.js';
import {convertMorrowWorld} from '../morrow-coast-bridge.js';
import {buildRuntimePreview,pickRuntimeProp,GAME_ART,BASE_SIZE} from '../morrow-runtime-preview.js';

function source(){
  return {format:'streetbound.streamed-world',version:1,size:[6400,4800],
    roads:[{id:0,name:'Laurel Avenue',kind:'local',surface:'ASPHALT',
      width:9,lanes:2,anchors:[[100,100],[1000,100]],points:[[100,100],[1000,100]]}],
    terrain:[{kind:'city',points:[[200,200],[1800,200],[1800,1200],[200,1200]],color:'b1b6a0'}],
    spawn:{position:[200,120],rotation:0},
    pois:[{name:'Laurel Motor House',category:'START / GARAGE',position:[200,120]}],
    props:[
      {kind:'tree',p:[410,420],size:[7,7],angle:0,seed:503,solid:true,radius:.5},
      {kind:'rock',p:[530,490],size:[3,2.5],angle:.1,seed:42,solid:true,radius:2},
      {kind:'garage',p:[250,260],size:[24,30],angle:0,seed:100,solid:true,
        poi:'Laurel Motor House'},
      {kind:'tree',p:[590,590],size:[7,7],angle:0,seed:13,solid:true,
        radius:.5,authoring_id:'prop-22',editor_type:'oak',editor_scale:1,
        asset_id:'game-pine',source_replacement:{kind:'tree',seed:11,p:[582,590]}}
    ],junctions:[]};
}
test('load current game world including procedural scenery and authorable source',()=>{
  const raw=source();
  const {doc,stats,raw:loaded}=convertMorrowWorld(raw);
  assert.equal(loaded,raw);
  assert.equal(stats.proceduralProps,4);
  assert.equal(doc.roads[0].points.length,2);
  assert.equal(doc.props[0].assetId,'game-pine');
  assert.deepEqual(doc.props[0].replaces,{kind:'tree',seed:11,p:[582,590]});
  assert.ok(GAME_ART.some(([id])=>id==='game-garage'));
});
test('spatial buckets locate native scenery but never adopt gameplay POI buildings',()=>{
  const raw=source(),preview=buildRuntimePreview(raw);
  const {doc}=convertMorrowWorld(raw);
  assert.equal(preview.propsCount,4);
  assert.equal(pickRuntimeProp(preview,doc,{x:410,y:420},20)?.kind,'tree');
  assert.equal(pickRuntimeProp(preview,doc,{x:250,y:260},20),null);
  assert.equal(pickRuntimeProp(preview,doc,{x:590,y:590},20),null);
  assert.equal(pickRuntimeProp(preview,doc,{x:530,y:490},20)?.kind,'rock');
});
test('adopted game artwork and original reference roundtrip through editor source',()=>{
  const src=createWorld({name:'Morrow Coast',width:6400,height:4800});
  const item={id:'prop-1',name:'Moved cedar',type:'oak',
    x:495,y:505,rotation:15,scale:1.3,assetId:'game-pine',
    replaces:{kind:'tree',seed:503,p:[410,420]},hidden:false};
  const doc=normalizeWorld({...src,props:[item]});
  const reread=normalizeWorld(JSON.parse(serializeWorld(doc)));
  assert.deepEqual(reread.props[0],doc.props[0]);
  assert.equal(reread.props[0].replaces.seed,503);
  assert.ok(BASE_SIZE.oak[0]>0);
  assert.throws(()=>normalizeWorld({...src,props:[{...item,assetId:'game-garage'}]}),
    /incompatible/);
  assert.throws(()=>normalizeWorld({...src,props:[{...item,replaces:{...item.replaces,seed:-1}}]}),
    /original game-object/);
  assert.equal(normalizeWorld({...src,props:[{...item,hidden:true}]}).props[0].hidden,true);
});
test('local live bridge, apply action and real asset library are wired to editor',async()=>{
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const editor=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  const api=await readFile(new URL('../../tools/map_editor_server.py',import.meta.url),'utf8');
  for(const id of ['load-morrow','save-morrow','adopt-game-prop','hide-game-prop','prop-asset'])
    assert.ok(html.includes('id="'+id+'"'));
  assert.ok(editor.includes("'/api/apply-morrow'"));
  assert.ok(editor.includes('buildRuntimePreview(raw)'));
  assert.ok(editor.includes('openGameMap({skipConfirm:true})'));
  assert.ok(api.includes('transactional_rebuild'));
  assert.ok(api.includes('subprocess.run'));
});
