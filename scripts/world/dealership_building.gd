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
	# Asset sprites are illustrated with their storefront toward image +Y;
	# turn the art to face local -Y (the nearest driving road) without
	# turning the building collider, parking bays or road approach.
	facade.rotation = float(site.get("art_rotation", PI))
	facade.region_enabled = true
	facade.region_rect = Rect2(rect)
	facade.scale = Vector2(BUILDING_M.x * PPM / rect.size.x,
		BUILDING_M.y * PPM / rect.size.y)
	facade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(facade)
	# The sign must be a separate ABOVE-art child: drawing it in the parent
	# _draw() painted it underneath the storefront Sprite2D and hid names.
	var sign := Panel.new()
	sign.name = "DealershipSign"
	sign.position = Vector2(-PPM * 12.5, -PPM * 12.7)
	sign.size = Vector2(PPM * 25.0, 64.0)
	sign.z_index = 1
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("183038")
	frame.border_color = Color("b3aa90")
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(7)
	sign.add_theme_stylebox_override("panel", frame)
	var caption := Label.new()
	caption.name = "Name"
	caption.position = Vector2(14.0, 7.0)
	caption.size = Vector2(sign.size.x - 28.0, 50.0)
	caption.text = str(site.name).to_upper()
	caption.add_theme_font_size_override("font_size", 20)
	caption.add_theme_color_override("font_color", Color("f6e8c8"))
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.add_child(caption)
	add_child(sign)
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

