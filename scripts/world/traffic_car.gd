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
	# Hide the debug shape without removing its physics registration.
	shape_node.visible = false
	var shape := CapsuleShape2D.new()
	shape.radius = width_px * 0.43
	shape.height = length_px * 0.94
	shape_node.shape = shape
	add_child(shape_node)
	_add_sprite()
	queue_redraw()


func _add_sprite() -> void:
	var path: String = MODEL_PATHS[posmod(model_index, MODEL_PATHS.size())]
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Traffic artwork unavailable: " + path)
		return
	var rect: Rect2i
	if crop_cache.has(path):
		rect = crop_cache[path]
	else:
		var pixels: Image = texture.get_image()
		if pixels == null:
			return
		# ImageGen's PNGs have almost invisible edge pixels (~0.4%
		# alpha) that make get_used_rect() expand to the whole square
		# canvas. Threshold sampling finds the actual opaque car body.
		rect = _visible_alpha_bounds(pixels)
		crop_cache[path] = rect
	if rect.size.x < 2 or rect.size.y < 2:
		return
	var sprite := Sprite2D.new()
	sprite.name = "VehicleArtwork"
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(rect)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Top-down cars in portrait artwork face upward. If an asset is
	# landscape, rotate its visual only; keep the physics body aligned.
	var aspect := Vector2(rect.size)
	if aspect.x > aspect.y * 1.08:
		sprite.rotation = -PI / 2.0
		aspect = Vector2(aspect.y, aspect.x)
	var scale_factor := minf(width_px / aspect.x, length_px / aspect.y)
	sprite.scale = Vector2.ONE * scale_factor
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
	# A soft oval shadow follows the silhouette instead of drawing a box
	# around the collision footprint. The physical shape is never rendered.
	for layer in range(3, 0, -1):
		var spread := float(layer) * 0.07
		draw_set_transform(Vector2(2.0, 4.0), 0.0,
			Vector2(width_px * (0.48 + spread), length_px * (0.47 + spread)))
		draw_circle(Vector2.ZERO, 1.0, Color(0.03, 0.04, 0.05, 0.048))
	draw_set_transform(Vector2.ZERO)
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
