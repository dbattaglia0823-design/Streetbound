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

test('cropped sheets are no longer available for placement',()=>{
  const item={id:'project-'+'c'.repeat(24),path:'Map Building Assets/Industrial/cargo.png',name:'Pallet',type:'industrial_prop',width:64,height:64,region:[0,0,64,64]};
  setProjectAssets([item]);
  assert.equal(projectAssets().length,0);
  assert.equal(projectArtwork({assetId:item.id,type:item.type,assetPath:item.path,assetSize:[2,2],assetRegion:item.region}),null);
  assert.equal(projectAssetPath('Map Building Assets/Sprite Sheets/cargo.png'),false);
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

test('individual nature artwork retains collision and footprint',()=>{
  const tree={id:'project-'+'e'.repeat(24),path:'Map Building Assets/Nature/Oak.svg',name:'Oak',type:'oak',width:128,height:128,worldSize:[8,8],collision:'none'};
  setProjectAssets([tree]);
  const doc=createEntity(createWorld(),'props',{type:'oak',x:300,y:300,rotation:0,scale:1,assetId:tree.id});
  const prop=parseWorld(serializeWorld(doc)).props[0];
  assert.equal(projectArtwork(prop).collision,'none');
  assert.deepEqual(prop.assetSize,[8,8]);
  assert.equal(prop.assetRegion,undefined);
  setProjectAssets([]);
});
