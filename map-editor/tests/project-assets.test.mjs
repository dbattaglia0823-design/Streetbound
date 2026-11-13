import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setProjectAssets,projectAssets,projectArtwork,projectAssetPath} from '../world-project-assets.js';
import {createWorld,createEntity,parseWorld,serializeWorld,updateEntity} from '../world-model.js';
import {placementFootprint} from '../world-road-placement.js';
import {buildWorldZip} from '../world-export.js';
import {pickEditableScenery} from '../world-selection.js';

const id='project-'+'a'.repeat(24);
const asset={id,path:'Buildings/New Folder/Corner Shop.png',name:'Corner Shop',type:'building',width:800,height:400};
test('folder assets are discovered, removed and restored without changing placed objects',()=>{
  setProjectAssets([asset]);
  assert.equal(projectAssets().length,1);
  const world=createEntity(createWorld({name:'Test'}),'props',{
    type:'building',name:'Shop',x:500,y:500,rotation:45,scale:1,assetId:id});
  const prop=world.props[0];
  assert.equal(prop.assetPath,asset.path);
  assert.deepEqual(prop.assetSize,[22,11]);
  assert.ok(placementFootprint(world,prop)<14);
  assert.ok(pickEditableScenery(world.props,{x:500,y:500}));
  assert.equal(pickEditableScenery(world.props,{x:540,y:500}),null);
  setProjectAssets([]);
  const restored=parseWorld(serializeWorld(world));
  assert.deepEqual(restored.props,world.props);
  assert.match(projectArtwork(restored.props[0]).src,/New%20Folder\/Corner%20Shop.png/);
  setProjectAssets([asset,{...asset,id:'project-'+'b'.repeat(24),width:400,height:800}]);
  const changed=updateEntity(restored,prop.id,{assetId:'project-'+'b'.repeat(24)});
  assert.deepEqual(changed.props[0].assetSize,[14.5,29]);
  setProjectAssets([]);
});
test('project asset paths cannot escape the building folders',()=>{
  for(const path of ['../secret.png','Buildings/../secret.png','Buildings//a.png',
    'Buildings\\x.png','Buildings/a.exe','Buildings/http://x.svg','Buildings/a\u0000.png'])
    assert.equal(projectAssetPath(path),false,path);
  assert.ok(projectAssetPath(asset.path));
});
test('Godot ZIP includes the actual project artwork with spaces in its filename',async()=>{
  setProjectAssets([asset]);
  const doc=createEntity(createWorld({name:'Test'}),'props',{
    type:'building',name:'Shop',x:500,y:500,rotation:0,scale:1,assetId:id});
  const loader=await readFile(new URL('../world_loader.gd',import.meta.url),'utf8');
  const bytes=new Uint8Array([137,80,78,71]);
  const zip=buildWorldZip(doc,loader,new Map([['assets/'+asset.path,bytes]]));
  assert.equal(zip.files.get('assets/'+asset.path),bytes);
  assert.ok(zip.bytes.length>1000);
  setProjectAssets([]);
});
