import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWorld,createEntity,normalizeWorld,serializeWorld} from '../world-model.js';
import {applyEnvironmentPreset,ENVIRONMENT_PRESETS} from '../world-environment-presets.js';
import {auditWorld} from '../world-audit.js';
import {convertMorrowWorld} from '../morrow-coast-bridge.js';

const point=(x,y)=>({x,y});
function roadsOnly(){
  let doc=createWorld({name:'Environment Design',width:1800,height:1400,seed:991});
  doc=createEntity(doc,'roads',{name:'Laurel Street',roadClass:'city',surface:'asphalt',
    width:36,lanes:2,shoulder:4,smooth:false,markings:true,
    points:[point(200,700),point(1600,700)]});
  return doc;
}
test('roadside preset keeps road geometry and adds reversible scenery',()=>{
  const source=roadsOnly(),before=serializeWorld(source),road=source.roads[0];
  const result=applyEnvironmentPreset(source,{
    preset:'street',selectedId:road.id,anchor:point(850,700),density:.8
  });
  assert.ok(result.count>0,'street furniture should be generated');
  assert.equal(result.doc.roads.length,source.roads.length);
  assert.deepEqual(result.doc.roads,source.roads);
  assert.ok(result.doc.props.every(p=>['streetlight','sign'].includes(p.type)));
  assert.equal(serializeWorld(source),before,'original source is preserved for Undo');
  assert.equal(auditWorld(result.doc).counts.errors,0);
});
test('parking generator creates a connected paved service access and valid lot',()=>{
  const source=roadsOnly();
  const result=applyEnvironmentPreset(source,{preset:'parking',anchor:point(700,885)});
  assert.equal(result.roadsAdded,1);
  assert.ok(result.doc.roads.some(r=>r.name==='Parking access'&&r.surface==='asphalt'));
  assert.ok(result.doc.props.some(p=>p.type==='parking'));
  const parking=result.doc.props.find(p=>p.type==='parking');
  assert.equal(parking.stallWidth,3.2);
  assert.equal(parking.entranceWidth,8);
  assert.equal(parking.occupancy,.4);
  const access=result.doc.roads.at(-1);
  assert.ok(access.points[0].y===700,'access starts on main street centerline');
  assert.ok(access.points[1].y>700,'access points toward parking');
  assert.equal(auditWorld(result.doc).counts.errors,0);
});
test('parking layout options roundtrip without damaging paved access',()=>{
  const source=roadsOnly();
  const result=applyEnvironmentPreset(source,{preset:'parking',
    anchor:point(700,885),parkingSize:1.25,stallWidth:2.8,
    occupancy:.8,entranceWidth:9});
  const lot=result.doc.props.find(p=>p.type==='parking');
  assert.ok(lot);
  assert.equal(lot.scale,1.25);
  assert.equal(lot.stallWidth,2.8);
  assert.equal(lot.occupancy,.8);
  assert.equal(lot.entranceWidth,9);
  assert.equal(result.doc.roads.at(-1).width,9);
  assert.ok(result.stallCapacity>=22);
  const roundtrip=normalizeWorld(JSON.parse(serializeWorld(result.doc)));
  assert.deepEqual(roundtrip.props.find(p=>p.id===lot.id),lot);
  assert.equal(auditWorld(result.doc).counts.errors,0);
});
test('invalid parking options do not mutate the source map',()=>{
  const source=roadsOnly(),before=serializeWorld(source);
  for(const options of [{occupancy:2},{stallWidth:0},{entranceWidth:16},
    {parkingSize:3},{occupancy:Number.NaN}]){
    assert.throws(()=>applyEnvironmentPreset(source,{preset:'parking',
      anchor:point(700,885),...options}),/parking/i);
  }
  assert.equal(serializeWorld(source),before);
});
test('parking near world edge fails safely with no mutations',()=>{
  const source=roadsOnly(),snapshot=serializeWorld(source);
  assert.throws(()=>applyEnvironmentPreset(source,{
    preset:'parking',anchor:point(1700,20)
  }),/road|boundary/i);
  assert.equal(serializeWorld(source),snapshot);
});
test('forest and coastal presets scatter only in selected land regions',()=>{
  let doc=roadsOnly();
  doc=createEntity(doc,'regions',{name:'Garden Preserve',biome:'grass',elevation:0,
    points:[point(150,100),point(900,100),point(900,520),point(150,520)]});
  const id=doc.regions[0].id;
  const first=applyEnvironmentPreset(doc,{preset:'forest',anchor:point(350,300),
    selectedId:id,density:.55});
  assert.equal(first.doc.regions[0].biome,'forest');
  assert.ok(first.count>0);
  const second=applyEnvironmentPreset(first.doc,{preset:'coastal',
    anchor:point(350,300),selectedId:id,density:.55});
  assert.equal(second.doc.regions[0].biome,'beach');
  assert.ok(second.doc.props.some(p=>p.type==='palm'));
  assert.equal(auditWorld(second.doc).counts.errors,0);
});
test('water never gets vegetation and invalid presets are rejected',()=>{
  let doc=roadsOnly();
  doc=createEntity(doc,'regions',{name:'Bay',biome:'ocean',elevation:0,
    points:[point(100,100),point(400,100),point(400,420),point(100,420)]});
  assert.throws(()=>applyEnvironmentPreset(doc,{
    preset:'forest',anchor:point(260,200),selectedId:doc.regions[0].id
  }),/water/);
  assert.throws(()=>applyEnvironmentPreset(doc,{preset:'nonsense',anchor:point(200,200)}));
});
test('industrial preset uses safe roadside building footprints',()=>{
  const doc=roadsOnly();
  const result=applyEnvironmentPreset(doc,{preset:'industrial',
    anchor:point(870,1040),density:.55});
  assert.ok(result.count>=1);
  assert.ok(result.doc.props.some(p=>['warehouse','building','sign','streetlight'].includes(p.type)));
});
test('map health flags obviously wrong building size and isolated driving access',()=>{
  let doc=roadsOnly();
  doc=createEntity(doc,'props',{name:'Oversize garage',type:'garage',
    x:1450,y:1200,scale:3,rotation:0,assetId:''});
  const report=auditWorld(doc);
  assert.ok(report.issues.some(i=>i.code==='building_scale_outlier'));
});
test('Morrow preview roundtrips authored scenery without importing generated props',()=>{
  const raw={format:'streetbound.streamed-world',version:1,
    size:[6400,4800],spawn:{position:[500,500],rotation:0},
    roads:[{name:'Main',kind:'local',surface:'ASPHALT',width:12,lanes:2,
      anchors:[[100,100],[1000,100]]}],terrain:[],pois:[],
    props:[{kind:'lot',p:[750,640],angle:0,size:[38,28],authoring_id:'prop-48',
      editor_type:'parking',editor_name:'Service lot',editor_scale:1},
      {kind:'tree',p:[220,300],size:[7,7]}]};
  const {doc}=convertMorrowWorld(raw);
  assert.equal(doc.props.length,1);
  assert.equal(doc.props[0].type,'parking');
  assert.equal(doc.props[0].id,'prop-48');
});
test('UI provides each preset and controls',async()=>{
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const script=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  assert.ok(ENVIRONMENT_PRESETS.length>=5);
  for(const id of ['parking-size','parking-stall-width','parking-occupancy',
      'parking-entrance','environment-preset','environment-density','apply-environment-preset',
      'environment-preset-status'])assert.ok(html.includes('id="'+id+'"'));
  assert.ok(script.includes('applyEnvironmentPreset('));
});
