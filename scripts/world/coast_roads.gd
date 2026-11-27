extends Node2D
const PPM := 20.0
const RoadJump = preload("res://scripts/world/road_jump.gd")
const Elevation = preload("res://scripts/world/road_elevation.gd")
const TrackKerbs=preload("res://scripts/world/track_kerbs.gd")
const JunctionFurniture=preload("res://scripts/world/junction_furniture.gd")
## Editor-only draft masking. Cleared on editor close; game data stays intact.
static var editor_hidden: Dictionary={}
const Walkways = preload("res://scripts/world/urban_walkways.gd")
const Clip = preload("res://scripts/world/road_marking_clip.gd")
const Finish=preload("res://scripts/world/environment_finishing_rules.gd")
const Lanes=preload("res://scripts/world/traffic_lane_geometry.gd")
var render_stage := 0
var world: Node2D
var origin_m := Vector2.ZERO
var extent_px := Vector2.ZERO
var road_batches: Array[Dictionary] = []
var junction_list: Array[Dictionary] = []
func point(raw: Array) -> Vector2:
	return (Vector2(float(raw[0]),float(raw[1]))-origin_m)*PPM
func _ready() -> void:
	material=preload("res://scripts/world/road_surface.tres")

func _offset(path: PackedVector2Array, amount: float) -> PackedVector2Array:
	return Lanes.offset_path(path,amount)

const PAINT_YELLOW := Color("#e5be65")
const PAINT_WHITE := Color("#eeeae0")
const PREVIEW_PAVEMENT := Color("#454e54")

## Metric paint plan from the actual directional lane layout.
static func marking_plan(road: Dictionary, width_px: float, include_edges: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kind := str(road.get("kind",road.get("roadClass","local")))
	var surface := str(road.get("surface","ASPHALT")).to_upper()
	if surface in ["GRAVEL","DIRT"] or kind in ["alley","driveway","service","track"] or not bool(road.get("markings",true)):
		return result
	var data := {"kind":kind,"lanes":int(road.get("lanes",2)),"width":width_px/PPM}
	var layout := Lanes.layout(data)
	var divider := float(layout.divider)*PPM
	var fast := kind in ["highway","arterial","onramp"]
	var line_width := 3.0 if fast else 2.4
	var dash := 60.0
	var gap := 180.0 if fast else 120.0
	if int(layout.reverse)>0 and int(layout.forward)>0:
		if kind in ["highway","arterial","mountain"]:
			for side in [-1.0,1.0]:
				result.append({"offset":divider+float(side)*3.5,"width":line_width,"color":PAINT_YELLOW,"dash":0.0,"gap":0.0})
		else:
			result.append({"offset":divider,"width":line_width,"color":PAINT_YELLOW,"dash":dash,"gap":gap})
	for direction in [1,-1]:
		for lane in range(1,int(layout.forward if direction>0 else layout.reverse)):
			result.append({"offset":divider+direction*float(layout.width)*lane*PPM,"width":line_width,"color":PAINT_WHITE,"dash":dash,"gap":gap})
	if include_edges:
		for side in [-1.0,1.0]:
			result.append({"offset":float(side)*maxf(0.0,width_px*.5-7.0),"width":line_width,"color":PAINT_YELLOW if kind=="onramp" and int(road.get("lanes",1))==1 and side<0 else PAINT_WHITE,"dash":0.0,"gap":0.0})
	return result

## Use centerline station, not offset curve length, across clipped chunks.
static func dash_spans(station: float, length: float, dash: float, gap: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if length<=.001 or dash<=0.0 or gap<=0.0:return result
	var at := 0.0
	var cycle := dash+gap
	while at<length-.001:
		var phase := fposmod(station+at,cycle)
		var step := minf(length-at,dash-phase if phase<dash else cycle-phase)
		if step<.001:
			at+=.001
			continue
		if phase<dash:
			result.append({"from":at/length,"to":(at+step)/length,"index":floori((station+at)/cycle)})
		at+=step
	return result

static func paint_lane_lines(canvas: CanvasItem,path: PackedVector2Array,road: Dictionary,width_px: float,station: float=0.0,include_edges: bool=true) -> void:
	if path.size()<2:return
	for spec in marking_plan(road,width_px,include_edges):
		var stripe := Lanes.offset_path(path,float(spec.offset))
		var ink: Color=spec.color
		if float(spec.dash)<=0.0:
			canvas.draw_polyline(stripe,ink,float(spec.width),true)
			continue
		var cursor := station
		for i in range(1,path.size()):
			var length := path[i-1].distance_to(path[i])
			for span in dash_spans(cursor,length,float(spec.dash),float(spec.gap)):
				var dash_index := int(span.index)
				var weathered := ink
				weathered.a *= .80 if posmod(dash_index,13) in [2,9] else .97
				canvas.draw_line(stripe[i-1].lerp(stripe[i],float(span.from)),stripe[i-1].lerp(stripe[i],float(span.to)),weathered,float(spec.width),true)
			cursor+=length

## Compact world-stationed road wear. Every position is derived from the
## baked road phase, so neighboring streamed chunks produce the same rhythm.
## One cached drawing pass per road chunk; no decals, textures or physics nodes.
static func wear_stations(start: float, length: float, spacing: float = 480.0) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if length <= 0.0 or spacing <= 0.0:
		return result
	var at := ceilf((start - .01) / spacing) * spacing
	while at < start + length - .01:
		result.append(at)
		at += spacing
	return result

func _road_wear(path: PackedVector2Array, road: Dictionary, width: float, station: float) -> void:
	# Race circuits stay pristine; gravel is already given its own aggregate.
	if str(road.surface) in ["GRAVEL","DIRT"] or str(road.kind) == "track" or width < 140.0:
		return
	var passed := station
	for i in range(1, path.size()):
		var start := path[i - 1]
		var span := path[i] - start
		var length := span.length()
		if length <= .01:
			continue
		var tangent := span / length
		var normal := tangent.orthogonal()
		for sample in wear_stations(passed, length):
			var center := start + tangent * (sample - passed)
			# Assign the mark to one chunk even if its strokes cross that
			# chunk's edge; the neighboring chunk must not draw it twice.
			var edge: float = float(world.chunk_m) * PPM
			if center.x < 0.0 or center.y < 0.0 or center.x >= edge or center.y >= edge:
				continue
			var index := int(round(sample / 480.0))
			var side := -1.0 if index % 2 == 0 else 1.0
			var lane_center := center + normal * side * width * .22
			if index % 4 == 0:
				# Slightly irregular resurfaced rectangle, kept in a travel lane.
				var half_long := 30.0 + float(posmod(floori(float(index)/4.0), 5)) * 9.0
				var half_wide := minf(34.0, width * .12)
				var corners := PackedVector2Array([
					lane_center - tangent * half_long - normal * half_wide,
					lane_center + tangent * half_long - normal * (half_wide - 4.0),
					lane_center + tangent * (half_long - 5.0) + normal * half_wide,
					lane_center - tangent * (half_long + 3.0) + normal * half_wide
				])
				draw_colored_polygon(corners, Color(.12, .15, .17, .20))
				draw_line(corners[0], corners[1], Color(.60, .61, .56, .18), 1.7, true)
			elif index % 3 == 0:
				# Short sealed cracks follow the wheel-worn portion of the lane.
				var p := lane_center - tangent * 27.0
				var q := lane_center + tangent * 9.0 + normal * 6.0
				var finish := lane_center + tangent * 33.0 - normal * 4.0
				draw_line(p, q, Color(.13, .18, .21, .32), 1.9, true)
				draw_line(q, finish, Color(.13, .18, .21, .25), 1.4, true)
			if index % 5 == 0 and str(road.kind) not in ["local", "arterial"]:
				# Faint edge unraveling on rural/highland roads, inside the
				# actual pavement so the shoulder collision remains untouched.
				var shoulder := center + normal * side * (width * .5 - 10.0)
				draw_line(shoulder - tangent * 28.0, shoulder + tangent * 23.0,
					Color(.30, .28, .24, .24), 6.0, true)
		passed += length

func _paver_joints(path: PackedVector2Array, width: float, station: float) -> void:
	var cursor := station
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		var length := a.distance_to(b)
		if length<.001: continue
		var direction := (b-a)/length
		var normal := Vector2(-direction.y,direction.x)
		var at := 100.0-fposmod(cursor,100.0)
		while at<length:
			var p := a+direction*at
			for side in [-1.0,1.0]:
				draw_line(p+normal*side*(width*.5+9),p+normal*side*(width*.5+35),Color(.48,.49,.44,.24),1.3,true)
			at+=100
		cursor+=length

## Common road-relative paint geometry. The paved approach width is supplied
## by the junction baker; no assumptions about connecting road classes.
static func approach_stop_line(center: Vector2, direction: Vector2,
		width_px: float, inset_px: float = 10.0) -> PackedVector2Array:
	var along := direction.normalized()
	if along.length_squared() < 0.5 or width_px <= inset_px * 2.0:
		return PackedVector2Array()
	var across := along.orthogonal()
	var half: float = width_px * 0.5 - inset_px
	return PackedVector2Array([center - across * half, center + across * half])


static func approach_crosswalk(center: Vector2, direction: Vector2,
		width_px: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var along := direction.normalized()
	if along.length_squared() < 0.5 or width_px < 84.0:
		return result
	var across := along.orthogonal()
	# Keep stripes inset from kerbs. Compute spacing from the actual approach
	# width so arterials and narrow streets have equal, centered margins.
	var half: float = width_px * 0.5 - 18.0
	var spacing: float = 23.0
	var count: int = maxi(3, floori(2.0 * half / spacing))
	for i in count:
		var offset: float = (float(i) - float(count - 1) * 0.5) * spacing
		var p := center + across * offset
		result.append(PackedVector2Array([
			p - along * 11.0, p + along * 11.0
		]))
	return result


## Return the road-station intervals occupied by driveways on ONE side
## of this road. Only those curb/sidewalk segments are omitted: the asphalt,
## centerline, and opposite sidewalk are unaffected.
func _dealer_curb_gaps(road: Dictionary, side: float) -> Array:
	var gaps: Array = []
	if not is_instance_valid(world.dealerships):
		return gaps
	var road_id: int = int(road.get("id", -1))
	if road_id < 0:
		return gaps
	for site in world.dealerships.sites:
		if int(site.get("road_id", -1)) != road_id or \
				float(site.get("road_side", 0.0)) != side:
			continue
		var station: float = float(site.road_station_m)
		# 12m wide driveway plus a modest curb return on either side.
		gaps.append([station - 7.0, station + 7.0])
	# Procedural parking entrances share the same road-relative openings
	# and are cut only on the near side of the matching baked road.
	for access in world.parking_road_openings.get(road_id, []):
		if float(access.get("road_side", 0.0)) != side:
			continue
		var station: float = float(access.station_m)
		var half: float = float(access.get("half_width_m", 6.0))
		gaps.append([station - half, station + half])
	gaps.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) < float(b[0]))
	return gaps


func _deck_supports(path: PackedVector2Array, width: float, phase: float, layer: int) -> void:
	var station := phase
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		var length := a.distance_to(b)
		if length < .01:continue
		var tangent := (b-a)/length
		for mark in wear_stations(station,length,PPM*31.0):
			var center := a+tangent*(mark-station)
			if not Rect2(Vector2.ZERO,extent_px).has_point(center):continue
			for side in [-1.0,1.0]:
				var foot: Vector2 = center+tangent.orthogonal()*width*.47*side+Vector2(12,25)*layer
				if str(world.surface_at(foot+origin_m*PPM).name) != "GRASS":continue
				draw_circle(foot+Vector2(12,9),21,Color(.08,.09,.08,.28))
				draw_circle(foot,14,Color("626b64"))
				draw_line(foot,foot-Vector2(12,25)*layer,Color("929a93"),20,true)
		station += length


func _portal_art() -> void:
	for batch in road_batches:
		var road: Dictionary = batch.road
		var road_id := int(road.id)
		if editor_hidden.has(road_id) or not world.tunnel_portals.has(road_id):continue
		var first: bool = world.tunnel_portals[road_id]
		var raw: Array = road.points[0 if first else -1]
		var inner: Array = road.points[1 if first else -2]
		var mouth := point(raw)
		if not Rect2(Vector2.ZERO,extent_px).has_point(mouth):continue
		var outside := (point(inner)-mouth).normalized()
		var across := outside.orthogonal()
		var half := float(road.width)*PPM*.52
		var exit_depth := PPM*2.3
		var wall_width := PPM*1.3
		for side in [-1.0,1.0]:
			var corner: Vector2 = mouth+across*half*side
			var bank: Vector2 = across*side*wall_width
			var cut := PackedVector2Array([corner-outside*PPM*1.4,corner+bank*2.7,
				corner+bank*1.2+outside*PPM*8.0,corner+outside*PPM*5.5])
			draw_colored_polygon(cut,Color("657c52"))
			draw_line(corner-outside*PPM*.4,corner+outside*PPM*5.5,Color("675e50"),wall_width,true)
			draw_line(corner-outside*PPM*.4,corner+outside*PPM*5.5,Color("a89f87"),wall_width*.38,true)
		draw_line(mouth-across*half,mouth+across*half,Color("242a2e"),PPM*1.35,true)
		draw_line(mouth-outside*PPM*.42-across*half,mouth-outside*PPM*.42+across*half,
			Color("b9b4a3"),PPM*.34,true)
		draw_line(mouth+outside*exit_depth-across*half*.88,mouth+outside*exit_depth+across*half*.88,
			Color(.03,.04,.04,.32),PPM*2.6,true)


func _roads(stage: int) -> void:
	for batch in road_batches:
		if editor_hidden.has(int(batch.road.get("id",-1))):continue
		var path: PackedVector2Array = batch.path
		var r: Dictionary = batch.road
		var width := float(r.width) * PPM
		var layer := Elevation.artwork_layer(r)
		var urban: bool = layer == 0 and r.kind in ["local", "arterial"] and not TrackKerbs.is_track(r)
		var gravel: bool = r.surface in ["GRAVEL","DIRT"]
		if stage == 0:
			if Elevation.is_open_cut(r):
				# Excavated ground is absent; the wider foundation is the
				# exposed trench floor, not a painted-over terrain region.
				draw_polyline(path,Color("625b50"),width+48.0,true)
			if layer != 0:
				if layer > 0:
					_deck_supports(path,width,float(batch.phase),layer)
					var shadow := PackedVector2Array()
					for point_px in path:
						shadow.append(point_px+Vector2(19,30)*layer)
					draw_polyline(shadow,Color(.09,.12,.14,.38),width+16.0,true)
					draw_polyline(shadow,Color("69746d"),width-7.0,true)
				draw_polyline(path,Color("2d3740") if layer > 0 else Color("30343a"),width+(24.0 if layer>0 else 58.0),true)
			elif urban:
				# Both sides are real road-relative paths, not disconnected
				# rectangles. Their mitered offsets follow every road bend.
				for side in [-1.0, 1.0]:
					for section in Clip.parts(path, float(batch.phase),
							_dealer_curb_gaps(r, float(side))):
						var walkway := Walkways.urban_sidewalk_center(
							section.path, width, float(side))
						draw_polyline(walkway, Color("99a49b"),
							Walkways.SIDEWALK_WIDTH_PX + 16.0, true)
						draw_polyline(walkway, Color("dedbcc"),
							Walkways.SIDEWALK_WIDTH_PX + 2.0, true)
						var outside := Walkways.urban_sidewalk_outer(
							section.path, width, float(side))
						draw_polyline(outside, Color("b5b8a9"), 3.0, true)
			elif r.kind=="alley":
				draw_polyline(path,Color("77736b"),width+10.0,true)
			else:
				draw_polyline(path,Color("777a70"),width+35,true)
				draw_polyline(path,Color("96958a"),width+23,true)
		elif stage == 1:
			if layer < 0:
				draw_polyline(path,Color("333b42"),width,true)
				continue
			draw_polyline(path,Color("8b6946") if r.surface=="DIRT" else Color("a1947d") if gravel else Color("58656c"),width,true)
			if not gravel:
				_road_wear(path, r, width, float(batch.phase))
				# Dark lane wear tracks look like painted stripes on narrow alleys.
				if r.kind=="alley":continue
				var lanes: Array=[]
				var layout:=Lanes.layout(r)
				for direction in [1,-1]:
					for lane in int(layout.forward if direction>0 else layout.reverse):
						lanes.append(Lanes.lane_offset(r,direction,lane)*PPM)
				for lane in lanes:
					for wheel in [-13.0,13.0]:
						draw_polyline(_offset(path,float(lane)+wheel),Color(.10,.13,.15,.105),14,true)
		elif stage == 2:
			# Road junctions and side entrances use the same station-clipped
			# spans as lane markings. Kerbs must never cross an open junction
			# mouth even when the main road path itself remains continuous.
			for piece in batch.markings:
				var visible_path: PackedVector2Array = piece.path
				if urban and visible_path.size() >= 2:
					for side in [-1.0, 1.0]:
						# Junctions are already removed from visible_path.
						# Dealer openings cut only the roadside kerb and
						# painted edge line nearest their driveway.
						for section in Clip.parts(visible_path,
								float(piece.phase), _dealer_curb_gaps(r, float(side))):
							draw_polyline(Walkways.offset(section.path,
								float(side) * (width * 0.5 + 1.5)),
								Color("c8c5b9"), 4.0, true)
							draw_polyline(_offset(section.path,
								float(side) * (width * .5 - 7.0)),
								PAINT_WHITE, 3.0 if r.kind=="arterial" else 2.4, true)
				if Elevation.is_open_cut(r):
					for side in [-1.0,1.0]:
						var rim := _offset(visible_path,side*(width*.5+24.0))
						draw_polyline(rim,Color("3d3933"),11.0,true)
						draw_polyline(rim,Color("b0a38d"),4.0,true)
				if layer != 0:
					for side in [-1.0,1.0]:
						var wall := _offset(visible_path,side*width*.5)
						if layer<0:
							# Concrete wall section outside the usable pavement, with a dark
							# outer coping, lit inner face and continuous safety stripe.
							var outer:=_offset(visible_path,side*(width*.5+17.0))
							draw_polyline(outer,Color("202329"),25.0,true)
							draw_polyline(outer,Color("77797a"),17.0,true)
							draw_polyline(wall,Color("b4ada0"),7.0,true)
						else:
							draw_polyline(wall,Color("9aa8a8"),7.0,true)
						if layer < 0 and r.kind!="alley":
							var cursor := float(piece.phase)
							for i in range(1,wall.size()):
								var length := wall[i-1].distance_to(wall[i])
								for span in dash_spans(cursor,length,16.0,174.0):
									var lamp_a:=wall[i-1].lerp(wall[i],float(span.from))
									var lamp_b:=wall[i-1].lerp(wall[i],float(span.to))
									draw_line(lamp_a,lamp_b,Color("e7ba70"),9.0,true)
									draw_line(lamp_a,lamp_b,Color("fff0c8"),3.0,true)
								cursor += length
				_paint(visible_path,r,width,float(piece.phase))

## Manhole covers, faded utility repairs and compact rain drains. Derived
## from the global road station so marks continue across streamed chunk seams.
## Excludes junction mouths because _paint receives clipped marking spans.
func _street_surface_details(path: PackedVector2Array, road: Dictionary, width: float, station: float) -> void:
	if road.kind not in ["local", "arterial"] or path.size() < 2:
		return
	var spacing := 1260.0
	var passed := station
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var segment := b - a
		var length := segment.length()
		if length <= .01:
			continue
		var tangent := segment / length
		var normal := tangent.orthogonal()
		var sample := ceilf((passed + .05) / spacing) * spacing
		while sample < passed + length - .05:
			var center := a + tangent * (sample - passed)
			# Side gutters and utility fittings must stay within this chunk.
			if center.x >= 12.0 and center.y >= 12.0 and \
				center.x < world.chunk_m * PPM - 12.0 and \
				center.y < world.chunk_m * PPM - 12.0:
				var n := int(sample / spacing)
				var cover := center + normal * (width * (.26 if n % 2 == 0 else -.26))
				draw_circle(cover, 15.0, Color(.15,.21,.23,.30))
				draw_arc(cover, 11.0, 0.0, TAU, 12, Color(.53,.56,.53,.34), 2.1, true)
				for side in [-1.0, 1.0]:
					var drain: Vector2 = center + normal * float(side) * (width * .5 - 18.0)
					draw_line(drain - tangent * 13.0, drain + tangent * 13.0,
						Color(.13,.18,.20,.44), 7.0, true)
			sample += spacing
		passed += length


## Extra road-relative storytelling, drawn under final paint and only in
## marking-clipped spans. Small, low-contrast, visual-only surface details.
func _finish_decals(path: PackedVector2Array,road: Dictionary,width: float,station: float) -> void:
	if path.size()<2 or width<120.0 or str(road.surface) in ["GRAVEL","DIRT"] or str(road.kind) in ["track","onramp"] or road.has("elevation"):return
	var passed:=station
	for i in range(1,path.size()):
		var a:=path[i-1];var b:=path[i]
		var length:=a.distance_to(b)
		if length<.001:continue
		var tangent: Vector2=(b-a)/length
		var normal:=tangent.orthogonal()
		for at in Finish.stations(passed,length,940.0):
			var p:=a+tangent*(at-passed)
			if not Finish.owns(p,extent_px):continue
			var n:=roundi(at/940.0)
			var style: String=world.environment_style_at(origin_m+p/PPM,Finish.road_fallback(str(road.kind))) if world.has_method("environment_style_at") else Finish.style_at(world.data,origin_m+p/PPM,Finish.road_fallback(str(road.kind)))
			var weight:=float(Finish.palette(style).wear)
			var side: float=-1.0 if n%2==0 else 1.0
			var shoulder:=p+normal*side*(width*.5-13.0)
			if style=="industrial":
				# Dark loading-yard stains and tar repairs; no artificial obstacles.
				for k in 3:
					var stain:=p+normal*side*width*.26+tangent*float(k-1)*11.0
					draw_circle(stain,7.0+float(k%2)*3.0,Color(.12,.13,.14,.12*weight))
			elif style=="coastal":
				draw_line(shoulder-tangent*21.0,shoulder+tangent*22.0,Color(.72,.66,.48,.16),5.0,true)
			elif style=="rural":
				draw_line(shoulder-tangent*18.0,shoulder+tangent*16.0,Color(.32,.29,.24,.20),7.0,true)
			else:
				var joint:=p+normal*side*width*.22
				draw_line(joint-tangent*17.0,joint+tangent*17.0+normal*5.0,Color(.17,.21,.23,.20*weight),2.0,true)
				if style=="downtown" and n%3==0:
					draw_line(shoulder-tangent*10.0,shoulder+tangent*10.0,Color(.59,.60,.54,.3),2.0,true)
		passed+=length

func _paint(path: PackedVector2Array,r: Dictionary,width: float,station: float) -> void:
	if r.kind=="alley":return
	_finish_decals(path,r,width,station)
	var urban: bool = r.kind in ["local","arterial"]
	var gravel: bool = r.surface in ["GRAVEL","DIRT"]
	if urban:
		_paver_joints(path,width,station)
		_street_surface_details(path,r,width,station)
	if gravel or r.kind in ["driveway","alley"]:
		return
	if TrackKerbs.is_track(r):
		TrackKerbs.paint(self,path,width,station)
		return
	paint_lane_lines(self,path,r,width,station,not urban)
func _draw() -> void:
	if render_stage < 3:
		_roads(render_stage)
		return
	_portal_art()
	for batch in road_batches:
		var road_id := int(batch.road.id)
		if editor_hidden.has(road_id):continue
		var jump: Dictionary = world.jumps_by_road.get(road_id,{})
		if not jump.is_empty():
			var lip := point(jump.p)
			if Rect2(Vector2.ZERO,extent_px).has_point(lip):
				RoadJump.draw_footprint(self,jump,lip,Vector2(jump.direction[0],jump.direction[1]),false)
	for j in junction_list:
		var hidden:=false
		for road_id in j.get("roads",[]):
			if editor_hidden.has(int(road_id)):hidden=true;break
		if hidden:continue
		var polygon := PackedVector2Array()
		for p in j.polygon: polygon.append(point(p))
		if int(j.get("road_layer",0))<0:
			# Only the outside corners are walled: junction approaches stay open.
			draw_colored_polygon(polygon,Color("333b42"))
			for curve in j.curbs:
				var wall_path:=PackedVector2Array()
				for p in curve:wall_path.append(point(p))
				if wall_path.size()<2:continue
				draw_polyline(wall_path,Color("30343a"),26.0,true)
				draw_polyline(wall_path,Color("77797a"),16.0,true)
				draw_polyline(wall_path,Color("b4ada0"),5.0,true)
			continue
		# The baker provides only OUTSIDE corner fillets, never a line across
		# a street approach. Extend each eligible corner into a sidewalk
		# apron, then mask the inside with the actual junction asphalt.
		for i in j.curbs.size():
			if j.approaches.is_empty():
				continue
			var first: Dictionary = j.approaches[i % j.approaches.size()]
			var second: Dictionary = j.approaches[(i + 1) % j.approaches.size()]
			var a_urban: bool = world.data.roads[int(first.road)].kind in ["local", "arterial"]
			var b_urban: bool = world.data.roads[int(second.road)].kind in ["local", "arterial"]
			if not (a_urban or b_urban):
				continue
			var corner := PackedVector2Array()
			for p in j.curbs[i]: corner.append(point(p))
			if corner.size() < 2:
				continue
			draw_polyline(corner, Color("9ba89f"),
				Walkways.SIDEWALK_WIDTH_PX * 2.0 + 21.0, true)
			draw_polyline(corner, Color("dedbcc"),
				Walkways.SIDEWALK_WIDTH_PX * 2.0 + 3.0, true)
		draw_colored_polygon(polygon,Color("58656c"))
		if str(j.get("control",""))=="merge":
			var through := PackedVector2Array()
			for arm in j.approaches:
				if int(arm.road)!=int(j.get("ramp_road",-1)):through.append(point(arm.p))
			if through.size()==2:
				through.insert(1,point(j.p))
				var main: Dictionary = world.data.roads[int(j.get("main_road",0))]
				paint_lane_lines(self,through,main,float(main.width)*PPM,0.0,false)
		# Rounded curb fillets leave vehicle mouths and marked crosswalks open.
		for curve in j.curbs:
			var path := PackedVector2Array()
			for p in curve: path.append(point(p))
			draw_polyline(path,Color("c6c3b8"),4.0,true)
		JunctionFurniture.draw_junction(self,j,origin_m,PPM,world.data.roads)
		for arm in j.approaches:
			if str(arm.get("control","")) not in ["stop","yield"]:continue
			var direction:=Vector2(arm.direction[0],arm.direction[1])
			var normal:=Vector2(-direction.y,direction.x)
			_sign(point(arm.p)+direction*30-normal*(float(arm.width)*PPM*.5+32),direction,str(arm.control)=="yield")
	draw_set_transform(Vector2.ZERO)

func _sign(p: Vector2,outward: Vector2,yield_sign: bool) -> void:
	draw_line(p+Vector2(5,7),p+Vector2(16,21),Color(.08,.14,.15,.3),8,true)
	draw_circle(p+Vector2(0,5),3,Color("b3bbb1"))
	draw_set_transform(p,outward.angle()+PI/2)
	var shape := PackedVector2Array()
	if yield_sign:
		shape=PackedVector2Array([Vector2(-14,-10),Vector2(14,-10),Vector2(0,14)])
	else:
		for i in 8: shape.append(Vector2.from_angle(PI/8+i*TAU/8)*14)
	draw_colored_polygon(shape,Color("f2e8d4"))
	var inset := PackedVector2Array()
	for v in shape: inset.append(v*.86)
	draw_colored_polygon(inset,Color("ae493c"))
	if yield_sign:
		var middle := PackedVector2Array()
		for v in shape: middle.append(v*.56)
		draw_colored_polygon(middle,Color("eee5cf"))
	else:
		draw_string(ThemeDB.fallback_font,Vector2(-11,3),"STOP",HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color("fff4dd"))
	draw_set_transform(Vector2.ZERO)
