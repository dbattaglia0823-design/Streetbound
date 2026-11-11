import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {convertMorrowWorld,expandMorrowWorld,isMorrowEdit,MORROW_MAX_HEIGHT,MORROW_MAX_WIDTH} from '../morrow-coast-bridge.js';
import {normalizeWorld,serializeWorld} from '../world-model.js';

const old=()=>normalizeWorld({
  format:'gdt.racing-world',version:2,name:'Morrow Coast',
  world:{width:6400,height:4800,seed:28114,base:'grass'},
  roads:[{id:'road-0',name:'Laurel Avenue',roadClass:'city',
    surface:'asphalt',width:12,lanes:2,shoulder:2,smooth:true,markings:true,
    points:[{x:1100,y:1900},{x:1400,y:1900}]}],
  regions:[{id:'region-2',name:'Existing forest',biome:'forest',
    elevation:0,points:[{x:600,y:600},{x:1000,y:650},{x:650,y:1000}]}],
  props:[{id:'prop-1',name:'Existing garage',type:'garage',
    x:850,y:1200,scale:1,rotation:15,assetId:'game-garage'}],
  markers:[{id:'marker-0',name:'Existing player spawn',
    type:'player_spawn',x:1200,y:1950,rotation:45,properties:{}}],
  assets:[]
});
test('expansion preserves all original object IDs and exact positions without rescaling',()=>{
  const source=old(),roadPoints=source.roads[0].points;
  const grown=expandMorrowWorld(source,{width:8000,height:6200});
  assert.equal(grown.world.width,8000);
  assert.equal(grown.world.height,6200);
  assert.deepEqual(grown.roads,source.roads);
  assert.deepEqual(grown.regions,source.regions);
  assert.deepEqual(grown.props,source.props);
  assert.deepEqual(grown.markers,source.markers);
  assert.equal(grown.roads,source.roads,'source geometry arrays retained untouched');
  assert.equal(grown.roads[0].points,roadPoints);
  assert.equal(source.world.width,6400,'input not changed');
  assert.equal(source.world.height,4800);
  assert.equal(isMorrowEdit(grown),true);
  assert.deepEqual(JSON.parse(serializeWorld(grown)).world,
    {width:8000,height:6200,seed:28114,base:'grass'});
});
test('map cannot shrink, translate, leave safe limits, or mutate an unrelated world',()=>{
  const grown=expandMorrowWorld(old(),{width:7200,height:5500});
  for(const size of [
    {width:6400,height:5500},{width:7200,height:4800},
    {width:9601,height:5500},{width:7200,height:7201},
    {width:NaN,height:5500},{width:7200.5,height:5500}]){
    assert.throws(()=>expandMorrowWorld(grown,size),/only increase/i);
  }
  assert.deepEqual(expandMorrowWorld(grown,{width:7200,height:5500}),grown);
  assert.throws(()=>expandMorrowWorld({...old(),name:'Other'},{width:7200,height:5500}),
    /Morrow Coast/);
  assert.equal(MORROW_MAX_WIDTH,9600);
  assert.equal(MORROW_MAX_HEIGHT,7200);
});
test('existing source is imported from enlarged world without exposing derived coastline as editable',()=>{
  const runtime={
    format:'streetbound.streamed-world',version:1,size:[7200,5600],
    roads:[{name:'Laurel Road',kind:'local',surface:'ASPHALT',width:9,lanes:2,
      anchors:[[100,100],[1200,100]]}],pois:[],spawn:{position:[500,200],rotation:0},
    props:[],junctions:[],
    terrain:[
      {kind:'forest',points:[[0,0],[1000,0],[1000,1000],[0,1000]]},
      {kind:'ocean',generated_extension:true,
        points:[[6400,0],[7200,0],[7200,5600],[6400,5600]]}
    ]
  };
  const {doc}=convertMorrowWorld(runtime);
  assert.equal(doc.world.width,7200);
  assert.equal(doc.world.height,5600);
  assert.equal(doc.regions.length,1,'generated extra water is never an authoring region');
  assert.equal(doc.regions[0].id,'region-0');
  assert.equal(isMorrowEdit(doc),true);
});
test('map editor has explicit sizing inputs and app applies expanded source',async()=>{
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const controller=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  for(const id of ['morrow-expand-panel','expand-world-width','expand-world-height','expand-morrow'])
    assert.ok(html.includes('id="'+id+'"'));
  assert.ok(controller.includes('expandMorrowWorld('));
  assert.ok(controller.includes("'/api/apply-morrow'"));
});
