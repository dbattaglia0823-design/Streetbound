extends RefCounted
## Simulation time advances independently of wall-clock economy cooldowns.
const RATE:=36.0
const DAY:=86400.0
const START:=43200.0
const MAX_TIME:=315360000.0

static func valid_time(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=MAX_TIME

static func hour(seconds: float) -> float:
	return fposmod(seconds,DAY)/3600.0

static func day(seconds: float) -> int:
	return floori(seconds/DAY)+1

static func clock_text(seconds: float) -> String:
	var minute:=floori(fposmod(seconds,DAY)/60.0)
	return "DAY %d  /  %02d:%02d"%[day(seconds),floori(float(minute)/60.0),minute%60]

static func until_hour(seconds: float,target: int) -> float:
	var delta:=fposmod(float(target)*3600.0-fposmod(seconds,DAY),DAY)
	return DAY if delta<1.0 else delta

static func open_at(seconds: float,kind: String) -> bool:
	var h:=hour(seconds)
	match kind:
		"dealership":return h>=8.0 and h<20.0
		"workshop":return h>=7.0 and h<19.0
		_:return true

static func traffic_factor(seconds: float) -> float:
	var h:=hour(seconds)
	if h>=7.0 and h<9.5 or h>=16.0 and h<19.0:return 1.5
	if h>=0.0 and h<5.0:return .35
	if h>=21.0 or h<7.0:return .65
	return 1.0

static func tint(seconds: float) -> Color:
	var h:=hour(seconds)
	var daylight:=smoothstep(5.0,8.0,h)*(1.0-smoothstep(18.0,21.0,h))
	return Color(.48,.54,.72).lerp(Color.WHITE,daylight)

## Smooth spatial and temporal weather fronts. Interpolated noise is based
## on world coordinates and simulation time, not frame order or real UTC.
static func _noise(x: int,y: int,t: int,seed_value: int) -> float:
	return float(posmod(hash("%d:%d:%d:%d"%[x,y,t,seed_value]),10000))/9999.0

static func rain(seconds: float,at_m: Vector2,seed_value: int,minimum: float=0.0) -> float:
	var p:=at_m/1000.0
	var ix:=floori(p.x);var iy:=floori(p.y)
	var t:=seconds/7200.0
	var it:=floori(t)
	var fx:=smoothstep(0.0,1.0,p.x-ix);var fy:=smoothstep(0.0,1.0,p.y-iy)
	var ft:=smoothstep(0.0,1.0,t-it)
	var values: Array[float]=[]
	for z in [it,it+1]:
		values.append(lerpf(lerpf(_noise(ix,iy,z,seed_value),_noise(ix+1,iy,z,seed_value),fx),lerpf(_noise(ix,iy+1,z,seed_value),_noise(ix+1,iy+1,z,seed_value),fx),fy))
	return maxf(clampf(minimum,0.0,1.0),smoothstep(.63,.92,lerpf(values[0],values[1],ft)))

static func rotation_seconds(seconds: float) -> int:
	return floori(seconds/RATE)

static func can_rest(stopped: bool,safe_location: bool,busy: bool,shared: bool) -> bool:
	return stopped and safe_location and not busy and not shared
