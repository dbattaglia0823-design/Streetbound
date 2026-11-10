extends Node2D
## Actual top-down dealership buildings and paved, drivable forecourts.
## Each storefront uses the corresponding artwork in assets/Buildings/Dealerships.
## The local -Y direction points toward the nearest existing road.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const PPM := 20.0
const BUILDING_M := Vector2(26.0, 18.0)
var site: Dictionary = {}


func _ready() -> void:
	name = "Dealer_" + str(site.id)
	position = Vector2(float(site.center_m[0]), float(site.center_m[1])) * PPM
	rotation = float(site.rotation)
	z_index = 6
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build_shop()
	queue_redraw()


func _build_shop() -> void:
	var texture := load(str(site.texture)) as Texture2D
	if texture == null:
		push_warning("Dealership image missing: " + str(site.texture))
		return
	var art: Image = texture.get_image()
	var rect: Rect2i = Catalog.alpha_bounds(art)
	if rect.size.x < 4 or rect.size.y < 4:
		push_warning("Dealership image has no visible pixels: " + str(site.texture))
		return
	var facade := Sprite2D.new()
	facade.name = "DealershipArtwork"
	facade.texture = texture
	facade.region_enabled = true
	facade.region_rect = Rect2(rect)
	facade.scale = Vector2(BUILDING_M.x * PPM / rect.size.x,
		BUILDING_M.y * PPM / rect.size.y)
	facade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(facade)
	# Collide with the actual building, not the paved sales lot.
	var solid := StaticBody2D.new()
	solid.name = "BuildingCollision"
	solid.collision_layer = 1
	solid.collision_mask = 2
	var bounds := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = BUILDING_M * PPM * Vector2(0.88, 0.88)
	bounds.shape = shape
	solid.add_child(bounds)
	add_child(solid)


func _draw() -> void:
	if site.is_empty():
		return
	var d := float(site.get("setback_m", 36.0)) * PPM
	var apron := Rect2(Vector2(-PPM * 16.0, -d + PPM * 4.0),
		Vector2(PPM * 32.0, d - PPM * 11.0))
	var bounds := StyleBoxFlat.new()
	bounds.bg_color = Color("a8aba3")
	bounds.set_corner_radius_all(22)
	draw_style_box(bounds, apron.grow(PPM * 0.5))
	draw_rect(apron, Color("394549"), true)
	# Defined access throat to road, without a raised curb across the drive.
	var entrance := Rect2(Vector2(-PPM * 7.5, -d - PPM * 2.0),
		Vector2(PPM * 15.0, PPM * 8.0))
	draw_rect(entrance, Color("394549"), true)
	# The marked bays are a real, unobstructed place to drive up and park.
	var parking_y := -PPM * 17.0
	draw_rect(Rect2(Vector2(-PPM * 6.0, parking_y - PPM * 6.5),
		Vector2(PPM * 12.0, PPM * 13.0)), Color("c8b58b"), false, 4.0, true)
	for side in [-1.0, 1.0]:
		var x: float = float(side) * PPM * 12.0
		draw_line(Vector2(x, -d + PPM * 7.0),
			Vector2(x, -PPM * 10.5), Color("d5d6c5"), 3.0, true)
	# Storefront signage is near the sidewalk, visible at driving zoom.
	var sign_at := Vector2(-PPM * 12.5, -PPM * 10.5)
	draw_rect(Rect2(sign_at - Vector2(14.0, 44.0),
		Vector2(PPM * 25.0, 70.0)), Color("183038"), true)
	draw_string(ThemeDB.fallback_font, sign_at,
		str(site.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
		int(PPM * 23.0), 24, Color("f6e8c8"))
