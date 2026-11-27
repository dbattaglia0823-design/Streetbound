import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {normalizeWorld,updateEntity} from '../world-model.js';

test('asset draw order is signed, optional and round trips without affecting transforms',()=>{
  const fixture=JSON.parse(readFileSync(new URL('../../tests/fixtures/road-elevation.world.json',import.meta.url),'utf8'));
  const raw={id:'prop-layer',name:'Layered house',type:'house',x:500,y:600,rotation:0,scale:1,assetId:''};
  const source=normalizeWorld({...fixture,props:[raw]});
  const original=source.props[0];
  for(const drawOrder of [-5,-1,1,10]){
    const changed=updateEntity(source,raw.id,{drawOrder});
    assert.deepEqual(changed.props[0],{...original,drawOrder});
    assert.deepEqual(normalizeWorld(JSON.parse(JSON.stringify(changed))).props,changed.props);
    assert.deepEqual(updateEntity(changed,raw.id,{drawOrder:0}).props,source.props);
  }
  assert.equal(original.drawOrder,undefined);
  for(const drawOrder of [-6,11,1.5,true,'1'])assert.throws(()=>updateEntity(source,raw.id,{drawOrder}),/draw order/);
});
