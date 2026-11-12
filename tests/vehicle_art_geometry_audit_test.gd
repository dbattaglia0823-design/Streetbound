extends SceneTree
## Fleet-wide mechanical art audit. Verifies real alpha silhouettes, independently
## anchored tires and collision dimensions without guessing a car's visual front.
## Visual hub centers and exact body identity still require human art review.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, valid: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL", label, detail])
	if not valid:
		failures.append(label)


func run() -> void:
	var game: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var player: VehicleController2D = game.vehicle
	player.set_physics_process(false)
	var rig: Node2D = player.get_node("Art/Wheels")
	var sprite: Sprite2D = player.get_node("Art/Sprite")
	var inspected := 0
	var corner_alerts: Array[String] = []
	var shape_alerts: Array[String] = []
	for entry in Catalog.all():
		var id := str(entry.id)
		var ok: bool = Catalog.select(player, entry)
		if not ok:
			failures.append("cannot_equip_" + id)
			continue
		inspected += 1
		var texture: Texture2D = sprite.texture
		var image: Image = texture.get_image()
		var alpha_bounds: Rect2i = Catalog.alpha_bounds(image)
		var body: Rect2 = rig.visible_bounds
		var points: Array[Vector2] = rig._base_points
		var expected := Vector2(float(entry.width_m), float(entry.length_m)) * Catalog.PPM
		var valid: bool = body.has_area() and \
			absf(body.size.x - expected.x) < expected.x * 0.17 and \
			absf(body.size.y - expected.y) < expected.y * 0.17 and \
			alpha_bounds.size.x > 10 and alpha_bounds.size.y > 10 and \
			points.size() == 4 and rig.tire_size.x > 4.0 and rig.tire_size.y > 8.0
		if points.size() == 4 and body.has_area():
			var axle_gap := (points[2].y + points[3].y - points[0].y - points[1].y) * 0.5
			valid = valid and axle_gap > expected.y * 0.35 and \
				axle_gap < expected.y * 0.85 and \
				points[0].x < points[1].x and points[2].x < points[3].x
			for hub in points:
				valid = valid and body.grow(2.0).has_point(hub)
		if not valid:
			shape_alerts.append(id + " silhouette=" + str(body.size) +
				" expected=" + str(expected) + " hubs=" + str(points))
		# Diagnostics only: cropped body corners may legitimately be opaque,
		# but four solid corners often indicate an unremoved background.
		var dim := image.get_size()
		var corner_sum := 0.0
		for corner in [Vector2i(1, 1), Vector2i(dim.x - 2, 1),
				Vector2i(1, dim.y - 2), Vector2i(dim.x - 2, dim.y - 2)]:
			corner_sum += image.get_pixelv(corner).a
		if corner_sum > 3.2:
			corner_alerts.append(id)
	check("all_catalog_cars_equip_and_have_fitted_axles",
		inspected == Catalog.all().size() and shape_alerts.is_empty(),
		shape_alerts)
	print("FLEET ART TRANSPARENCY REVIEW (not automatically failed): ", corner_alerts)
	print("FLEET ART FACING REVIEW: direction cannot be established from alpha bounds alone.")
	print("FLEET ART AUDIT: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
