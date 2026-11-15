"""Validate editor races before they enter the playable world archive."""
import math
import re

def authored_races(doc,width,height):
    races=doc.get('races',[])
    if not isinstance(races,list) or len(races)>64:raise ValueError('At most 64 editor races are supported')
    result=[];ids=set()
    for race in races:
        if not isinstance(race,dict):raise ValueError('Invalid editor race')
        identity=race.get('id');mode=race.get('mode');name=race.get('name')
        if not isinstance(identity,str) or not re.fullmatch(r'race-[a-zA-Z0-9_-]{1,50}',identity) or identity in ids:raise ValueError('Invalid/duplicate race ID')
        ids.add(identity)
        if mode not in ('sprint','circuit') or not isinstance(name,str) or not name.strip() or len(name)>80:raise ValueError('Race needs a name and sprint/circuit format')
        points=race.get('points')
        if not isinstance(points,list) or not (3 if mode=='circuit' else 2)<=len(points)<=100:raise ValueError('Race needs a start, finish and required checkpoints')
        clean=[]
        for p in points:
            if not isinstance(p,dict):raise ValueError('Invalid race checkpoint')
            x,y=p.get('x'),p.get('y')
            if any(type(v) not in (int,float) or not math.isfinite(v) for v in (x,y)) or not 0<=x<=width or not 0<=y<=height:raise ValueError('Race checkpoint outside map')
            if clean and math.hypot(x-clean[-1]['x'],y-clean[-1]['y'])<5:raise ValueError('Race checkpoints must be at least 5 m apart')
            clean.append({'x':float(x),'y':float(y)})
        entry={'id':identity,'name':name.strip(),'mode':mode,'points':clean}
        for key,low,high,default in [('laps',1,20,1),('checkpoint_radius',4,60,16),('start_radius',3,30,8),('time_limit',0,7200,0)]:
            value=race.get(key,default)
            if type(value) not in (int,float) or not math.isfinite(value) or not low<=value<=high:raise ValueError('Invalid race setting: '+key)
            if key=='laps' and value!=int(value):raise ValueError('Race laps must be a whole number')
            entry[key]=int(value) if key=='laps' else float(value)
        result.append(entry)
    return result
