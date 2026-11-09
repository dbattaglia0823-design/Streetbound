/**
 * Map-health UI controller. Isolated so normal editor interactions do not run
 * a full validation scan every frame. Findings are cached until the next edit.
 */
import {auditWorld} from './world-audit.js';
import {snapSafeEndpoints,cleanDuplicateRoadPoints} from './world-safe-edit.js';
import {serializeWorld,parseWorld} from './world-model.js';

const $=id=>document.getElementById(id);
const RECOVERY='streetbound.map-editor.previous.v2';
export function createMapAuditUI({getDoc,change,selectIssue,download,startWorld,getDirty,worldSlug,status}){
  let report=null;
  function invalidate(){
    report=null;
    $('audit-count').textContent='NOT CHECKED';
    $('audit-summary').className='audit-summary';
    $('audit-summary').textContent='Map changed. Run Check map for updated findings.';
    $('audit-list').replaceChildren();
  }
  function render(){
    if(!report)return;
    const {counts,stats,issues,truncated}=report;
    $('audit-count').textContent=counts.errors+' ERR / '+counts.warnings+' WARN';
    const summary=$('audit-summary');
    summary.className='audit-summary'+(counts.errors?' has-errors':counts.warnings?' has-warnings':'');
    summary.textContent=counts.errors+' blocking errors · '+counts.warnings+' warnings · '+
      counts.info+' notes · '+stats.junctions+' junctions'+
      (truncated?' · findings capped':'')+
      '. Errors block Godot export; warnings should be reviewed.';
    const list=$('audit-list');
    list.replaceChildren();
    for(const issue of issues.slice(0,70)){
      const button=document.createElement('button');
      button.type='button';button.className='audit-item';button.dataset.severity=issue.severity;
      const severity=document.createElement('strong');
      severity.textContent=issue.severity;
      button.append(severity,document.createTextNode(' '+issue.message));
      const detail=document.createElement('small');
      detail.textContent=issue.entityName+(issue.suggestion?' · '+issue.suggestion:'');
      button.append(detail);
      button.addEventListener('click',()=>selectIssue(issue));
      list.append(button);
    }
    if(issues.length>70){
      const more=document.createElement('p');
      more.className='muted-copy';
      more.textContent='Showing the first 70 of '+issues.length+' findings. Fix and run the check again.';
      list.append(more);
    }
  }
  function run(){
    try{
      report=auditWorld(getDoc());
      render();
      return report;
    }catch(e){
      status('Map health could not finish: '+e.message);
      return null;
    }
  }
  function stash(source){
    try{
      const value=typeof source==='string'?source:serializeWorld(source);
      // Avoid evicting current browser autosaves for a large world;
      // use Download backup for bigger source worlds.
      if(value.length>2_000_000)return false;
      localStorage.setItem(RECOVERY,value);
      return true;
    }catch{return false;}
  }
  function preflight(){
    const data=run();
    if(!data)return false;
    if(data.counts.errors){
      status('Godot export blocked: '+data.counts.errors+
        ' geometry error(s). Fix them using Map health; Export JSON still works.');
      return false;
    }
    if(data.counts.warnings&&!window.confirm(
      'Map health found '+data.counts.warnings+
      ' warning(s). Review them before using this map in-game.\n\nExport Godot ZIP anyway?'))return false;
    return true;
  }
  $('audit-run').addEventListener('click',()=>{
    const result=run();
    if(result)status('Map health: '+result.counts.errors+' errors, '+
      result.counts.warnings+' warnings. Click a finding to inspect.');
  });
  $('audit-top').addEventListener('click',()=>{
    $('audit-heading').scrollIntoView({behavior:'smooth',block:'start'});
    run();
  });
  $('audit-snap').addEventListener('click',()=>{
    let action=null;
    change(doc=>{action=snapSafeEndpoints(doc);return action.doc;},'Safely snapped compatible road ends.');
    status('Snapped '+(action?.count||0)+' compatible endpoint pair(s). Undo is available.');
    run();
  });
  $('audit-clean').addEventListener('click',()=>{
    let action=null;
    change(doc=>{action=cleanDuplicateRoadPoints(doc);return action.doc;},'Cleaned duplicate road points.');
    status('Removed '+(action?.removed||0)+' redundant road point(s). Undo is available.');
    run();
  });
  $('audit-backup').addEventListener('click',()=>{
    try{
      const stamp=new Date().toISOString().replace(/[:.]/g,'-');
      download(serializeWorld(getDoc()),worldSlug(getDoc().name)+'-backup-'+stamp+
        '.world.json','application/json');
      status('Downloaded editable JSON backup. Commit it to the repository if needed.');
    }catch(e){status(e.message);}
  });
  $('audit-recover').addEventListener('click',()=>{
    try{
      const saved=localStorage.getItem(RECOVERY);
      if(!saved){status('No previous local recovery copy. Use Export JSON for backups.');return;}
      const data=parseWorld(saved);
      if(!window.confirm('Restore the previous local map? Current unsaved edits will be replaced.'))return;
      startWorld(data,'Restored the previous map. Export JSON for permanent recovery.',{skipRecovery:true});
    }catch(e){status('Could not restore previous copy: '+e.message);}
  });
  return {
    invalidate,run,stash,preflight,
    get issues(){return $('audit-show-overlay').checked?(report?.issues||[]):[];},
    get report(){return report;}
  };
}
