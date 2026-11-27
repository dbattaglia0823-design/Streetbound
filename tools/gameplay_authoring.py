"""Validate and bake optional custom-map gameplay controls."""
import math

def validate(doc,width,height):
    zones=doc.get("gameplayZones",[])
    controls=doc.get("junctionControls",[])
    if not isinstance(zones,list) or len(zones)>32 or not isinstance(controls,list) or len(controls)>128:
        raise ValueError("Invalid gameplay controls")
    def num(row,key,lo,hi):
        v=row.get(key)
        if type(v) not in (int,float) or not math.isfinite(v) or not lo<=v<=hi:
            raise ValueError("Invalid gameplay field "+key)
        return v
    for z in zones:
        if not isinstance(z,dict) or not str(z.get("name","")).strip() or z.get("models") not in ("all","passenger","commercial"):
            raise ValueError("Invalid district")
        x,y=num(z,"x",0,width),num(z,"y",0,height)
        num(z,"w",1,width-x);num(z,"h",1,height-y)
        for k,a,b in (("density",0,200),("speed",0,160),("patrol",0,30),("response",50,150)):
            num(z,k,a,b)
    for j in controls:
        if not isinstance(j,dict) or j.get("control") not in ("stop","yield","signal","uncontrolled"):
            raise ValueError("Invalid junction control")
        num(j,"x",0,width);num(j,"y",0,height)
        layer=num(j,"layer",-2,2)
        if layer!=int(layer) or not isinstance(j.get("turns"),list) or not j["turns"] or any(t not in ("left","straight","right") for t in j["turns"]):
            raise ValueError("Invalid junction layer or turns")
    return zones,controls

def apply(junctions,controls):
    used=set()
    for c in controls:
        candidates=[]
        for i,j in enumerate(junctions):
            if j.get("control") in ("merge","roundabout") or len(j.get("approaches",[]))<3 or j.get("road_layer",j.get("layer",0))!=c["layer"]:
                continue
            d=math.hypot(j["p"][0]-c["x"],j["p"][1]-c["y"])
            if d<=8:candidates.append((d,i))
        if not candidates:raise ValueError("Authored intersection no longer matches a baked same-level junction")
        _,i=min(candidates)
        if i in used:raise ValueError("Duplicate authored intersection")
        used.add(i)
        j=junctions[i]
        mode=c["control"]
        j["allowed_turns"]=list(dict.fromkeys(c["turns"]))
        j["control"]="all_way_stop" if mode=="stop" else "priority" if mode=="yield" else mode
        j["signal_count"]=len(j["approaches"]) if mode=="signal" else 0
        for slot,arm in enumerate(j["approaches"]):
            arm["control"]="none" if mode=="uncontrolled" else mode
            arm["signal_slot"]=slot
