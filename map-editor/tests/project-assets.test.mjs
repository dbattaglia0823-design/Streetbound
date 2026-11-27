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

test('category assets and cropped sprites roundtrip with explicit collisions',()=>{
  const sheetId='project-'+'c'.repeat(24);
  const item={id:sheetId,path:'Map Building Assets/Industrial/cargo.png',
    name:'Pallet',type:'industrial_prop',width:64,height:64,
    region:[64,0,64,64],collision:'solid',worldSize:[2,1.5]};
  setProjectAssets([item]);
  const doc=createEntity(createWorld({name:'Warehouse'}),'props',{
    type:'industrial_prop',name:'Pallet',x:300,y:350,rotation:0,scale:1,assetId:sheetId});
  const prop=doc.props[0];
  assert.deepEqual(prop.assetRegion,[64,0,64,64]);
  assert.deepEqual(prop.assetSize,[2,1.5]);
  assert.equal(prop.assetCollision,'solid');
  const saved=parseWorld(serializeWorld(doc));
  setProjectAssets([]);
  assert.deepEqual(saved.props[0],prop);
  assert.deepEqual(projectArtwork(saved.props[0]).region,[64,0,64,64]);
  assert.ok(projectAssetPath(item.path));
});

test('ground decals remain collision-free in project metadata',()=>{
  const sheetId='project-'+'d'.repeat(24);
  setProjectAssets([{id:sheetId,path:'Map Building Assets/Ground Decals/oil.png',
    name:'Oil',type:'ground_decal',width:128,height:128,collision:'none'}]);
  const doc=createEntity(createWorld({name:'Streets'}),'props',{
    type:'ground_decal',name:'Oil',x:400,y:500,rotation:0,scale:1,assetId:sheetId});
  assert.equal(doc.props[0].assetCollision,'none');
  assert.equal(projectArtwork(doc.props[0]).collision,'none');
  setProjectAssets([]);
});

test('nature sprites from shared sheets keep crops and non-solid settings',()=>{
  const sheet='Map Building Assets/Test Fixtures/Synthetic Nature.png';
  const treeId='project-'+'e'.repeat(24),rockId='project-'+'f'.repeat(24);
  setProjectAssets([
    {id:treeId,path:sheet,name:'Tree',type:'oak',width:264,height:264,region:[322,0,264,264],worldSize:[8,8],collision:'none'},
    {id:rockId,path:sheet,name:'Rock',type:'rock',width:140,height:89,region:[8,723,140,89],worldSize:[2.2,1.399],collision:'solid'}
  ]);
  let doc=createEntity(createWorld(),'props',{type:'oak',x:300,y:300,rotation:0,scale:1,assetId:treeId});
  doc=createEntity(doc,'props',{type:'rock',x:350,y:300,rotation:20,scale:1,assetId:rockId});
  const saved=parseWorld(serializeWorld(doc));setProjectAssets([]);
  assert.equal(projectArtwork(saved.props[0]).collision,'none');
  assert.equal(projectArtwork(saved.props[1]).collision,'solid');
  assert.notDeepEqual(projectArtwork(saved.props[0]).region,projectArtwork(saved.props[1]).region);
  assert.equal(saved.props[0].assetPath,saved.props[1].assetPath);
});
