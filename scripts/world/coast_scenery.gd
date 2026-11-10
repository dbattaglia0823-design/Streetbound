extends Node2D
const Art = preload("res://scripts/world/coast_art.gd")
const TrafficCar = preload("res://scripts/world/traffic_car.gd")
const GarageGeometry = preload("res://scripts/world/garage_geometry.gd")
const PPM := 20.0
var prop_list: Array[Dictionary] = []
var origin_m := Vector2.ZERO
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material = preload("res://scripts/world/scenery_cutout.tres")
func point(raw: Array) -> Vector2:
	return (Vector2(float(raw[0]),float(raw[1]))-origin_m)*PPM
func _draw() -> void:
	for prop in prop_list:
		_draw_prop(prop)
	draw_set_transform(Vector2.ZERO)

func _rounded(rect: Rect2, color: Color, radius := 12.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)

## Parked cars share the alpha-trimmed model cache with moving traffic.
## Seed-based choices remain stable across streamed chunk reloads.
static func parked_art_for(seed_value: int) -> Dictionary:
	return TrafficCar.appearance_for(seed_value)


func _asphalt_apron(size: Vector2, seed_value: int, parking: bool, stall_width_m := 0.0, entrance_width_m := 0.0) -> void:
	# Warm rounded concrete curb and actual weathered charcoal asphalt.
	var bounds := Rect2(-size*.5,size)
	var curb := 16.0 if parking else 9.0
	_rounded(bounds,Color("b9b6a6") if parking else Color("a8aaa0"),
		38.0 if parking else 17.0)
	var roadbed := bounds.grow(-curb)
	_rounded(roadbed,Color("464f52"),28.0 if parking else 11.0)
	if parking:
		# Curb throat on the driveway-facing (-X) side; the original baked
		# road remains authoritative for traffic and collisions.
		var opening := clampf(entrance_width_m * PPM, 110.0, size.y * .63) if entrance_width_m > 0.0 else maxf(115.0,minf(size.y*.36,185.0))
		draw_rect(Rect2(-size.x*.5-3.0,-opening*.5,curb+24.0,opening),
			Color("464f52"),true)
		for side in [-1.0,1.0]:
			draw_line(Vector2(-size.x*.5-2.0,side*opening*.5),
				Vector2(-size.x*.5+curb+25.0,side*opening*.5),
				Color("cbc7b5"),5.0,true)
		draw_line(Vector2(-size.x*.5+curb+62.0,-opening*.37),
			Vector2(-size.x*.5+curb+62.0,opening*.37),
			Color(.82,.80,.70,.56),3.5,true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 918372
	# World-space shader handles fine grain; static oil, cracks and rubber
	# add depth without extra textures, collision or draw nodes.
	for i in (13 if parking else 5):
		var p := Vector2(rng.randf_range(roadbed.position.x+30.0,roadbed.end.x-30.0),
			rng.randf_range(roadbed.position.y+30.0,roadbed.end.y-30.0))
		draw_circle(p,rng.randf_range(8.0,32.0 if parking else 18.0),
			Color(.17,.21,.23,.20))
	for i in (18 if parking else 7):
		var p := Vector2(rng.randf_range(roadbed.position.x+24.0,roadbed.end.x-40.0),
			rng.randf_range(roadbed.position.y+24.0,roadbed.end.y-24.0))
		draw_line(p,p+Vector2(rng.randf_range(7.0,27.0),rng.randf_range(-4.0,4.0)),
			Color(.16,.19,.21,.27),rng.randf_range(1.2,2.6),true)
	if parking:
		var stalls := clampi(int((size.x*.84)/(stall_width_m*PPM)),3,16) if stall_width_m > 0.0 else clampi(int(size.x/105.0),3,9)
		for side in [-1.0,1.0]:
			for i in stalls+1:
				var x := lerpf(-size.x*.42,size.x*.42,float(i)/float(stalls))
				draw_line(Vector2(x,side*size.y*.44),
					Vector2(x,side*size.y*.22),Color("c9c8b4"),3.2,true)
			for i in stalls:
				var x := lerpf(-size.x*.42,size.x*.42,
					(float(i)+.5)/float(stalls))
				draw_line(Vector2(x-15.0,side*size.y*.395),
					Vector2(x+15.0,side*size.y*.395),Color("b2ab94"),5.0,true)
				draw_line(Vector2(x-12.0,side*size.y*.35),
					Vector2(x+12.0,side*size.y*.35),Color(.12,.16,.18,.30),3.0,true)
		# A faded arrow in the aisle keeps drivers out of the stalls.
		var arrow := Vector2(-size.x*.11,0)
		draw_line(arrow-Vector2(31,0),arrow+Vector2(17,0),Color(.85,.83,.71,.40),4,true)
		for side in [-1.0,1.0]:
			draw_line(arrow+Vector2(17,0),arrow+Vector2(2,side*11),
				Color(.85,.83,.71,.40),4,true)
	else:
		for i in 3:
			var x := -size.x*.30+float(i)*size.x*.30
			draw_line(Vector2(x,-size.y*.40),Vector2(x,size.y*.40),
				Color(.22,.26,.28,.23),1.8,true)


func _shrub(p: Vector2, radius: float, seed_value: int) -> void:
	# The same vegetation atlas used for street trees makes the small
	# roadside planting beds fit the existing illustrated buildings.
	var sprite := Art.sprite("pine" if seed_value%4==0 else "tree",seed_value)
	draw_circle(p+Vector2(2.8,4.0),radius*.95,Color(.13,.19,.14,.26))
	draw_circle(p,radius*.92,Color("55734c"))
	if sprite != null:
		var diameter := radius*(1.7 if seed_value%3==0 else 1.9)
		draw_texture_rect(sprite,Rect2(p-Vector2.ONE*diameter*.5,
			Vector2.ONE*diameter),false,Color(.88,.96,.86,1.0))
	else:
		for i in 5:
			var leaf := p+Vector2.from_angle((float(i)+.4)*TAU/5.0)*radius*.43
			draw_circle(leaf,radius*.47,
				Color("769b68") if i%2==0 else Color("83a577"))


func _shrub_bed(size: Vector2, seed_value: int, circular: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 645192
	if circular:
		var r := minf(size.x,size.y)*.5
		draw_circle(Vector2.ZERO,r+8.0,Color("bcb8a6"))
		draw_circle(Vector2.ZERO,r,Color("6d785b"))
		draw_circle(Vector2.ZERO,r*.87,Color("635e48"))
		var count := clampi(int(r/25.0),3,9)
		for i in count:
			var angle := (float(i)+.15)*TAU/float(count)
			var placement := Vector2.from_angle(angle)*r*(.30 if i%3==0 else .51)
			_shrub(placement,minf(35.0,r*.32)*rng.randf_range(.78,1.18),seed_value+i)
	else:
		_rounded(Rect2(-size*.5,size),Color("bab9a5"),8.0)
		_rounded(Rect2(-size*.5+Vector2.ONE*5.0,
			size-Vector2.ONE*10.0),Color("625e48"),5.0)
		var count := clampi(int(size.x/maxf(25.0,size.y*.85)),2,12)
		for i in count:
			var x := lerpf(-size.x*.39,size.x*.39,(float(i)+.5)/float(count))
			var placement := Vector2(x,rng.randf_range(-size.y*.10,size.y*.10))
			_shrub(placement,minf(23.0,size.y*.30)*rng.randf_range(.8,1.15),seed_value+i)


## Existing named destinations share the same cached building batch but
## receive recognizable roof silhouettes and business-specific palettes.
static func destination_motif(title: String) -> String:
	var name := title.to_lower()
	if name.contains("laurel motor"): return "motorhouse"
	if name.contains("performance"): return "tuning"
	if name.contains("auto gallery"): return "showroom"
	if name.contains("fuel") or name.contains("harvest rest"): return "fuel"
	if name.contains("pinecrest"): return "lodge"
	if name.contains("marina"): return "marina"
	if name.contains("overlook") or name.contains("lookout"): return "scenic"
	if name.contains("raceworks") or name.contains("drag staging"): return "racing"
	if name.contains("quarry"): return "industrial"
	if name.contains("village") or name.contains("farm"): return "village"
	if name.contains("saltair"): return "coastal"
	return "service"

func _destination_roof_details(size: Vector2, title: String) -> void:
	# Every detail fits within the original static building footprint, so
	# it cannot alter service lanes, parked traffic or solid collisions.
	var theme_name := destination_motif(title)
	var accent := Color("e5ae69") if theme_name == "motorhouse" else Color("8fc0b7")
	if theme_name in ["racing", "industrial"]:
		accent = Color("c9886a")
	elif theme_name in ["scenic", "lodge", "village"]:
		accent = Color("c8bd8e")
	elif theme_name in ["marina", "coastal"]:
		accent = Color("78b4c5")
	var upper_left := Vector2(-size.x * .31, size.y * .12)
	var lower_right := Vector2(size.x * .31, size.y * .31)
	draw_line(upper_left, Vector2(lower_right.x, upper_left.y), accent.darkened(.24), 5.0, true)
	match theme_name:
		"motorhouse", "tuning":
			# Three recognizable orange service-bay canopies.
			for i in 3:
				var x := -size.x * .25 + float(i) * size.x * .18
				draw_rect(Rect2(Vector2(x, size.y * .16),
					Vector2(size.x * .145, size.y * .13)), Color(.14, .24, .27, .82), true)
				draw_line(Vector2(x, size.y * .16),
					Vector2(x + size.x * .145, size.y * .16), accent, 5.0, true)
		"showroom", "coastal":
			draw_rect(Rect2(Vector2(-size.x * .22, size.y * .12),
				Vector2(size.x * .44, size.y * .16)), Color(.36, .58, .63, .82), true)
			for i in 4:
				var x := -size.x * .17 + float(i) * size.x * .11
				draw_line(Vector2(x, size.y * .12), Vector2(x, size.y * .28),
					Color(.82, .94, .90, .62), 2.2, true)
		"fuel":
			for side in [-1.0, 1.0]:
				var x := float(side) * size.x * .14
				draw_rect(Rect2(Vector2(x - 12, size.y * .16),
					Vector2(24, 32)), Color("b9ddd1"), true)
				draw_rect(Rect2(Vector2(x - 7, size.y * .16 + 6),
					Vector2(14, 8)), Color("3f7376"), true)
		"racing":
			for i in 6:
				var x := -size.x * .27 + float(i) * size.x * .09
				draw_rect(Rect2(Vector2(x, size.y * .15),
					Vector2(size.x * .09, size.y * .11)),
					Color("d9d5c7") if i % 2 == 0 else Color("48585a"), true)
		"industrial":
			for i in 4:
				var x := -size.x * .20 + float(i) * size.x * .12
				draw_line(Vector2(x, size.y * .13),
					Vector2(x + 13, size.y * .28), accent, 5.0, true)
		"marina", "scenic":
			draw_arc(Vector2.ZERO + Vector2(0, size.y * .20),
				minf(size.x, size.y) * .12, 0.0, TAU, 18, accent, 3.0, true)
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(Vector2(0, size.y * .20),
					Vector2(0, size.y * .20) + direction * minf(size.x, size.y) * .13,
					accent, 2.0, true)
		"lodge", "village":
			for i in 4:
				var y := size.y * (.14 + float(i) * .04)
				draw_line(Vector2(-size.x * .25, y),
					Vector2(size.x * .25, y), accent.darkened(.12), 3.0, true)

func _landmark_sign(kind: String, size: Vector2, title: String) -> void:
	# Every named destination gets a roof fascia and recognizable entrance.
	# Reuses original building art and the static scenery batch.
	var service := kind in ["garage","workshop","fuel","showroom","warehouse"]
	var motif := destination_motif(title)
	var accent := Color("c69a69") if service else Color("7ca49f")
	if motif == "motorhouse":
		accent = Color("e5ae69")
	elif motif in ["racing","industrial"]:
		accent = Color("c9886a")
	elif motif in ["marina","coastal"]:
		accent = Color("78b4c5")
	elif motif in ["scenic","lodge","village"]:
		accent = Color("c8bd8e")
	var width := minf(size.x*.78,410.0)
	var origin := Vector2(-size.x*.40,-size.y*.39)
	draw_rect(Rect2(origin,Vector2(width,36.0)),Color(.14,.22,.24,.80),true)
	draw_line(origin+Vector2(7,31),origin+Vector2(width-7,31),accent,3,true)
	var name := title.to_upper()
	if name.length()>25:
		name=name.substr(0,24)
	draw_string(ThemeDB.fallback_font,origin+Vector2(13,24),name,
		HORIZONTAL_ALIGNMENT_LEFT,int(width-22.0),20,Color("f1ebd9"))
	var entrance := Vector2(-size.x*.48,size.y*.23)
	draw_rect(Rect2(entrance,Vector2(42,54)),
		Color("749995") if service else Color("aeae9b"),true)
	draw_line(entrance+Vector2(8,9),entrance+Vector2(8,45),
		Color(.82,.90,.84,.62),3,true)


func _draw_player_garage(size: Vector2) -> void:
	# A genuine roof opening, not a switch-car icon on top of a solid prop.
	# The center drive-in bay is visible beneath the vehicle; roof/walls
	# have exactly the same geometry as the collision carve-out.
	var bounds := Rect2(-size * 0.5, size)
	_rounded(bounds.grow(12.0), Color("b3b7a7"), 16.0)
	_rounded(bounds, Color("26353b"), 11.0)
	var bay: Rect2 = GarageGeometry.bay_rect(size / PPM)
	bay = Rect2(bay.position * PPM, bay.size * PPM)
	_rounded(bay, Color("1c2b2e"), 5.0)
	_rounded(bay.grow(-18.0), Color("34464a"), 4.0)
	# Interior driving lines, wheel guide and target parking pad.
	var parking: Rect2 = GarageGeometry.parking_rect(size / PPM)
	parking = Rect2(parking.position * PPM, parking.size * PPM)
	draw_rect(parking, Color("9eb59c"), false, 5.0, true)
	draw_line(Vector2(parking.end.x - 15.0, parking.position.y + 16.0),
		Vector2(parking.end.x - 15.0, parking.end.y - 16.0),
		Color("c5a46c"), 6.0, true)
	for side in [-1.0, 1.0]:
		var y := side * bay.size.y * 0.32
		draw_line(Vector2(bay.position.x - 100.0, y),
			Vector2(bay.position.x + 90.0, y),
			Color("c6ba91"), 4.0, true)
	for wall: Rect2 in GarageGeometry.wall_rects(size / PPM):
		var wall_px := Rect2(wall.position * PPM, wall.size * PPM)
		_rounded(wall_px, Color("6b8284"), 9.0)
		_rounded(wall_px.grow(-17.0), Color("a2b8b1"), 6.0)
		# Painted metal roof ribs communicate solid, roofed side wings.
		for i in int(wall_px.size.x / 90.0):
			var x := wall_px.position.x + 30.0 + float(i) * 90.0
			draw_line(Vector2(x, wall_px.position.y + 15.0),
				Vector2(x, wall_px.end.y - 15.0),
				Color("cadaae"), 4.0, true)
	# Bay posts mark the edge of the wide, physically unobstructed doorway.
	for side in [-1.0, 1.0]:
		var y := side * bay.size.y * 0.5
		_rounded(Rect2(Vector2(bay.position.x - 8.0, y - 15.0),
			Vector2(29.0, 30.0)), Color("e6b36b"), 5.0)
	# Sign is on the solid wing, not across the drivable entrance.
	var sign_pos := Vector2(-size.x * 0.35, -size.y * 0.35)
	draw_rect(Rect2(sign_pos, Vector2(size.x * 0.7, 42.0)),
		Color("17282e"), true)
	draw_string(ThemeDB.fallback_font, sign_pos + Vector2(18.0, 29.0),
		"LAUREL MOTOR HOUSE  /  GARAGE", HORIZONTAL_ALIGNMENT_LEFT,
		int(size.x * 0.7 - 20.0), 24, Color("f3dfb7"))


func _draw_prop(prop: Dictionary) -> void:
	var center := point(prop.p)
	var size := Vector2(float(prop.size[0]),float(prop.size[1]))*PPM
	var color := Color(prop.color)
	var kind: String = prop.kind
	var seed_value := int(prop.seed)
	draw_set_transform(center,float(prop.angle))
	if GarageGeometry.is_player_garage(prop):
		_draw_player_garage(size)
		return
	var sprite: Texture2D = Art.sprite(kind,seed_value)
	if sprite!=null:
		var tint := Color.WHITE
		if kind in ["house","building","warehouse"]:
			tint = Color(1.0,0.98,0.94) if seed_value%2==0 else Color(0.94,0.98,1.0)
		draw_texture_rect(sprite,Rect2(-size/2,size),false,tint)
		if prop.has("poi"):
			_landmark_sign(kind,size,str(prop.poi))
			_destination_roof_details(size,str(prop.poi))
		return
	if kind in ["tree","pine","palm"]:
		var radius := size.x*.5
		# Top-down overlapping canopies; subtle warm footing, no hard cast shadow.
		draw_circle(Vector2(0,4),radius*1.02,Color("7c956c"))
		if kind == "palm":
			for i in 7:
				var direction := Vector2.from_angle(float(i)*TAU/7)
				draw_line(Vector2.ZERO,direction*radius,color,22,true)
				draw_line(direction*radius*.4,direction.rotated(.32)*radius*.8,color.lightened(.08),10,true)
		else:
			for i in 5:
				var offset := Vector2.from_angle(float(i)*TAU/5)*radius*.33
				draw_circle(offset,radius*.7,color.lightened(float(i%3)*.035))
			draw_circle(Vector2(-radius*.22,-radius*.19),radius*.58,color.lightened(.1))
		return
	if kind == "field":
		_rounded(Rect2(-size/2,size),color,50)
		# Alternating shaded planting ridges and soft crop highlights break up
		# uniform fields without adding thousands of tiny crop sprites.
		for side in [-1.0,1.0]:
			draw_line(Vector2(-size.x*.48,side*size.y*.47),Vector2(size.x*.48,side*size.y*.47),Color("8d9f76"),7,true)
			for post in range(int(size.x/80)):
				var p := Vector2(-size.x*.46+post*80,side*size.y*.47)
				draw_circle(p,4,Color("aeaa87"))
		var crop_rng := RandomNumberGenerator.new()
		crop_rng.seed = seed_value
		for row in range(int(size.y/100)):
			var y := -size.y/2+55+row*100
			var start := Vector2(-size.x/2+35,y)
			var finish := Vector2(size.x/2-35,y)
			draw_line(start,finish,color.darkened(.14 if row%2==0 else .095),23,true)
			draw_line(start+Vector2(0,-7),finish+Vector2(0,-7),color.lightened(.075),4,true)
			if row%2==0:
				for spot in 4:
					var x := lerpf(start.x+24,finish.x-24,(float(spot)+.5)/4.0)
					var p := Vector2(x+crop_rng.randf_range(-18,18),y+crop_rng.randf_range(-8,8))
					draw_circle(p,crop_rng.randf_range(5,9),color.lightened(.14))
		return
	if kind in ["start_line","finish_line"]:
		for row in 2:
			for column in int(size.x/12):
				var p := Vector2(-size.x/2+column*12,-size.y/2+row*12)
				draw_rect(Rect2(p,Vector2(12,12)),Color("e6dec7") if (column+row)%2==0 else Color("536764"))
		return
	if kind == "grandstand":
		_rounded(Rect2(-size/2,size),Color("c2c5b4"),12)
		for row in 5:
			var y := -size.y*.4+row*size.y*.18
			draw_line(Vector2(-size.x*.46,y),Vector2(size.x*.46,y),color.lightened(row*.02),18,true)
		_rounded(Rect2(Vector2(-size.x*.5,-size.y*.5),Vector2(size.x,size.y*.22)),Color("7b9b94"),9)
		return
	if kind == "bush":
		_shrub(Vector2.ZERO,minf(size.x,size.y)*.47,seed_value)
		return
	if kind == "sign":
		draw_line(Vector2(3,6),Vector2(13,16),Color(.12,.17,.18,.23),6,true)
		draw_line(Vector2(-size.x*.4,0),Vector2(size.x*.4,0),Color("d9d5bd"),8,true)
		draw_line(Vector2(-size.x*.33,-2),Vector2(size.x*.33,-2),
			Color("5e8577"),4,true)
		return
	if kind == "barrier":
		_rounded(Rect2(-size*.5,size),Color("c7c4af"),5)
		for i in 4:
			var x := -size.x*.34+size.x*.22*float(i)
			draw_line(Vector2(x,-size.y*.46),Vector2(x+size.x*.12,size.y*.46),
				Color("b97e62"),4,true)
		return
	if kind == "garden":
		_shrub_bed(size,seed_value,false)
		return
	if kind == "planter":
		_shrub_bed(size,seed_value,true)
		return
	if kind == "forecourt":
		_asphalt_apron(size,seed_value,false)
		return
	if kind == "lot":
		_asphalt_apron(size,seed_value,true,
			float(prop.get("stall_width",0.0)),float(prop.get("entrance_width",0.0)))
		return
	if kind == "parked_car":
		var art := parked_art_for(seed_value)
		# Same top-down models, alpha crop and proportions as moving traffic.
		# Paint into the static chunk draw list to avoid extra parked nodes.
		if not art.is_empty():
			var angle := float(art.rotation)
			var source: Vector2 = art.source_aspect
			var target := Vector2(size.y,size.x) if absf(angle)>0.01 else size
			var fitted := source*minf(target.x/source.x,target.y/source.y)
			_rounded(Rect2(-size*.5+Vector2(4,7),size),
				Color(.06,.09,.10,.22),9.0)
			draw_set_transform(center,float(prop.angle)+angle)
			draw_texture_rect_region(art.texture,Rect2(-fitted*.5,fitted),
				Rect2(art.region),Color.WHITE)
		else:
			_rounded(Rect2(-size*.5,size),color,9.0)
		return
	if kind == "rock":
		_rounded(Rect2(-size/2,size),color.darkened(.07),size.y*.4)
		_rounded(Rect2(-size*.35,size*.68),color.lightened(.09),size.y*.28)
		return
	if kind == "island":
		_shrub_bed(size,seed_value,true)
		return
	if kind == "dock":
		_rounded(Rect2(-size/2,size),color,7)
		for i in range(int(size.y/16)):
			draw_line(Vector2(-size.x/2,-size.y/2+i*16),Vector2(size.x/2,-size.y/2+i*16),color.darkened(.12),2)
		# Small moored boat, a soft rounded hull and warm canvas cabin.
		_rounded(Rect2(Vector2(size.x*.7,-size.y*.1),Vector2(50,155)),Color("e6e0c9"),24)
		_rounded(Rect2(Vector2(size.x*.7+10,0),Vector2(30,60)),Color("6b939a"),10)
		return
	if kind == "lamp":
		draw_line(Vector2.ZERO,Vector2(18,0),Color("7a827a"),4,true)
		draw_circle(Vector2(19,0),7,Color("dfd2a9"))
		return
	# Buildings are modular roof illustrations. Palette and layout distinguish
	# town houses, shops, downtown blocks, warehouses and destination facilities.
	_rounded(Rect2(-size/2-Vector2.ONE*9,size+Vector2.ONE*18),Color("b1b59f"),17)
	_rounded(Rect2(-size/2,size),color.darkened(.16),14)
	var inset := Vector2(10,10)
	_rounded(Rect2(-size/2+inset,size-inset*2),color,12)
	if kind in ["house","coastal_house","lodge"]:
		var roof := color.darkened(.10) if kind=="house" else color.lightened(.04)
		_rounded(Rect2(-size/2+Vector2(9,13),size-Vector2(18,26)),roof,11)
		draw_line(Vector2(-size.x*.39,0),Vector2(size.x*.39,0),roof.lightened(.16),9,true)
		for side in [-1.0,1.0]:
			for i in 3:
				var p := Vector2(-size.x*.28+i*size.x*.28,side*size.y*.39)
				_rounded(Rect2(p-Vector2(13,8),Vector2(26,16)),Color("cfdbd4"),3)
		_rounded(Rect2(Vector2(size.x*.2,-size.y*.25),Vector2(25,32)),Color("baaa96"),4)
		for i in range(int(size.y/24)):
			var y := -size.y*.4+float(i)*22
			draw_line(Vector2(-size.x*.4,y),Vector2(size.x*.4,y),Color(0.3,0.3,0.25,.035),2)
	else:
		var roof := color.lightened(.07)
		_rounded(Rect2(-size/2+Vector2.ONE*15,size-Vector2.ONE*30),roof,8)
		var cols := maxi(2,int(size.x/90))
		for i in cols:
			var p := Vector2(-size.x*.32+i*size.x*.64/maxf(cols-1,1),-size.y*.28)
			_rounded(Rect2(p,Vector2(33,45)),Color("93b0af"),5)
		if kind in ["garage","workshop","warehouse","fuel"]:
			for i in 3:
				var y := -size.y*.32+i*size.y*.28
				_rounded(Rect2(Vector2(-size.x/2-4,y),Vector2(24,size.y*.20)),Color("8eaaa5"),4)
			_rounded(Rect2(Vector2(size.x*.12,-size.y*.1),Vector2(48,55)),Color("b5bcb0"),6)
			for i in 5:
				draw_line(Vector2(size.x*.12+8,-size.y*.1+8+i*9),Vector2(size.x*.12+40,-size.y*.1+8+i*9),Color("98a79e"),3)
		else:
			for side in [-1.0,1.0]:
				_rounded(Rect2(Vector2(-size.x*.34,side*size.y*.43),Vector2(size.x*.68,12)),Color("759a9b"),3)
	# Small service apron on the front-facing edge, outside the solid footprint.
	if kind in ["garage","workshop","showroom","fuel","cafe"]:
		_rounded(Rect2(Vector2(-size.x/2-55,-size.y*.3),Vector2(48,size.y*.6)),Color("c4c0ad"),9)
		var stripe := Color("c88e73") if kind in ["garage","workshop"] else Color("89a49b")
		draw_line(Vector2(-size.x/2,-size.y*.36),Vector2(-size.x/2,size.y*.36),stripe,10,true)
	if prop.has("poi"):
		_landmark_sign(kind,size,str(prop.poi))
		_destination_roof_details(size,str(prop.poi))
