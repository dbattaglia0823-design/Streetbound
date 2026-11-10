extends CharacterBody2D
## Collidable, recoverable traffic vehicles. The ten authored top-down PNGs
## are cropped by their alpha bounds and scaled to a physical car-sized body.
## Player impacts can displace cars; TrafficFlow then returns them to a legal
## directional road lane rather than teleporting them to a fixed waypoint.
const PPM := 20.0
const MODEL_PATHS := [
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_42 PM-1.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_46 PM-2.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_47 PM-3.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_49 PM-4.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_50 PM-5.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_51 PM-6.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_52 PM-7.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_53 PM-8.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_55 PM-9.png",
	"res://assets/Traffic Vehicles/ChatGPT Image Nov 8, 2026, 09_28_56 PM-10.png"
]
static var crop_cache: Dictionary = {}
## Shared once-per-model textures and alpha-trimmed rectangles. Used by both
## moving traffic and static parked cars; each chunk does not rescan PNG data.
static var art_cache: Dictionary = {}
var car_color := Color("718899") # Only used when artwork is unavailable.
var accent_color := Color("e4d5b9")
var model_index := 0
var length_px := 76.0
var width_px := 38.0
var recovering := false
var recovery_velocity := Vector2.ZERO
var impact_count := 0
var model_loaded := false

static func model_count() -> int:
	return MODEL_PATHS.size()


func _ready() -> void:
	# Player layer=2/mask=1; world obstacles layer=1. Traffic collides with
	# both, and the player can push it instead of driving through a sprite.
	collision_layer = 1
	collision_mask = 3
	add_to_group("traffic_vehicle")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 2
	var shape_node := CollisionShape2D.new()
	shape_node.name = "VehicleCollider"
	var shape := CapsuleShape2D.new()
	shape.radius = width_px * 0.43
	shape.height = length_px * 0.94
	shape_node.shape = shape
	add_child(shape_node)
	_add_sprite()
	queue_redraw()


static func appearance_for(index: int) -> Dictionary:
	var slot := posmod(index,MODEL_PATHS.size())
	if art_cache.has(slot):
		return art_cache[slot]
	var path: String = MODEL_PATHS[slot]
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Traffic artwork unavailable: " + path)
		return {}
	var rect: Rect2i
	if crop_cache.has(path):
		rect = crop_cache[path]
	else:
		var pixels: Image = texture.get_image()
		if pixels == null:
			return {}
		rect = _visible_alpha_bounds(pixels)
		crop_cache[path] = rect
	if rect.size.x < 2 or rect.size.y < 2:
		return {}
	var degrees := 0.0
	var aspect := Vector2(rect.size)
	if aspect.x > aspect.y * 1.08:
		degrees = -PI / 2.0
		aspect = Vector2(aspect.y, aspect.x)
	var art := {
		"texture": texture, "region": rect, "rotation": degrees,
		"aspect": aspect, "source_aspect": Vector2(rect.size)
	}
	art_cache[slot] = art
	return art


func _add_sprite() -> void:
	var art := appearance_for(model_index)
	if art.is_empty():
		return
	var sprite := Sprite2D.new()
	sprite.name = "VehicleArtwork"
	sprite.texture = art.texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(art.region)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.rotation = float(art.rotation)
	var aspect: Vector2 = art.aspect
	sprite.scale = Vector2.ONE * minf(width_px / aspect.x, length_px / aspect.y)
	add_child(sprite)
	model_loaded = true


static func _visible_alpha_bounds(image: Image) -> Rect2i:
	var w := image.get_width()
	var h := image.get_height()
	var x_min := w
	var y_min := h
	var x_max := -1
	var y_max := -1
	# Four-pixel stride keeps one-time per-model analysis fast even for
	# 1254px source PNGs. A generous margin preserves antialiased edges.
	for y in range(0,h,4):
		for x in range(0,w,4):
			if image.get_pixel(x,y).a < 0.17:
				continue
			x_min = mini(x_min,x)
			y_min = mini(y_min,y)
			x_max = maxi(x_max,x)
			y_max = maxi(y_max,y)
	if x_max < x_min:
		return image.get_used_rect()
	var x0 := maxi(0,x_min-12)
	var y0 := maxi(0,y_min-12)
	var x1 := mini(w,x_max+16)
	var y1 := mini(h,y_max+16)
	return Rect2i(x0,y0,maxi(1,x1-x0),maxi(1,y1-y0))


func receive_impact(impulse_px_per_sec: Vector2) -> void:
	if impulse_px_per_sec.length_squared() < 1.0:
		return
	recovery_velocity = (recovery_velocity + impulse_px_per_sec).limit_length(PPM * 23.0)
	recovering = true
	impact_count += 1


func move_traffic(motion_px: Vector2, dt: float) -> KinematicCollision2D:
	# This is an actual swept CharacterBody collision, not a sprite teleport.
	# Knockback is consumed gradually so a collision is visible and cars can
	# rejoin a path without instantly snapping over buildings or sidewalks.
	var motion := motion_px + recovery_velocity * dt
	var hit := move_and_collide(motion)
	if hit:
		recovering = true
		recovery_velocity = recovery_velocity.slide(hit.get_normal()) * 0.38
	recovery_velocity = recovery_velocity.move_toward(Vector2.ZERO, PPM * 10.0 * dt)
	return hit


func _draw() -> void:
	# Shadow remains under the user-supplied artwork.
	draw_rect(Rect2(-width_px * .55 + 3, -length_px * .50 + 5,
		width_px * 1.1, length_px * 1.03),
		Color(0.06, 0.08, 0.10, 0.21), true)
	if model_loaded:
		return
	# Emergency fallback keeps traffic visible if an asset is missing,
	# but normally the ten actual vehicle images are displayed instead.
	var w := width_px * .5
	var h := length_px * .5
	draw_rect(Rect2(-w, -h, width_px, length_px), car_color, true)
	draw_rect(Rect2(-w + 5, -h + 14, width_px - 10, 19), Color("293f4a"), true)
	draw_rect(Rect2(-w + 5, h - 27, width_px - 10, 14), Color("455e68"), true)
	draw_line(Vector2(-w + 5, -h + 8), Vector2(w - 5, -h + 8),
		accent_color, 3, true)
