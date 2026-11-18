"""Validate playable marker metadata and linked authored races for production archives."""
import math

KINDS={'player_spawn','garage','dealership','mission','fast_travel',
       'traffic_spawn','fuel','checkpoint','race_start','finish','custom'}

def validate_markers(markers,races,dealers,width,height):
    if not isinstance(markers,list) or len(markers)>400:
        raise ValueError('Invalid game marker list')
    races={r['id'] for r in races}
    dealers={d['id'] for d in dealers}
    spawns=0
    seen=set()
    result=[]
    for marker in markers:
        if not isinstance(marker,dict) or marker.get('type') not in KINDS:
            raise ValueError('Unknown map marker')
        if not isinstance(marker.get('id'),str) or marker['id'] in seen:
            raise ValueError('Duplicate marker ID')
        seen.add(marker['id'])
        if marker['type']=='player_spawn':spawns+=1
        if not isinstance(marker.get('name',''),str) or len(marker.get('name',''))>120:
            raise ValueError('Invalid marker name')
        for field,bound in (('x',width),('y',height)):
            at=marker.get(field)
            if type(at) not in (int,float) or not math.isfinite(at) or not 0<=at<=bound:
                raise ValueError('Invalid marker position')
        info=marker.get('properties',{})
        if not isinstance(info,dict):raise ValueError('Marker properties must be an object')
        for key,collection in (('race_id',races),('required_race',races),('dealer_id',dealers)):
            target=info.get(key,'')
            if not isinstance(target,str) or len(target)>100 or target and target not in collection:
                raise ValueError('Marker references missing '+key)
        if type(info.get('enabled',True)) is not bool:
            raise ValueError('Invalid marker enabled flag')
        radius=info.get('radius_m',12)
        weight=info.get('traffic_weight',3)
        if type(radius) not in (int,float) or not math.isfinite(radius) or not 4<=radius<=50:
            raise ValueError('Invalid marker radius')
        if type(weight) is not int or not 1<=weight<=10:
            raise ValueError('Invalid marker traffic priority')
        result.append(marker)
    if spawns>1:raise ValueError('Only one player spawn is supported')
    return result
