extends Node2D
## One lazily populated additive batch per live chunk. No Light2D nodes,
## shadows, collision bodies or per-frame redraws for individual lamps.
const Rules=preload("res://scripts/world/environment_finishing_rules.gd")
const Scenery=preload("res://scripts/world/coast_scenery.gd")
const PPM:=20.0
const MAX_SOURCES:=72
static var glow_texture: GradientTexture2D
static var glow_material: CanvasItemMaterial
var world: Node2D
var details: Node2D
var origin_m:=Vector2.ZERO
var extent_px:=Vector2.ZERO
var props: Array[Dictionary]=[]
var sources: Array[Dictionary]=[]
var prepared:=false

static func texture() -> GradientTexture2D:
	if glow_texture==null:
		var gradient:=Gradient.new()
		gradient.offsets=PackedFloat32Array([0.0,.18,.50,1.0])
		gradient.colors=PackedColorArray([Color(1,1,1,.95),Color(1,1,1,.72),Color(1,1,1,.22),Color(1,1,1,0)])
		glow_texture=GradientTexture2D.new();glow_texture.width=64;glow_texture.height=64
		glow_texture.gradient=gradient;glow_texture.fill=GradientTexture2D.FILL_RADIAL
		glow_texture.fill_from=Vector2(.5,.5);glow_texture.fill_to=Vector2(1,.5)
	return glow_texture

func _ready() -> void:
	visible=false
	if glow_material==null:
		glow_material=CanvasItemMaterial.new()
		glow_material.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
		glow_material.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material=glow_material

func set_night(amount: float) -> void:
	visible=amount>.015
	if not visible:return
	if not prepared:
		_prepare()
		queue_redraw()
	self_modulate.a=clampf(amount,0.0,1.0)

func _add(p: Vector2,style: String,building: bool=false) -> void:
	if sources.size()>=MAX_SOURCES or not Rules.owns(p,extent_px):return
	for entry in sources:
		if p.distance_squared_to(entry.p)<pow(PPM*2.5,2):return
	var palette:=Rules.palette(style)
	sources.append({"p":p,"color":palette.building if building else palette.lamp,
		"radius":float(palette.radius)*PPM*(.36 if building else 1.0),
		"strength":float(palette.strength)*(.65 if building else 1.0)})

func _prepare() -> void:
	prepared=true
	# Prioritize actual streetlights and then representative facade lights.
	for prop in props:
		if str(prop.kind)!="lamp" or Scenery.editor_hidden.has(Scenery.editor_key(prop)):continue
		var p: Vector2=Vector2(float(prop.p[0]),float(prop.p[1]))
		_add((p-origin_m)*PPM,Rules.style_at(world.data,p))
	if is_instance_valid(details):
		for lamp in details.lamp_positions():
			var p: Vector2=lamp.p
			_add(p,Rules.style_at(world.data,origin_m+p/PPM,Rules.road_fallback(str(lamp.kind))))
	for prop in props:
		if not Rules.building_kind(str(prop.kind)) or Scenery.editor_hidden.has(Scenery.editor_key(prop)):continue
		var center:=Vector2(float(prop.p[0]),float(prop.p[1]))
		var size:=Vector2(float(prop.size[0]),float(prop.size[1]))*PPM
		var style:=Rules.style_at(world.data,center)
		# A top-down entrance/roof-edge glow, not fabricated window geometry.
		# Stable seed leaves some homes dark at night.
		if style=="residential" and posmod(int(prop.get("seed",0)),4)==0:continue
		for side in [-1.0,1.0]:
			var offset:=Vector2(side*size.x*.25,-size.y*.43).rotated(float(prop.get("angle",0)))
			_add((center-origin_m)*PPM+offset,style,true)

func _draw() -> void:
	if not prepared:return
	for source in sources:
		var radius:=float(source.radius)
		var p: Vector2=source.p
		var tint: Color=source.color
		tint.a=float(source.strength)
		draw_texture_rect(texture(),Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),false,tint)
		tint.a=.7
		draw_circle(p,3.4,tint)
