import test from 'node:test';
import assert from 'node:assert/strict';
import {terrainFamily,TERRAIN_COLORS,textureTerrain,TERRAIN_TILE_PIXELS,TERRAIN_REPEAT_M,HILL_REPEAT_M,hillLight} from '../world-terrain-materials.js';

test('terrain families preserve water/shoreline aliases and distinguish land materials',()=>{
  assert.equal(terrainFamily('water'),'lake');
  assert.equal(terrainFamily('riverbank'),'foam');
  assert.equal(terrainFamily('town'),'grass');
  assert.equal(terrainFamily('field'),'farmland');
  for(const key of ['grass','forest','rock','beach','ocean','lake','farmland','city','gravel'])
    assert.match(TERRAIN_COLORS[key],/^#[a-f0-9]{6}$/);
  assert.equal(new Set(Object.values(TERRAIN_COLORS)).size>=12,true);
});

test('non-browser export and geometry tools do not need a canvas implementation',()=>{
  assert.equal(textureTerrain({},'forest'),false);
});

test('higher resolution material tiles keep their world scale',()=>{
  assert.equal(TERRAIN_TILE_PIXELS,1024);
  assert.equal(TERRAIN_REPEAT_M,64);
});

test('directional hill lighting is continuous across repeat edges and has both lit and shaded slopes',()=>{
  assert.equal(HILL_REPEAT_M,384);
  for(const y of [0,.13,.5,.95,1])assert.ok(Math.abs(hillLight(0,y)-hillLight(1,y))<1e-9);
  for(const x of [0,.13,.5,.95,1])assert.ok(Math.abs(hillLight(x,0)-hillLight(x,1))<1e-9);
  const lights=Array.from({length:64},(_,i)=>hillLight((i%8)/8,Math.floor(i/8)/8));
  assert.ok(Math.min(...lights)<-.2&&Math.max(...lights)>.2);
});

test('terrain overhang survives source round trip and point edits, not roads or props',async()=>{
  const {createWorld,normalizeWorld,parseWorld,serializeWorld,moveControlPoint}=await import('../world-model.js');
  const doc=createWorld({name:'Overhang',width:1000,height:800});
  doc.regions.push({id:'region-1',name:'Large field',biome:'grass',elevation:0,points:[{x:-200,y:-200},{x:1500,y:-200},{x:1500,y:1000},{x:-200,y:1000}]});
  const saved=parseWorld(serializeWorld(doc));
  assert.deepEqual(saved.regions[0].points,doc.regions[0].points);
  const moved=moveControlPoint(saved,'region-1',0,{x:-350,y:-300});
  assert.equal(moved.regions[0].points[0].x,-350);
  const invalid=structuredClone(doc);invalid.regions[0].points[0].x=-1000000;
  assert.throws(()=>normalizeWorld(invalid));
  const road=structuredClone(doc);road.roads.push({id:'road-1',name:'Outside',roadClass:'city',surface:'asphalt',width:10,lanes:2,shoulder:1,smooth:false,markings:true,points:[{x:-1,y:10},{x:500,y:10}]});
  assert.throws(()=>normalizeWorld(road));
});
