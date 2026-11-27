"""Production archive preflight for layered road access and event connectivity.

Road-component reachability is necessary, not sufficient, for a legal directed
route. Runtime route planning remains authoritative for turn restrictions.
Legacy maps without elevated objectives remain byte-identical.
"""
import math
from road_elevation import height_at_station

def audit_elevated_objectives(data):
    races=data.get("editor_races",[])
    markers=data.get("editor_game_markers",[])
    if not any(p.get("road_layer",0) for r in races for p in r["points"]) and not any(m.get("properties",{}).get("road_layer",0) for m in markers):
        return []
    roads=data["roads"]
    parent=list(range(len(roads)))
    def root(i):
        while parent[i]!=i:
            parent[i]=parent[parent[i]]
            i=parent[i]
        return i
    for a,b in data.get("road_connections",[]):
        parent[root(a)]=root(b)
    # Use the existing spatial index, not an all-roads scan for each gate.
    stations=[]; segment_stations=[]
    for road in roads:
        values=[0.0]
        for a,b in zip(road["points"],road["points"][1:]):
            values.append(values[-1]+math.dist(a,b))
        stations.append(values)
        segment_stations.append({(tuple(a),tuple(b)):values[i] for i,(a,b) in enumerate(zip(road["points"],road["points"][1:]))})
    profiles=[{**r,"_stations":st} for r,st in zip(roads,stations)]
    cell=data["surface_cell"]
    warnings=[]
    def access(point,layer,label):
        x,y=float(point["x"]),float(point["y"])
        radius=22.0 if layer==0 else 0.0
        candidates=set()
        for cy in range(math.floor((y-radius)/cell),math.floor((y+radius)/cell)+1):
            for cx in range(math.floor((x-radius)/cell),math.floor((x+radius)/cell)+1):
                candidates.update(data["surface_index"].get(f"{cx},{cy}",[]))
        components=set()
        for index in candidates:
            segment=data["segments"][index]
            rid=segment["road"];road=profiles[rid]
            a,b=segment["a"],segment["b"]
            dx,dy=b[0]-a[0],b[1]-a[1]
            length=math.hypot(dx,dy)
            if length<.001:continue
            t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(length*length)))
            distance=math.hypot(x-a[0]-dx*t,y-a[1]-dy*t)
            if distance>(22 if layer==0 else road["width"]*.5-.85):continue
            station=segment_stations[rid].get((tuple(a),tuple(b)))
            if station is None:continue
            if abs(height_at_station(road,station+t*length)-layer*6)<.65:
                components.add(root(rid))
        if not components:warnings.append(f"{label}: no supported road on layer {layer:+d}")
        return components
    def route(points,label):
        components=[access(p,l,f"{label} objective {i+1}") for i,(p,l) in enumerate(points)]
        if components and all(components) and not set.intersection(*components):
            warnings.append(f"{label}: objective road levels are disconnected")
    for race in races:
        points=[(p,int(p.get("road_layer",0))) for p in race["points"]]
        if any(l for _,l in points):
            route(points,race["name"])
            start_layer=points[0][1]
            if start_layer:
                for i,slot in enumerate(([race["player_start"]] if "player_start" in race else [])+race.get("enemy_starts",[])):
                    access(slot,start_layer,f"{race['name']} grid slot {i+1}")
    by_id={m["id"]:m for m in markers}
    for marker in markers:
        info=marker.get("properties",{})
        layer=int(info.get("road_layer",0))
        if layer:access(marker,layer,marker.get("name",marker["id"]))
        offers=info.get("offers",[]) if marker["type"]=="contract_contact" else [info] if marker["type"]=="contract" else []
        for offer in offers:
            points=[(marker,layer)]
            for field in ("robbery_marker_id","destination_marker_id"):
                target=by_id.get(offer.get(field))
                if target:points.append((target,int(target.get("properties",{}).get("road_layer",0))))
            if len(points)>1 and any(l for _,l in points):route(points,offer.get("title",marker.get("name",marker["id"])))
    return list(dict.fromkeys(warnings))
