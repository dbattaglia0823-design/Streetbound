import test from 'node:test';
import assert from 'node:assert/strict';
import {terrainFamily,TERRAIN_COLORS,textureTerrain} from '../world-terrain-materials.js';

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
