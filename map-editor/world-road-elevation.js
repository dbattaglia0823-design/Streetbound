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
    return layer===start_layer||layer===end_layer;
  }));
  return byLayer.get(layer);
}

export function normalizeRoadElevation(profile,points){
  if(profile===undefined)return undefined;
  if(!profile||typeof profile!=='object'||Object.keys(profile).length!==2)
    throw new TypeError('Road elevation needs start and end layers');
  const {start_layer,end_layer}=profile;
  if([start_layer,end_layer].some(layer=>!Number.isInteger(layer)||Math.abs(layer)>2))
    throw new RangeError('Road layers must be integers from -2 to 2');
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
  if(start_layer===end_layer||distance(road.points[0],point)<=.12)return start_layer;
  if(distance(road.points.at(-1),point)<=.12)return end_layer;
  return null;
}
