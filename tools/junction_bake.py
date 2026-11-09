"""Bake at-grade junction mouths, rounded corners, priority and paint exclusions.

Endpoint T joins and interior crossings use the same geometry. No road-over-road
decks exist in Morrow Coast; the old grade field describes water bridge routes.
"""
import bisect
import math

PRIORITY = {'highway':5,'track':5,'arterial':4,'rural':3,'mountain':3,
            'local':2,'gravel':1,'driveway':0}


def distance(a,b):
    return math.hypot(a[0]-b[0],a[1]-b[1])


def near(p,a,b):
    d=[b[k]-a[k] for k in (0,1)]
    t=max(0,min(1,sum((p[k]-a[k])*d[k] for k in (0,1))/max(sum(v*v for v in d),1e-12)))
    q=[a[k]+t*d[k] for k in (0,1)]
    return distance(p,q),t


def crossing(a,b,c,d):
    v=[b[k]-a[k] for k in (0,1)]; w=[d[k]-c[k] for k in (0,1)]
    det=v[0]*w[1]-v[1]*w[0]
    if abs(det)<1e-8:return None
    delta=[c[k]-a[k] for k in (0,1)]
    t=(delta[0]*w[1]-delta[1]*w[0])/det
    u=(delta[0]*v[1]-delta[1]*v[0])/det
    if -1e-6<=t<=1.000001 and -1e-6<=u<=1.000001:
        return [a[k]+t*v[k] for k in (0,1)]


def unit(a,b):
    length=max(distance(a,b),1e-9)
    return [(b[k]-a[k])/length for k in (0,1)]


def sample(road,station):
    s=max(0,min(road['_stations'][-1],station))
    i=min(len(road['points'])-2,max(0,bisect.bisect_right(road['_stations'],s)-1))
    a,b=road['points'][i:i+2]
    t=(s-road['_stations'][i])/max(distance(a,b),1e-9)
    return [a[k]+t*(b[k]-a[k]) for k in (0,1)]


def project(road,p):
    best=(float('inf'),0)
    for i,(a,b) in enumerate(zip(road['points'],road['points'][1:])):
        d,t=near(p,a,b)
        if d<best[0]:best=d,road['_stations'][i]+t*distance(a,b)
    return best


def clean_polygon(points):
    result=[]
    for p in points:
        if not result or distance(result[-1],p)>.001:result.append(p)
    if len(result)>1 and distance(result[0],result[-1])<.001:result.pop()
    return result


def simple_polygon(points):
    for i,a in enumerate(points):
        b=points[(i+1)%len(points)]
        for k in range(i+2,len(points)):
            if i==0 and k==len(points)-1:continue
            c,d=points[k],points[(k+1)%len(points)]
            p=crossing(a,b,c,d)
            if p is not None and min(distance(p,q) for q in [a,b,c,d])>.001:return False
    return True


def rounded_hull(points):
    points=sorted(set(tuple(p) for p in points))
    def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower=[]; upper=[]
    for p in points:
        while len(lower)>1 and cross(lower[-2],lower[-1],p)<=0:lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper)>1 and cross(upper[-2],upper[-1],p)<=0:upper.pop()
        upper.append(p)
    hull=lower[:-1]+upper[:-1]
    rounded=[]
    for i,p in enumerate(hull):
        before,after=hull[i-1],hull[(i+1)%len(hull)]
        cut=min(2,distance(before,p)*.15,distance(p,after)*.15)
        a=[p[k]+(before[k]-p[k])*cut/max(distance(before,p),.001) for k in (0,1)]
        b=[p[k]+(after[k]-p[k])*cut/max(distance(after,p),.001) for k in (0,1)]
        for step in range(6):
            t=step/5
            rounded.append([(1-t)**2*a[k]+2*t*(1-t)*p[k]+t*t*b[k] for k in (0,1)])
    return rounded


def build_junctions(roads,nodes,segments,grid):
    for road in roads:
        stations=[0.0]
        for a,b in zip(road['points'],road['points'][1:]):stations.append(stations[-1]+distance(a,b))
        road['_stations']=stations
        road['marking_gaps']=[]
    events=[]; cells={}; connections=set(); crossings=[]
    def event(p,ids):
        cell=(int(p[0]//8),int(p[1]//8))
        for x in range(cell[0]-1,cell[0]+2):
            for y in range(cell[1]-1,cell[1]+2):
                for index in cells.get((x,y),[]):
                    if distance(events[index]['p'],p)<3:
                        events[index]['roads'].update(ids)
                        return
        cells.setdefault(cell,[]).append(len(events))
        events.append(dict(p=list(p),roads=set(ids)))
    for name,p in nodes.items():
        ids=[r['id'] for r in roads if name in [r['start'],r['end']]]
        if len(ids)>=2:event(p,ids)
    tested=set()
    for indices in grid.values():
        for i in indices:
            for j in indices:
                if j<=i or (i,j) in tested:continue
                tested.add((i,j))
                a,b=segments[i],segments[j]
                if a['road']==b['road']:continue
                p=crossing(a['a'],a['b'],b['a'],b['b'])
                if p is not None:
                    ids=[a['road'],b['road']]
                    crossings.append(dict(p=p,roads=ids))
                    event(p,ids)
    # Catch endpoints touching the interior of a road within authored precision.
    for road in roads:
        for p in [road['points'][0],road['points'][-1]]:
            key=f'{int(p[0]//64)},{int(p[1]//64)}'
            ids={road['id']}
            for index in grid.get(key,[]):
                seg=segments[index]
                if seg['road']!=road['id'] and near(p,seg['a'],seg['b'])[0]<.12:ids.add(seg['road'])
            if len(ids)>1:event(p,ids)
    result=[]
    for e in events:
        ids=sorted(e['roads']); center=e['p']
        for a in ids:
            for b in ids:
                if a<b:connections.add((a,b))
        base=max(roads[i]['width'] for i in ids)*.5+6
        arms=[]
        for road_id in ids:
            road=roads[road_id]; _,station=project(road,center)
            for side in [-1,1]:
                available=station if side<0 else road['_stations'][-1]-station
                if available<.5:continue
                out=unit(center,sample(road,station+side*min(5,available)))
                arms.append(dict(road=road_id,side=side,origin_station=station,
                                 direction=out,available=available,width=road['width']))
        # Coincident route pieces describe one physical approach.
        unique=[]
        for arm in sorted(arms,key=lambda a:-a['width']):
            if not any(sum(arm['direction'][k]*b['direction'][k] for k in (0,1))>.998 for b in unique):unique.append(arm)
        arms=unique
        if len(arms)<2:continue
        dot=sum(arms[0]['direction'][k]*arms[1]['direction'][k] for k in (0,1))
        if len(arms)==2 and dot<-.94 and abs(arms[0]['width']-arms[1]['width'])<.1:
            continue  # smooth continuation, not a traffic junction
        for arm in arms:
            clearance=base
            for other in arms:
                if other is arm:continue
                cosine=sum(arm['direction'][k]*other['direction'][k] for k in (0,1))
                sine=abs(arm['direction'][0]*other['direction'][1]-arm['direction'][1]*other['direction'][0])
                if cosine>0 and sine>.025:
                    clearance=max(clearance,(other['width']*.5+arm['width']*.5*cosine)/sine+3)
            arm['setback']=min(40,clearance,arm['available']*.70)
            road=roads[arm['road']]
            arm['station']=max(0,min(road['_stations'][-1],arm['origin_station']+arm['side']*arm['setback']))
            arm['p']=sample(road,arm['station'])
            arm['direction']=unit(sample(road,arm['station']-arm['side']*.4),sample(road,arm['station']+arm['side']*.4))
            arm['angle']=math.atan2(arm['p'][1]-center[1],arm['p'][0]-center[0])
            arm['control']='none'
        arms.sort(key=lambda a:a['angle'])
        ranks=[PRIORITY[roads[a['road']]['kind']] for a in arms]
        roundabout=any(roads[a['road']]['name']=='Civic Roundabout' for a in arms)
        control='none'
        if len(arms)>=3:
            if roundabout:
                control='roundabout'
                for arm in arms:
                    if roads[arm['road']]['name']!='Civic Roundabout':arm['control']='yield'
            else:
                pairs=[]
                for i,a in enumerate(arms):
                    for j,b in enumerate(arms[i+1:],i+1):
                        dot=sum(a['direction'][k]*b['direction'][k] for k in (0,1))
                        same=roads[a['road']]['name']==roads[b['road']]['name']
                        if dot<-.45 or (same and dot<.3):
                            score=min(ranks[i],ranks[j])*100+(25 if same else 0)-dot*10
                            pairs.append((score,i,j))
                # Equal-rank urban crossroads get an explicit all-way stop.
                all_way=len(arms)>=4 and len(set(ranks))==1 and max(ranks)<=4
                if pairs and not all_way:
                    _,i,j=max(pairs)
                    for k,arm in enumerate(arms):
                        if k not in [i,j]:arm['control']='stop'
                    control='priority'
                else:
                    for arm in arms:arm['control']='stop'
                    control='all_way_stop'
        polygon=[]; curbs=[]
        for i,a in enumerate(arms):
            b=arms[(i+1)%len(arms)]
            da,db=a['direction'],b['direction']
            na,nb=[-da[1],da[0]],[-db[1],db[0]]
            right=[a['p'][k]-na[k]*a['width']*.5 for k in (0,1)]
            start=[a['p'][k]+na[k]*a['width']*.5 for k in (0,1)]
            end=[b['p'][k]-nb[k]*b['width']*.5 for k in (0,1)]
            polygon.append(right)
            det=da[0]*db[1]-da[1]*db[0]
            corner=[]
            if abs(det)>.08:
                delta=[end[k]-start[k] for k in (0,1)]
                t=(delta[0]*db[1]-delta[1]*db[0])/det
                handle=[start[k]+da[k]*t for k in (0,1)]
                if distance(handle,center)>max(55,base*3):handle=[(start[k]+end[k])*.5 for k in (0,1)]
                for step in range(9):
                    t=step/8
                    corner.append([(1-t)**2*start[k]+2*t*(1-t)*handle[k]+t*t*end[k] for k in (0,1)])
            else:corner=[start,end]
            polygon.extend(corner)
            curbs.append(corner)
        polygon=clean_polygon(polygon)
        if not simple_polygon(polygon):
            # Curved acute approaches can overlap their own tangent mouths.
            # Use a rounded compound apron, with kerbs only outside road lanes.
            polygon=rounded_hull(polygon)
            curbs=[]; run=[]
            for a,b in zip(polygon,polygon[1:]+polygon[:1]):
                count=max(1,math.ceil(distance(a,b)))
                for step in range(count):
                    p=[a[k]+(b[k]-a[k])*step/count for k in (0,1)]
                    clear=all(project(roads[road_id],p)[0]>roads[road_id]['width']*.5+.15 for road_id in ids)
                    if clear:run.append(p)
                    else:
                        if len(run)>1:curbs.append(run)
                        run=[]
            if len(run)>1:curbs.append(run)
        for arm in arms:
            road=roads[arm['road']]
            s=arm['origin_station']; end=arm['station']
            road['marking_gaps'].append([max(0,min(s,end)-.5),min(road['_stations'][-1],max(s,end)+.5)])
            for key in ['available','origin_station','angle']:arm.pop(key,None)
        radius=max(distance(center,p) for p in polygon)+2
        result.append(dict(p=center,roads=ids,approaches=arms,polygon=polygon,curbs=curbs,
                           radius=radius,control=control,kind='crossroads' if len(arms)>=4 else ('t_junction' if len(arms)==3 else 'bend')))
    for road in roads:
        merged=[]
        for a,b in sorted(road['marking_gaps']):
            if merged and a<=merged[-1][1]:merged[-1][1]=max(b,merged[-1][1])
            else:merged.append([a,b])
        road['marking_gaps']=merged
        road.pop('_stations')
    return result,connections,crossings
