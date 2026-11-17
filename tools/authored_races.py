"""Validate editor races before they enter the playable world archive."""
import math
import re
import json
from functools import lru_cache
from pathlib import Path

@lru_cache(maxsize=1)
def vehicle_ids():
    catalog=Path(__file__).resolve().parents[1] / 'data' / 'player_vehicle_catalog.json'
    return frozenset(str(car['id']) for car in json.loads(catalog.read_text(encoding='utf-8'))['vehicles'])

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
        formation=race.get('formation','single_file')
        if formation not in ('single_file','side_by_side','staggered'):raise ValueError('Invalid grid formation')
        player=race.get('player_start')
        enemies=race.get('enemy_starts',[])
        if not isinstance(enemies,list) or len(enemies)>6:raise ValueError('Race grid allows at most six rivals')
        def slot(value):
            if not isinstance(value,dict) or any(type(value.get(k)) not in (int,float) or not math.isfinite(value[k]) for k in ('x','y','rotation')):raise ValueError('Invalid race grid slot')
            x,y,rotation=value['x'],value['y'],value['rotation']
            if not 0<=x<=width or not 0<=y<=height or abs(rotation)>360:raise ValueError('Race grid slot outside world')
            return {'x':float(x),'y':float(y),'rotation':float(rotation)}
        if player is not None or enemies:
            if player is None:raise ValueError('Rivals need a player start slot')
            starts=[slot(player)]+[slot(enemy) for enemy in enemies]
            def separated(a,b):
                pa=(a['x'],a['y']);pb=(b['x'],b['y'])
                aa=math.radians(a['rotation']);ab=math.radians(b['rotation'])
                fa=(math.cos(aa),math.sin(aa));fb=(math.cos(ab),math.sin(ab))
                axes=[fa,(-fa[1],fa[0]),fb,(-fb[1],fb[0])]
                for ax in axes:
                    da=abs(ax[0]*fa[0]+ax[1]*fa[1])*1.1+abs(ax[0]*-fa[1]+ax[1]*fa[0])*2.3
                    db=abs(ax[0]*fb[0]+ax[1]*fb[1])*1.1+abs(ax[0]*-fb[1]+ax[1]*fb[0])*2.3
                    if abs((pb[0]-pa[0])*ax[0]+(pb[1]-pa[1])*ax[1])>=da+db+0.6:return True
                return False
            for i in range(len(starts)):
                for j in range(i):
                    if not separated(starts[i],starts[j]):raise ValueError('Race grid vehicles overlap')
            entry.update({'player_start':starts[0],'enemy_starts':starts[1:],'formation':formation})
        elif 'formation' in race:
            entry['formation']=formation
        pool=race.get('opponent_pool',[])
        if not isinstance(pool,list) or len(pool)>128 or any(
            not isinstance(car,str) or car not in vehicle_ids() for car in pool
        ) or len(pool)!=len(set(pool)):
            raise ValueError('Race opponent pool must contain unique IDs from the current vehicle catalog')
        entry['opponent_pool']=pool
        for key,maximum in [('reward_cash',1000000),('reward_player_xp',100000),('reward_car_xp',100000)]:
            amount=race.get(key,0)
            if type(amount) is not int or not 0<=amount<=maximum:
                raise ValueError('Invalid race reward: '+key)
            entry[key]=amount
        result.append(entry)
    return result
