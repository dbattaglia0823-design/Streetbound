extends RefCounted
## Cut baked station intervals out of paint paths, preserving dash phase.
static func parts(path: PackedVector2Array, station: float, gaps: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current := PackedVector2Array()
	var current_station := station
	var cursor := station
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		var length := a.distance_to(b)
		if length<.0001: continue
		var at := 0.0
		for gap in gaps:
			var start := maxf(0,float(gap[0])*20-cursor)
			var end := minf(length,float(gap[1])*20-cursor)
			if end<=at or start>=length: continue
			if start>at:
				if current.is_empty():
					current_station=cursor+at
					current.append(a.lerp(b,at/length))
				current.append(a.lerp(b,start/length))
			if current.size()>1: result.append({"path":current,"phase":current_station})
			current=PackedVector2Array()
			at=maxf(at,end)
		if at<length:
			if current.is_empty():
				current_station=cursor+at
				current.append(a.lerp(b,at/length))
			current.append(b)
		cursor+=length
	if current.size()>1: result.append({"path":current,"phase":current_station})
	return result
