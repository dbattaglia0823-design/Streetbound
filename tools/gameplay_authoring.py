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
        approach=num(j,"approach",-1,31) if "approach" in j else -1
        lane=num(j,"lane",-1,5) if "lane" in j else -1
        if approach!=int(approach) or lane!=int(lane) or (lane>=0 and approach<0):
            raise ValueError("Invalid approach or lane selector")
    return zones,controls

def apply(junctions,controls,roads=None):
    """Bind rules to a real same-level junction; all-arm rules precede overrides."""
    used=set()
    grouped={}
    for c in controls:
        candidates=[]
        for i,j in enumerate(junctions):
            if j.get("control") in ("merge","roundabout") or len(j.get("approaches",[]))<3 or j.get("road_layer",j.get("layer",0))!=c["layer"]:
                continue
            d=math.hypot(j["p"][0]-c["x"],j["p"][1]-c["y"])
            if d<=8:candidates.append((d,i))
        if not candidates:raise ValueError("Authored intersection no longer matches a baked same-level junction")
        _,i=min(candidates)
        approach=int(c.get("approach",-1));lane=int(c.get("lane",-1))
        if approach>=len(junctions[i]["approaches"]):
            raise ValueError("Authored approach no longer exists")
        if lane>=0 and roads is not None:
            arm=junctions[i]["approaches"][approach]
            road=roads[arm["road"]]
            count=max(1,int(road.get("lanes",2)))
            # Match the runtime right-hand lane layout: one-lane roads are
            # bidirectional (except explicit on-ramps); odd counts favor forward.
            if road.get("kind")=="onramp":
                count=1
            elif count>1:
                count=(count+1)//2 if int(arm["side"])<0 else count//2
            if lane>=count:raise ValueError("Authored lane no longer exists on approach")
        key=(i,approach,lane)
        if key in used:raise ValueError("Duplicate authored intersection approach/lane")
        used.add(key)
        grouped.setdefault(i,[]).append((approach,lane,c))
    for i,rules in grouped.items():
        j=junctions[i]
        j["authored_control"]=True
        arms=j["approaches"]
        for approach,lane,c in sorted(rules,key=lambda row:(row[0],row[1])):
            mode=c["control"]
            turns=list(dict.fromkeys(c["turns"]))
            if approach<0:
                j["allowed_turns"]=turns
                j["control"]="all_way_stop" if mode=="stop" else "priority" if mode=="yield" else "none" if mode=="uncontrolled" else mode
                for arm in arms:
                    arm["control"]="none" if mode=="uncontrolled" else mode
                    arm["allowed_turns"]=turns
            elif lane<0:
                arms[approach]["control"]="none" if mode=="uncontrolled" else mode
                arms[approach]["allowed_turns"]=turns
            else:
                arms[approach].setdefault("lane_turns",{})[str(lane)]=turns
        has_signal=any(a.get("control")=="signal" for a in arms)
        j["signal_count"]=len(arms) if has_signal else 0
        if has_signal:j["control"]="signal"
        for slot,arm in enumerate(arms):
            arm["signal_slot"]=slot
