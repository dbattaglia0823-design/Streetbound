import {normalizeWorld,parseWorld} from './world-model.js';

// One atomic storage record keeps the document and its source revision together.
// Legacy autosaves were plain world documents and must remain recoverable.
export function encodeSession(doc,{dirty=false,worldSha='',view=null}={}){
  return JSON.stringify({format:'streetbound.editor-session',version:1,
    doc,dirty:Boolean(dirty),worldSha,view});
}
export function decodeSession(text){
  if(!text)return null;
  const value=JSON.parse(text);
  if(value.format!=='streetbound.editor-session')
    return {doc:parseWorld(text),dirty:true,worldSha:''};
  if(value.version!==1)throw new Error('Unsupported editor session version.');
  const view=value.view;
  const validView=view&&[view.x,view.y,view.zoom].every(Number.isFinite)&&view.zoom>=.007&&view.zoom<=5;
  return {doc:normalizeWorld(value.doc),dirty:Boolean(value.dirty),view:validView?view:null,
    worldSha:typeof value.worldSha==='string'?value.worldSha:''};
}
export function shouldRestoreSession(session,projectConnected){
  return Boolean(session&&(!projectConnected||session.dirty||session.doc.name!=='Morrow Coast'));
}
