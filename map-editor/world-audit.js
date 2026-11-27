/**
 * Streetbound map health / preflight: read-only, deterministic, and deliberately
 * advisory except for malformed topology that could make exported physics
 * or route geometry unusable. No changes to the persisted world v2 schema.
 *
 * Inspired by OSM JOSM checks: tiny/repeated segments, unintended crossings,
 * nearby disconnected endpoints, invalid areas and obstructed sites.
 */
import {distance,polygonArea,pointSegment,segmentIntersection,sampleRoad,roadIntersections} from './world-geometry.js';
import {roadwayClearance,placementFootprint,nearestRoadPlacement} from './world-road-placement.js';
import {buildRoadJunctions} from './world-junctions.js';
import {normalizeRoadElevation,junctionLayer,previewHeightAt} from './world-road-elevation.js';
import {findEndpointGaps} from './world-safe-edit.js';
import {nativeAdoptedRadius} from './morrow-runtime-preview.js';

const ENDPOINT_EPS=1.25,CELL=96;
const inWorld=(doc,p)=>p.x>=0&&p.y>=0&&p.x<=doc.world.width&&p.y<=doc.world.height;
const pointOf=entity=>entity.points?.[0]||{x:entity.x||0,y:entity.y||0};
const at=(a,b)=>({x:(a.x+b.x)*0.5,y:(a.y+b.y)*0.5});
const key=(x,y)=>x+','+y;

/** Find first nonadjacent self intersection, with a shared first/last
 * endpoint treated as a legitimate closed race circuit or closed region.
 * Indexed sampled segments avoid a quadratic scan on large curving roads.
 */
export function selfCrossing(path,{closed=false}={}){
  if(path.length<4)return null;
  const segments=[],grid=new Map(),last=closed?path.length:path.length-1;
  const count=path.length;
  for(let i=0;i<last;i++){
    const a=path[i],b=path[(i+1)%count];
    if(distance(a,b)<.001)continue;
    const s={a,b,i};
    const x0=Math.floor(Math.min(a.x,b.x)/CELL),x1=Math.floor(Math.max(a.x,b.x)/CELL);
    const y0=Math.floor(Math.min(a.y,b.y)/CELL),y1=Math.floor(Math.max(a.y,b.y)/CELL);
    const seen=new Set();
    for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++){
      for(const other of grid.get(key(x,y))||[]){
        if(seen.has(other)||Math.abs(i-other.i)<=1)continue;
        seen.add(other);
        if((i===last-1&&other.i===0)&&
          (closed||distance(path[0],path.at(-1))<ENDPOINT_EPS))continue;
        const hit=segmentIntersection(a,b,other.a,other.b);
        if(hit)return hit;
      }
    }
    for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++){
      const k=key(x,y);
      if(!grid.has(k))grid.set(k,[]);
      grid.get(k).push(s);
    }
  }
  return null;
}

export function auditWorld(doc,{maxIssues=180}={}){
  const issues=[];
  const add=(severity,code,entity,p,message,suggestion='')=>{
    if(issues.length>=maxIssues)return;
    issues.push({severity,code,entityId:entity?.id||null,
      entityName:entity?.name||'World',point:{x:+p.x.toFixed(2),y:+p.y.toFixed(2)},
      message,suggestion,id:code+':'+(entity?.id||'world')+':'+issues.length});
  };
  const junctions=buildRoadJunctions(doc.roads);
  for(const road of doc.roads){
    for(let i=1;i<road.points.length;i++){
      const a=road.points[i-1],b=road.points[i],length=distance(a,b);
      if(length<1.0){
        add('error','road_zero_segment',road,b,
          'Two consecutive road control points overlap.',
          'Select the road and use Clean duplicate points.');
        break;
      }
      if(!inWorld(doc,b)){
        add('error','road_outside_world',road,b,
          'Road control point is outside world bounds.');
        break;
      }
    }
    if(road.width/road.lanes<3.2){
      add('warning','narrow_lanes',road,pointOf(road),
        'Road width is narrow for '+road.lanes+' lanes.',
        'Reduce the lane count or increase the total road width.');
    }
    const path=sampleRoad(road.points,road.smooth,20);
    const crossing=selfCrossing(path,{closed:false});
    if(crossing){
      add('warning','road_self_crossing',road,crossing,
        'Road crosses itself. This planar map cannot represent an overpass.',
        'Move control points, split the road, or model an explicit grade-separated crossing.');
    }
  }

  // Elevation health: check profiles, grade crossings and objective access.
  // The exact bake is authoritative for curves, so preview findings are
  // warnings except for invalid authored profile values.
  const elevated=doc.roads.filter(r=>r.elevation);
  if(elevated.length||(doc.races??[]).some(r=>r.points.some(p=>p.road_layer))||doc.markers.some(m=>m.properties?.road_layer)){
    const byId=new Map(doc.roads.map(r=>[r.id,r]));
    const parents=new Map(doc.roads.map(r=>[r.id,r.id]));
    const root=id=>{while(parents.get(id)!==id)id=parents.get(id);return id;};
    for(const junction of junctions){
      const ids=junction.roads.filter(id=>parents.has(id));
      for(let i=1;i<ids.length;i++)parents.set(root(ids[i]),root(ids[0]));
    }
    for(const road of elevated){
      try{normalizeRoadElevation(road.elevation,road.points);}
      catch(e){add('error','invalid_elevation',road,pointOf(road),e.message);}
    }
    for(const cross of roadIntersections(doc.roads)){
      const [a,b]=cross.roads.map(id=>byId.get(id));
      if(!a.elevation&&!b.elevation)continue;
      const la=junctionLayer(a,cross),lb=junctionLayer(b,cross);
      if(la!==null&&la===lb)continue;
      const clearance=Math.abs(previewHeightAt(a,cross).height-previewHeightAt(b,cross).height);
      if(clearance<4.5)add('warning','grade_clearance',a,cross,'Estimated crossing clearance '+clearance.toFixed(1)+' m is below 4.5 m.','Adjust grade or check exact production bake.');
    }
    const access=(point,layer,entity)=>{
      const components=new Set();
      for(const road of doc.roads){
        const p=previewHeightAt(road,point);
        if(p.distance<=(layer===0?22:road.width/2-.85)&&Math.abs(p.height-layer*6)<.65)components.add(root(road.id));
      }
      if(!components.size)add('warning','objective_layer_access',entity,point,'No nearby pavement on objective layer '+layer+'.','Move the objective onto the intended road level.');
      return components;
    };
    const route=(items,entity)=>{
      const sets=items.map(([p,l])=>access(p,l,entity));
      if(sets.length&&sets.every(set=>set.size)&&![...sets[0]].some(id=>sets.every(set=>set.has(id))))
        add('warning','objective_disconnected',entity,items[0][0],'Objectives appear to use disconnected road components.','Connect the required road levels with ramps.');
    };
    for(const race of doc.races??[]){
      if(race.points.some(p=>p.road_layer))route(race.points.map(p=>[p,p.road_layer??0]),race);
    }
    const markers=new Map(doc.markers.map(m=>[m.id,m]));
    for(const marker of doc.markers){
      const info=marker.properties??{},layer=info.road_layer??0;
      if(layer)access(marker,layer,marker);
      for(const offer of marker.type==='contract_contact'?info.offers??[]:marker.type==='contract'?[info]:[]){
        const items=[[marker,layer]];
        for(const key of ['robbery_marker_id','destination_marker_id']){
          const target=markers.get(offer[key]);if(target)items.push([target,target.properties?.road_layer??0]);
        }
        if(items.length>1&&items.some(([,l])=>l))route(items,marker);
      }
    }
  }

  // Nearby unconnected ends are only a suggestion; never auto-connect dirt
  // with pavement and never flag intentional dirt-road cut crossings.
  const gaps=findEndpointGaps(doc,{min:3,max:24});
  for(const gap of gaps){
    const road=doc.roads.find(r=>r.id===gap.roadId);
    add('warning','near_road_endpoint',road,gap.from,
      'Road endpoint is '+gap.distance.toFixed(1)+' units from '+
      (doc.roads.find(r=>r.id===gap.targetRoadId)?.name||'another road')+'.',
      'Use Snap safe ends, or leave it if this is an intentional dead end.');
  }

  for(const region of doc.regions){
    const crossing=selfCrossing(region.points,{closed:true});
    if(crossing){
      add('error','terrain_self_crossing',region,crossing,
        'Terrain boundary intersects itself, creating an ambiguous fill.',
        'Adjust or remove crossing polygon handles.');
    }
    if(polygonArea(region.points)<60){
      add('warning','tiny_terrain',region,pointOf(region),
        'Small terrain polygon may produce hard-to-see geometry.',
        'Increase its area or remove it.');
    }
  }

  // Read-only collision review: ordinary road/scenery edits NEVER relocate
  // props. Show conflicts here and in the live road-clearance layer instead.
  for(const prop of doc.props){
    const radius=placementFootprint(doc,prop);
    // A generated parking entry intentionally reaches the lot curb cut.
    const accessIds=prop.type==='parking'?new Set(doc.roads
      .filter(road=>road.name==='Parking access'&&road.roadClass==='service'&&
        distance(road.points.at(-1),prop)<Math.max(30,32*prop.scale))
      .map(road=>road.id)):null;
    // Adopted native items use their real metre-based collision size, not
    // the larger icon footprint intended for standalone editor mockups.
    const native=prop.replaces?nearestRoadPlacement(doc,prop,250):null;
    const unsafe=prop.replaces
      ? Boolean(native&&native.distance<native.width/2+nativeAdoptedRadius(prop)+1.5)
      : roadwayClearance(doc,prop,radius,accessIds)<-0.5;
    if(unsafe)
      add('warning','scenery_over_road',prop,prop,
        'Scenery footprint overlaps a road or its shoulder.',
        'Move it manually or use Align all overlapping scenery (with confirmation).');
  }

  // Advisory urban-design checks are intentionally bounded and conservative.
  // They catch obvious size errors, isolated vehicle access and crowded
  // facades without incorrectly rejecting curved streets or small courtyards.
  const buildings=new Set(['house','building','warehouse','garage','gas_station','parking']);
  const vehicleSites=new Set(['garage','gas_station','parking']);
  const grid=new Map(),cell=180;
  const keyOf=(x,y)=>x+','+y;
  for(const prop of doc.props){
    if(!buildings.has(prop.type))continue;
    if(prop.scale<.47||prop.scale>2.35)
      add('warning','building_scale_outlier',prop,prop,
        'Building or parking scale is unusual for nearby vehicles.',
        'Compare the footprint to road width and neighboring buildings.');
    if(vehicleSites.has(prop.type)&&doc.roads.length){
      const near=nearestRoadPlacement(doc,prop,260);
      const acceptable=Math.max(105,placementFootprint(doc,prop)*1.6);
      if(!near||near.distance>acceptable)
        add('warning','disconnected_vehicle_access',prop,prop,
          'Vehicle destination has no nearby drivable street or access road.',
          'Add a connected paved driveway or move it closer to a street.');
    }
    const cx=Math.floor(prop.x/cell),cy=Math.floor(prop.y/cell);
    for(let x=cx-1;x<=cx+1;x++)for(let y=cy-1;y<=cy+1;y++){
      for(const other of grid.get(keyOf(x,y))||[]){
        const minimum=(placementFootprint(doc,prop)+placementFootprint(doc,other))*.58;
        if(distance(prop,other)<minimum){
          add('warning','overlapping_buildings',prop,prop,
            'Two building footprints appear crowded or overlapping.',
            'Move one facade or verify the intended attached-building layout.');
          break;
        }
      }
    }
    const key=keyOf(cx,cy);
    if(!grid.has(key))grid.set(key,[]);
    grid.get(key).push(prop);
  }

  // Gameplay markers are intentional free overlays. They may sit on roads,
  // scenery, terrain or each other without placement/overlap warnings.
  if(doc.roads.length&&!doc.markers.some(m=>m.type==='player_spawn'))
    add('warning','missing_spawn',null,{x:doc.world.width/2,y:doc.world.height/2},
      'No player start marker is defined.',
      'Place a player spawn before using this world for gameplay.');
  if(!doc.roads.length)
    add('info','empty_road_network',null,{x:doc.world.width/2,y:doc.world.height/2},
      'This map has no roads yet.','Draw your first road or start with the coastal sample.');

  const rank={error:0,warning:1,info:2};
  issues.sort((a,b)=>rank[a.severity]-rank[b.severity]||a.code.localeCompare(b.code)||a.id.localeCompare(b.id));
  const counts={errors:issues.filter(i=>i.severity==='error').length,
    warnings:issues.filter(i=>i.severity==='warning').length,
    info:issues.filter(i=>i.severity==='info').length};
  return {issues,counts,truncated:issues.length===maxIssues,
    stats:{roads:doc.roads.length,junctions:junctions.length,
      terrain:doc.regions.length,props:doc.props.length,markers:doc.markers.length},
    canExport:counts.errors===0};
}
