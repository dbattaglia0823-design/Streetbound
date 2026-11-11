import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWorld,createEntity,updateEntity,normalizeWorld,serializeWorld} from '../world-model.js';
import {pickEditableScenery,pointInRotatedFootprint} from '../world-selection.js';
import {buildRuntimePreview,pickRuntimeProp} from '../morrow-runtime-preview.js';
import {repairRoadsideObjects,placeSiteMarker} from '../world-road-placement.js';
import {auditWorld} from '../world-audit.js';

const point=(x,y)=>({x,y});
function game(){
  let world=createWorld({name:'House pickup',width:1600,height:1200});
  return createEntity(world,'roads',{name:'Main St',roadClass:'city',
    surface:'asphalt',width:40,lanes:2,shoulder:3,smooth:false,
    markings:true,points:[point(100,600),point(1450,600)]});
}

test('house selects by rotated roof footprint, not only its center or terrain fill',()=>{
  const house={id:'prop-1',name:'Corner house',type:'house',x:500,y:500,
    rotation:90,scale:1,assetId:''};
  const hidden={...house,id:'prop-2',hidden:true};
  assert.ok(pointInRotatedFootprint(point(507,500),house,[12,17],Math.PI/2));
  assert.equal(pickEditableScenery([house],point(507,500),{gameArt:true}),house);
  assert.equal(pickEditableScenery([hidden],point(507,500),{gameArt:true}),null);
  assert.equal(pickEditableScenery([house],point(518,500),{gameArt:true}),null,
    'a nearby click outside the actual roof should select the terrain behind it');
});

test('original baked houses are picked directly across the roof even above fields',()=>{
  const house={kind:'house',p:[520,500],size:[12,17],angle:0,seed:3};
  const field={kind:'field',p:[525,500],size:[100,80],angle:0,seed:4};
  const raw={format:'streetbound.streamed-world',version:1,size:[1600,1200],
    roads:[],terrain:[],props:[field,house],junctions:[]};
  const preview=buildRuntimePreview(raw);
  const doc=createWorld({name:'Map',width:1600,height:1200});
  assert.equal(pickRuntimeProp(preview,doc,point(525,505),6),house,
    'a house should win over an overlapping underlay even when field is closer');
  assert.equal(pickRuntimeProp(preview,doc,point(525,506),6),house,
    'clicking a roof edge, not just its center, should work');
  const adopted=normalizeWorld({...doc,props:[{
    id:'prop-1',type:'house',name:'Game house',x:520,y:500,rotation:0,
    scale:1,assetId:'',replaces:{kind:'house',seed:3,p:[520,500]}
  }]});
  assert.notEqual(pickRuntimeProp(preview,adopted,point(525,505),6),house,
    'once adopted, the native house must not duplicate itself');
});

test('gameplay markers can overlap houses, roads, water and each other without snapping',()=>{
  let doc=game();
  doc=normalizeWorld({...doc,props:[{id:'prop-1',type:'house',
    name:'House',x:500,y:600,rotation:0,scale:1,assetId:''}],
    regions:[{id:'region-1',name:'Water',biome:'ocean',elevation:0,
      points:[point(1100,800),point(1500,800),point(1500,1100),point(1100,1100)]}]});
  const a=createEntity(doc,'markers',{type:'garage',name:'Garage A',
    x:500,y:600,rotation:0,properties:{}});
  assert.deepEqual([a.markers[0].x,a.markers[0].y],[500,600],
    'garage marker must remain exactly atop road and house');
  const c=createEntity(a,'markers',{type:'race_start',name:'Start',
    x:500,y:600,rotation:0,properties:{}});
  assert.deepEqual([c.markers[1].x,c.markers[1].y],[500,600],
    'overlapping different markers is allowed');
  const moved=updateEntity(c,c.markers[0].id,{x:1300,y:900,type:'player_spawn'});
  assert.deepEqual([moved.markers[0].x,moved.markers[0].y],[1300,900],
    'moving a player spawn onto water does not move it back to a road');
  assert.deepEqual(placeSiteMarker(doc,a.markers[0]),a.markers[0],
    'legacy marker placement helper has no implicit snap');
  const report=auditWorld(moved);
  assert.ok(!report.issues.some(i=>i.code==='marker_off_road'));
  const repaired=repairRoadsideObjects(moved,{alignAll:true});
  assert.deepEqual(repaired.doc.markers,moved.markers,
    'roadside auto-repair must never move game markers');
  assert.equal(repaired.adjustedMarkers,0);
  assert.deepEqual(JSON.parse(serializeWorld(moved)).markers,moved.markers,
    'overlap positions survive editor JSON serialization');
});

test('select mode checks visible scenery before roads/terrain and starts direct drag',async()=>{
  const editor=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  const hit=editor.slice(editor.indexOf('function hitTest(p){'),
    editor.indexOf('function refreshInspector()'));
  assert.ok(hit.indexOf("show-markers")<hit.indexOf('pickEditableScenery'));
  assert.ok(hit.indexOf('pickEditableScenery')<hit.indexOf("show-terrain"));
  assert.ok(hit.indexOf('pickRuntimeProp')<hit.indexOf("show-roads"));
  assert.match(editor,/if\(hit\?\.kind==='native'\)/);
  assert.match(editor,/adoptRuntimeScenery\(hit\.source\)/);
  assert.match(editor,/gesture=\{mode:'entity',before:doc,id,start:p,/);
});
