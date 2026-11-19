import test from 'node:test';
import assert from 'node:assert/strict';
import {pickEditableScenery,pointInVisibleImageFootprint} from '../world-selection.js';
import {projectVisibleImageBounds} from '../world-renderer.js';

const connected=(id,x)=>({
  id,name:'Connected Building',type:'building',x,y:100,rotation:0,scale:1,
  assetId:'project-'+'a'.repeat(24),
  assetPath:'Map Building Assets/Buildings/ConnectedBuilding1.png',
  assetSize:[20,30]
});
const skinny=()=>({x:.44,y:.05,width:.12,height:.90});

test('connected building clicks do not include transparent width',()=>{
  const building=connected('prop-1',100);
  const props=[building];
  assert.equal(pickEditableScenery(props,{x:100,y:100},
    {gameArt:true,tolerance:8,visibleBoundsFor:skinny}),building);
  assert.equal(pickEditableScenery(props,{x:106,y:100},
    {gameArt:true,tolerance:8,visibleBoundsFor:skinny}),null,
    'the old 8 m padding must not extend thin roofs into their neighbors');
});

test('adjacent skinny buildings choose the correct visible roof even when full canvases overlap',()=>{
  const first=connected('prop-1',100);
  const second=connected('prop-2',108);
  const props=[first,second];
  const options={gameArt:true,tolerance:8,visibleBoundsFor:skinny};
  assert.equal(pickEditableScenery(props,{x:100,y:100},options),first);
  assert.equal(pickEditableScenery(props,{x:108,y:100},options),second);
  assert.equal(pickEditableScenery(props,{x:104,y:100},options),null);
});

test('selection preserves off-centre opaque bounds after rotation',()=>{
  const bounds={x:.68,y:.1,width:.12,height:.8};
  assert.equal(pointInVisibleImageFootprint({x:4.8,y:0},{x:0,y:0},
    [20,30],0,bounds,.1),true);
  assert.equal(pointInVisibleImageFootprint({x:0,y:4.8},{x:0,y:0},
    [20,30],Math.PI/2,bounds,.1),true);
  assert.equal(pointInVisibleImageFootprint({x:0,y:-4.8},{x:0,y:0},
    [20,30],Math.PI/2,bounds,.1),false);
});

test('other props retain existing selection tolerance and headless rendering fails safe',()=>{
  const tree={id:'prop-tree',type:'oak',x:100,y:100,scale:1,rotation:0};
  assert.equal(pickEditableScenery([tree],{x:105,y:100},
    {gameArt:true,tolerance:8}),tree);
  assert.equal(projectVisibleImageBounds({id:'none',src:'/test.png'}),null);
});
