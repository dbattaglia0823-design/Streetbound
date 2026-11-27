extends RefCounted
## Visual-only district profiles; no collision, grip, traffic or archive changes.
const STYLES=["residential","downtown","industrial","coastal","rural"]
const PALETTES={
	"residential":{"lamp":Color("#ffd49a"),"radius":8.0,"strength":.25,"wear":.85,"furniture":Color("#9a9e88"),"building":Color("#ffd7a2")},
	"downtown":{"lamp":Color("#e3efff"),"radius":10.0,"strength":.34,"wear":1.0,"furniture":Color("#718998"),"building":Color("#d6e9ff")},
	"industrial":{"lamp":Color("#ffc175"),"radius":11.0,"strength":.33,"wear":1.35,"furniture":Color("#a19c79"),"building":Color("#ffd09a")},
	"coastal":{"lamp":Color("#ffe2b7"),"radius":8.5,"strength":.24,"wear":.7,"furniture":Color("#8daaa4"),"building":Color("#ffe6bd")},
	"rural":{"lamp":Color("#ffe6b9"),"radius":7.0,"strength":.20,"wear":1.1,"furniture":Color("#9a9680"),"building":Color("#ffdcab")}
}
static func classify(label: String,fallback: String="residential") -> String:
	var value:=label.to_lower()
	for token in ["industrial","warehouse","foundry","freight","dockyard","port district","factory","logistics"]:
		if token in value:return "industrial"
	for token in ["downtown","commercial","civic","market","financial","office","business"]:
		if token in value:return "downtown"
	for token in ["coastal","coast","beach","harbor","harbour","marina","seaside","boardwalk"]:
		if token in value:return "coastal"
	for token in ["rural","farmland","forest","mountain","highland","country","farm"]:
		if token in value:return "rural"
	for token in ["residential","suburb","neighborhood","housing","laurel"]:
		if token in value:return "residential"
	return fallback

static func style_at(data: Dictionary,p: Vector2,fallback: String="residential") -> String:
	var zones: Array=data.get("gameplay_zones",[])
	for i in range(zones.size()-1,-1,-1):
		var z: Dictionary=zones[i]
		if Rect2(float(z.x),float(z.y),float(z.w),float(z.h)).has_point(p):
			var named:=classify(str(z.get("name","")),"")
			if not named.is_empty():return named
			if str(z.get("models",""))=="commercial":return "industrial"
	var best:=1.0
	var selected:=fallback
	for district in data.get("districts",[]):
		if district.get("p",[]).size()!=2:continue
		var origin:=Vector2(float(district.p[0]),float(district.p[1]))
		var score:=p.distance_to(origin)/maxf(1.0,float(district.get("radius",1)))
		if score<best:
			best=score;selected=classify(str(district.get("name","")),fallback)
	return selected

static func palette(style: String) -> Dictionary:
	return PALETTES.get(style,PALETTES.residential)

static func darkness(color: Color) -> float:
	# Phase 8's CanvasModulate is white at noon. The same rule supports
	# any future scene clock without introducing a second ambient modulator.
	var luma:=color.r*.2126+color.g*.7152+color.b*.0722
	return smoothstep(.05,.38,1.0-luma)

static func owns(point: Vector2,extent: Vector2) -> bool:
	return Rect2(Vector2.ZERO,extent).has_point(point)

static func building_kind(kind: String) -> bool:
	return kind in ["house","coastal_house","lodge","building","shop","warehouse","garage","workshop","showroom","fuel","cafe","office","hotel"]

static func road_fallback(kind: String) -> String:
	return "rural" if kind in ["rural","mountain","highway"] else ("industrial" if kind in ["alley","driveway"] else "residential")

## Global-station samples are invariant under chunk subdivision.
static func stations(start: float,length: float,spacing: float) -> PackedFloat32Array:
	var result:=PackedFloat32Array()
	if length<=0 or spacing<=0:return result
	var at:=ceilf((start-.001)/spacing)*spacing
	while at<start+length-.001:
		result.append(at);at+=spacing
	return result
