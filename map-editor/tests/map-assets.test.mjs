import test from 'node:test';
import assert from 'node:assert/strict';
import {setProjectAssets,projectAssets,projectArtwork,projectAssetPath} from '../world-project-assets.js';
import {createWorld,createEntity,serializeWorld,parseWorld,updateEntity} from '../world-model.js';

const id='project-'+'1'.repeat(24),second='project-'+'2'.repeat(24);
const sheet='Map Building Assets/Industrial/Pallets and Crates/cargo sheet.png';
const data=[
  {id,path:sheet,category:'Industrial',name:'Pallet',type:'prop',width:256,height:256,
    sprite:'pallet',region:[0,0,256,256],collision:'solid',size:[1.4,1.2]},
  {id:second,path:sheet,category:'Industrial',name:'Oil stain',type:'decal',
    width:256,height:256,sprite:'stain',region:[256,0,256,256],
    collision:'none',size:[2.8,2.8]}
];
test('recursive map folder path validation and classification',()=>{
  assert.ok(projectAssetPath(sheet));
  assert.ok(projectAssetPath('Buildings/House.png'));
  for(const bad of ['Map Building Assets/../x.png','Map Building Assets//a.png',
    'Map Building Assets\\Industrial\\x.png','vehicles/car.png','Map Building Assets/x.exe'])
    assert.equal(projectAssetPath(bad),false,bad);
});
test('sheet frames select and survive world export and missing library refresh',()=>{
  setProjectAssets(data);
  assert.equal(projectAssets().length,2);
  const doc=createEntity(createWorld({name:'Morrow'}),'props',{
    name:'Pallet',type:'prop',assetId:id,x:100,y:120,rotation:0,scale:1
  });
  const placed=doc.props[0];
  assert.equal(placed.assetPath,sheet);
  assert.equal(placed.assetSprite,'pallet');
  assert.deepEqual(placed.assetRegion,[0,0,256,256]);
  assert.deepEqual(placed.assetSize,[1.4,1.2]);
  assert.equal(placed.assetCollision,'solid');
  const updated=updateEntity(doc,placed.id,{assetId:second,type:'decal'});
  assert.equal(updated.props[0].assetCollision,'none');
  assert.deepEqual(updated.props[0].assetRegion,[256,0,256,256]);
  setProjectAssets([]);
  const reloaded=parseWorld(serializeWorld(updated));
  assert.deepEqual(reloaded.props,updated.props);
  assert.equal(projectArtwork(reloaded.props[0]).src.includes('cargo%20sheet.png'),true);
  setProjectAssets(data);
  assert.deepEqual(projectArtwork(reloaded.props[0]).region,[256,0,256,256]);
  setProjectAssets([]);
});
