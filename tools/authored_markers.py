"""Validate playable marker metadata and linked authored races for production archives."""
import math
import re

KINDS={'player_spawn','home','garage','dealership','mission','fast_travel',
       'traffic_spawn','fuel','checkpoint','race_start','finish','custom',
       'contract','contract_dropoff','contract_contact','robbery_target'}

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
        layer=info.get('road_layer',0) if isinstance(info,dict) else 0
        if type(layer) not in (int,float) or layer not in range(-2,3):raise ValueError('Invalid marker road layer')
        if layer and marker['type'] not in ('contract','contract_contact','contract_dropoff','robbery_target','race_start','checkpoint','finish','mission','custom'):raise ValueError('Marker type requires ground level')
        if not isinstance(info,dict):raise ValueError('Marker properties must be an object')
        if not isinstance(info.get('description',''),str) or len(info.get('description',''))>500:
            raise ValueError('Invalid marker help text')
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
    by_id={m['id']:m for m in result}
    def linked(origin,identity,kind):
        target=by_id.get(identity) if isinstance(identity,str) else None
        if target is None or target['type']!=kind:
            raise ValueError('Contract references missing '+kind)
        distance=math.hypot(origin['x']-target['x'],origin['y']-target['y'])
        if not 100<=distance<=15000:
            raise ValueError('Contract location must be 100–15000 m away')
        return target
    kinds={'courier','smuggling','getaway','robbery'}
    limits={'cash':(0,10000),'player_xp':(0,1500),'car_xp':(0,1200),
            'underground_rep':(0,30),'required_player_level':(1,100),
            'required_underground_rep':(0,100000),'time_limit_seconds':(60,900),
            'wanted_level':(0,5),'robbery_hold_seconds':(3,30),'arrival_radius_m':(6,30)}
    for marker in result:
        info=marker.get('properties',{})
        kind=marker['type']
        if 'contract_kind' in info and (not isinstance(info['contract_kind'],str) or info['contract_kind'] not in kinds):
            raise ValueError('Invalid contract kind')
        if kind=='contract' and info.get('destination_marker_id'):
            linked(marker,info['destination_marker_id'],'contract_dropoff')
        if 'contact_style' in info and info['contact_style'] not in ('street','business','mechanic','casual','racing'):
            raise ValueError('Invalid contact style')
        for field,maximum in [('contact_role',60),('contact_greeting',180),('contact_bio',240)]:
            if field in info and (not isinstance(info[field],str) or len(info[field])>maximum):
                raise ValueError('Invalid contact field '+field)
        if 'offers' in info and kind!='contract_contact':
            raise ValueError('Only contract contacts can offer jobs')
        if kind!='contract_contact':
            continue
        offers=info.get('offers',[])
        if not isinstance(offers,list) or len(offers)>8:
            raise ValueError('Invalid contact offers')
        job_ids=set()
        for offer in offers:
            if not isinstance(offer,dict):
                raise ValueError('Invalid contract offer')
            identity=offer.get('id')
            if not isinstance(identity,str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,55}',identity) or identity in job_ids:
                raise ValueError('Invalid or duplicate contract ID')
            job_ids.add(identity)
            title=offer.get('title')
            if not isinstance(title,str) or not title.strip() or len(title)>80:
                raise ValueError('Invalid contract title')
            if not isinstance(offer.get('description',''),str) or len(offer.get('description',''))>400:
                raise ValueError('Invalid contract briefing')
            if offer.get('kind') not in tuple(kinds) or offer.get('difficulty','rookie') not in ('rookie','amateur','pro','elite'):
                raise ValueError('Invalid job type or difficulty')
            if type(offer.get('repeatable',True)) is not bool:
                raise ValueError('Invalid repeatability')
            prerequisite=offer.get('required_race_id','')
            if not isinstance(prerequisite,str) or prerequisite and prerequisite not in races:
                raise ValueError('Missing race prerequisite')
            for field,(low,high) in limits.items():
                if field in offer:
                    value=offer[field]
                    if type(value) not in (int,float) or not math.isfinite(value) or value!=int(value) or not low<=value<=high:
                        raise ValueError('Invalid contract setting '+field)
            drop=linked(marker,offer.get('destination_marker_id'),'contract_dropoff')
            if offer['kind']=='robbery':
                target_id=offer.get('robbery_marker_id')
                target=by_id.get(target_id) if isinstance(target_id,str) else None
                if target is None or target['type']!='robbery_target':
                    raise ValueError('Missing robbery target')
                if min(math.hypot(marker['x']-target['x'],marker['y']-target['y']),
                       math.hypot(drop['x']-target['x'],drop['y']-target['y']))<100:
                    raise ValueError('Robbery locations must be separated by 100 m')
            elif offer.get('robbery_marker_id'):
                raise ValueError('Only robberies use robbery targets')
    return result
