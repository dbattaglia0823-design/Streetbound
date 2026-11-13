import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {convertMorrowWorld} from '../morrow-coast-bridge.js';
import {buildRuntimePreview,browseRuntimeAssets,pickRuntimeProp} from '../morrow-runtime-preview.js';
import {normalizeWorld} from '../world-model.js';

function fixture(){
  return {
    format:'streetbound.streamed-world',version:1,size:[6400,4800],
    roads:[{name:'Laurel',kind:'local',surface:'ASPHALT',width:10,lanes:2,
      anchors:[[100,100],[1000,100]],points:[[100,100],[1000,100]]}],
    terrain:[],spawn:{position:[260,200],rotation:0},pois:[],junctions:[],
    props:[
      {kind:'house',p:[275,210],size:[12,17],angle:0,seed:2},
      {kind:'tree',p:[291,219],size:[7,7],angle:0,seed:3},
      {kind:'garage',p:[282,240],size:[20,21],angle:0,seed:4,poi:'Main garage'},
      {kind:'rock',p:[480,500],size:[3,2.5],angle:0,seed:5},
      {kind:'tree',p:[305,250],size:[7,7],angle:0,seed:6,
        authoring_id:'prop-22',editor_type:'oak',editor_scale:1}
    ]
  };
}

test('existing baked scenery is browseable even when editable props count is zero',()=>{
  const raw=fixture();
  raw.props=raw.props.filter(p=>!p.authoring_id);
  const {doc}=convertMorrowWorld(raw);
  assert.equal(doc.props.length,0,'zero authoring records is legitimate');
  const preview=buildRuntimePreview(raw);
  const browser=browseRuntimeAssets(preview,doc);
  assert.equal(preview.propsCount,4);
  assert.equal(browser.total,4);
  assert.equal(browser.rows.length,4);
  assert.equal(browser.rows[0].source.kind,'house','assets nearest spawn come first');
  assert.equal(browser.rows.find(r=>r.source.kind==='garage').editable,false,
    'protected gameplay landmarks must not be adopted');
  assert.ok(browser.rows.find(r=>r.source.kind==='house').editable);
  assert.deepEqual(doc.props,[],'browser must not write 4 native props to edit overlay');
});

test('already editable or replaced game objects are not duplicated in the browser',()=>{
  const raw=fixture(),{doc}=convertMorrowWorld(raw);
  assert.equal(doc.props.length,1);
  const preview=buildRuntimePreview(raw);
  assert.equal(preview.authoredIds.has('prop-22'),true);
  const list=browseRuntimeAssets(preview,doc);
  assert.equal(list.total,5);
  assert.equal(list.rows.length,4,'baked editor-authored item already has one editable row');
  const moved=normalizeWorld({...doc,props:[...doc.props,{
    id:'prop-23',type:'house',name:'Moved house',x:300,y:225,
    rotation:0,scale:1,assetId:'',
    replaces:{kind:'house',seed:2,p:[275,210]}
  }]});
  const next=browseRuntimeAssets(preview,moved);
  assert.equal(next.rows.length,3,'original house suppressed while explicit override draws');
  assert.equal(pickRuntimeProp(preview,moved,{x:275,y:210},8),null);
  assert.equal(raw.props.length,5,'source is still untouched');
});

test('browse list stays bounded for large streamed maps and protected objects remain visible',()=>{
  const raw=fixture();
  raw.props=Array.from({length:4500},(_,i)=>({
    kind:i%3?'tree':'warehouse',p:[100+i%140*5,170+Math.floor(i/140)*6],
    size:i%3?[7,7]:[28,37],angle:0,seed:i+10
  }));
  const preview=buildRuntimePreview(raw);
  const {doc}=convertMorrowWorld(raw);
  const browser=browseRuntimeAssets(preview,doc,180);
  assert.equal(browser.total,4500);
  assert.equal(browser.rows.length,180);
  assert.ok(['tree','warehouse'].includes(browser.rows[0].source.kind));
  assert.equal(doc.props.length,0,'procedural 4500 never pollute editable source cap of 4000');
});

test('committed game world actually contains thousands of renderable scenery assets',async()=>{
  const raw=JSON.parse(await readFile(
    new URL('../../worlds/morrow-coast.world.json',import.meta.url),'utf8'));
  const preview=buildRuntimePreview(raw);
  const {doc,stats}=convertMorrowWorld(raw);
  assert.ok(preview.propsCount>1000,
    'the game archive lost its baked scenery: rebake before releasing');
  assert.equal(preview.propsCount,raw.props.length);
  assert.equal(stats.proceduralProps,raw.props.length);
  assert.ok(preview.assetBrowser.length>1000);
  const browser=browseRuntimeAssets(preview,doc,180);
  assert.equal(browser.rows.length,180);
  assert.ok(browser.rows.some(entry=>entry.editable),
    'the nearest 180 entries should expose at least one editable native asset');
});

test('editor initializes preview and visible count before drawing the large game world',async()=>{
  const editor=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  assert.match(editor,/browseRuntimeAssets\(runtimePreview,doc,(?:nativeRows|maxRows)\)/);
  assert.match(editor,/startWorld\(world,[\s\S]*?\{preview\}\)/);
  assert.match(editor,/setZoom\(Math\.max\(zoom,0\.65\)\)/);
  assert.match(editor,/if\(!Array\.isArray\(raw\.props\)\|\|!raw\.props\.length\)/);
  assert.match(html,/>Map assets<\/h2>/);
  assert.match(html,/>Game scenery & edits<\/option>/);
});
