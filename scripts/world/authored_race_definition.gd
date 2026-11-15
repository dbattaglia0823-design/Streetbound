extends RefCounted
## Metre-space authoring contract shared by editor and race runtime.
static func valid(race: Dictionary,width: float,height: float) -> bool:
	if not str(race.get("id","")).begins_with("race-") or str(race.get("name","")).strip_edges().is_empty() or str(race.get("name","")).length()>80:return false
	if race.get("mode","") not in ["sprint","circuit"]:return false
	var points= race.get("points")
	if not points is Array or points.size()<(3 if race.mode=="circuit" else 2) or points.size()>100:return false
	for i in points.size():
		if not points[i] is Dictionary:return false
		var p:=Vector2(float(points[i].get("x",-1)),float(points[i].get("y",-1)))
		if not p.is_finite() or p.x<0 or p.y<0 or p.x>width or p.y>height:return false
		if i>0 and p.distance_to(Vector2(points[i-1].x,points[i-1].y))<5:return false
	for spec in [["laps",1,20],["checkpoint_radius",4,60],["start_radius",3,30],["time_limit",0,7200]]:
		var number= race.get(spec[0],{"laps":1,"checkpoint_radius":16,"start_radius":8,"time_limit":0}[spec[0]])
		if not typeof(number) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)) or float(number)<spec[1] or float(number)>spec[2]:return false
	var laps: float=float(race.get("laps",1))
	return laps==floorf(laps)
