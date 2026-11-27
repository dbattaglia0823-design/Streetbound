import {distance} from './world-geometry.js';

export const LAYER_HEIGHT_M=6;
export const MAX_ROAD_SLOPE=.12;

export function roadElevation(road){
  return road.elevation||{start_layer:0,end_layer:0};
}

const layerViews=new WeakMap();

export function roadsOnLayer(roads,layer){
  if(layer==='all')return roads;
  let byLayer=layerViews.get(roads);
  if(!byLayer){byLayer=new Map();layerViews.set(roads,byLayer);}
  if(!byLayer.has(layer))byLayer.set(layer,roads.filter(road=>{
    const {start_layer,end_layer}=roadElevation(road);
    return road.elevation?.point_layers?.includes(layer)||layer===start_layer||layer===end_layer;
  }));
  return byLayer.get(layer);
}

export function normalizeRoadElevation(profile,points){
  if(profile===undefined)return undefined;
  if(!profile||typeof profile!=='object'||![2,3].includes(Object.keys(profile).length))
    throw new TypeError('Road elevation needs start and end layers');
  const {start_layer,end_layer}=profile;
  if([start_layer,end_layer].some(layer=>!Number.isInteger(layer)||Math.abs(layer)>2))
    throw new RangeError('Road layers must be integers from -2 to 2');
  if(profile.point_layers!==undefined){
    const values=profile.point_layers;
    if(!Array.isArray(values)||values.length!==points.length||values.some(v=>!Number.isInteger(v)||Math.abs(v)>2)||values[0]!==start_layer||values.at(-1)!==end_layer)
      throw new RangeError('Choose a layer for every road point');
    for(let i=1;i<values.length;i++){
      if(Math.abs(values[i]-values[i-1])>1)throw new RangeError('Point layers must be adjacent');
      if(values[i]!==values[i-1]&&distance(points[i],points[i-1])<50)throw new RangeError('Point layer changes need at least 50 m');
    }
    if(distance(points[0],points.at(-1))<.001&&values.some(v=>v!==values[0]))throw new RangeError('Variable-height closed road is not supported');
    return values.some(Boolean)?{start_layer,end_layer,point_layers:[...values]}:undefined;
  }
  if(Math.abs(start_layer-end_layer)>1)
    throw new RangeError('A ramp can connect only adjacent layers');
  if(!start_layer&&!end_layer)return undefined;
  const length=points.slice(1).reduce((sum,p,i)=>sum+distance(points[i],p),0);
  const rise=Math.abs(start_layer-end_layer)*LAYER_HEIGHT_M;
  if(rise&&distance(points[0],points.at(-1))<.12)
    throw new RangeError('An elevation ramp must have distinct endpoints');
  if(length<4||rise>length*MAX_ROAD_SLOPE)
    throw new RangeError('An elevation ramp needs at least 50 m per layer');
  return {start_layer,end_layer};
}

export function junctionLayer(road,point){
  const {start_layer,end_layer}=roadElevation(road);
  if(road.elevation?.point_layers){
    const values=road.elevation.point_layers;
    for(let i=0;i<road.points.length;i++)if(distance(road.points[i],point)<=.12)return values[i];
    // Conservative interior preview: only a flat span can create a junction.
    let best=Infinity,layer=null;
    for(let i=1;i<road.points.length;i++){
      const a=road.points[i-1],b=road.points[i],dx=b.x-a.x,dy=b.y-a.y;
      const t=Math.max(0,Math.min(1,((point.x-a.x)*dx+(point.y-a.y)*dy)/Math.max(.001,dx*dx+dy*dy)));
      const d=Math.hypot(point.x-a.x-t*dx,point.y-a.y-t*dy);
      if(d<best){best=d;layer=values[i-1]===values[i]?values[i]:null;}
    }
    return layer;
  }
  if(start_layer===end_layer||distance(road.points[0],point)<=.12)return start_layer;
  if(distance(road.points.at(-1),point)<=.12)return end_layer;
  return null;
}
