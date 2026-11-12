extends Node2D
## Bounded tire smoke, surface dust and fading rear-tire skid marks.
## Contacts follow the current car's real visual wheel hubs, not fixed offsets.
const MAX_PUFFS := 90
const MAX_MARKS := 150
const SKID_LIFE := 3.4
var vehicle: VehicleController2D
var puffs: Array[Dictionary] = []
var skid_marks: Array[Dictionary] = []
var _rear_contacts: Array[Vector2] = []
var _emission := 0.0
var _last_position := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

static func loose_strength(surface: String) -> float:
	match surface:
		"GRAVEL": return .85
		"DIRT": return .75
		"SAND": return .72
		"GRASS": return .45
		_: return 0.0

static func dust_color(surface: String) -> Color:
	match surface:
		"GRAVEL": return Color(.73, .69, .60)
		"DIRT": return Color(.57, .46, .36)
		"SAND": return Color(.86, .76, .58)
		"GRASS": return Color(.43, .51, .35)
		_: return Color(.76, .81, .82)

func _ready() -> void:
	_rng.seed = 60491
	_last_position = vehicle.global_position
	_rear_contacts = _rear_wheel_contacts()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Dynamic ground contact accommodates every selected vehicle wheelbase.
func _rear_wheel_contacts() -> Array[Vector2]:
	var result: Array[Vector2] = []
	var rig: Node = vehicle.get_node_or_null("Art/Wheels")
	for i in [2, 3]:
		var anchor := Vector2(-16.0 if i == 2 else 16.0, 31.0)
		if is_instance_valid(rig) and rig.has_method("wheel_anchor"):
			anchor = rig.wheel_anchor(i)
		result.append(vehicle.global_position + anchor.rotated(vehicle.rotation))
	return result


static func tire_smoke_strength(speed_mps: float, slip_radians: float,
		wheel_spin: float, handbrake: float, surface: String) -> float:
	var moving := smoothstep(2.0, 12.0, speed_mps)
	var slide := smoothstep(0.08, 0.34, absf(slip_radians))
	var burnout := clampf(wheel_spin * 2.0, 0.0, 1.0)
	var loss := maxf(slide, maxf(burnout, handbrake))
	var surface_dust := loose_strength(surface) * moving
	# Burnouts can make smoke before reaching road speed. Ordinary rolling
	# never makes continuous dust on clean asphalt.
	return clampf(maxf(surface_dust,
		loss * maxf(moving, burnout * 0.72)), 0.0, 1.0)

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle):
		return
	var dt := minf(delta, 0.05)
	if dt <= 0.0:
		return
	if vehicle.global_position.distance_to(_last_position) > 550.0:
		puffs.clear()
		skid_marks.clear()
		_rear_contacts = _rear_wheel_contacts()
		_emission = 0.0
	_last_position = vehicle.global_position
	for i in range(puffs.size() - 1, -1, -1):
		var puff: Dictionary = puffs[i]
		puff["age"] = float(puff["age"]) + dt
		if float(puff["age"]) >= float(puff["life"]):
			puffs.remove_at(i)
			continue
		puff["point"] = Vector2(puff["point"]) + Vector2(puff["drift"]) * dt
		puffs[i] = puff
	var speed := vehicle.linear_velocity.length()
	var strength := tire_smoke_strength(speed, vehicle.slip_angle,
		vehicle.wheel_spin, vehicle.handbrake_grip_loss, vehicle.surface)
	_update_skid_marks(dt, speed)
	if strength < 0.03:
		_emission = 0.0
	else:
		_emission = minf(_emission + dt * strength * 46.0, 5.0)
		while _emission >= 1.0 and puffs.size() < MAX_PUFFS:
			_emission -= 1.0
			_spawn_puff(vehicle.surface)
		if puffs.size() >= MAX_PUFFS:
			_emission = 0.0
	queue_redraw()

func _update_skid_marks(dt: float, speed_mps: float) -> void:
	for i in range(skid_marks.size() - 1, -1, -1):
		var mark: Dictionary = skid_marks[i]
		mark["age"] = float(mark.age) + dt
		if float(mark.age) >= float(mark.life):
			skid_marks.remove_at(i)
		else:
			skid_marks[i] = mark
	var contacts := _rear_wheel_contacts()
	if _rear_contacts.size() != 2:
		_rear_contacts = contacts
		return
	var slip := maxf(smoothstep(0.12, 0.37, absf(vehicle.slip_angle)),
		maxf(vehicle.wheel_spin, vehicle.handbrake_grip_loss))
	if speed_mps >= 3.0 and slip > 0.20 and vehicle.surface == "ASPHALT":
		for i in 2:
			var from: Vector2 = _rear_contacts[i]
			var to: Vector2 = contacts[i]
			var travel: float = from.distance_to(to)
			if travel >= 5.0 and travel <= 90.0:
				skid_marks.append({"start":from, "end":to, "age":0.0,
					"life":SKID_LIFE, "width":4.0 + slip * 2.0})
				if skid_marks.size() > MAX_MARKS:
					skid_marks.pop_front()
	_rear_contacts = contacts


func _spawn_puff(surface: String) -> void:
	var contacts := _rear_wheel_contacts()
	var point: Vector2 = contacts[0 if _rng.randf() < 0.5 else 1]
	point += Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
	var drift := vehicle.linear_velocity * VehicleController2D.PIXELS_PER_METER * 0.11
	drift += Vector2(_rng.randf_range(-25.0, 25.0), _rng.randf_range(-25.0, 25.0))
	puffs.append({
		"point": point,
		"drift": drift,
		"age": 0.0,
		"life": _rng.randf_range(0.66, 1.12) if surface != "GRASS" else _rng.randf_range(.45, .78),
		"radius": _rng.randf_range(7.0, 12.5) if surface != "SAND" else _rng.randf_range(9.0, 16.0),
		"surface": surface,
		"color": dust_color(surface)
	})

func _draw() -> void:
	# Skid rubber is world-aligned. Fade every mark independently so the road
	# clears after a drift; never paint permanent data into streamed chunks.
	for mark in skid_marks:
		var life: float = float(mark.life)
		var fade: float = pow(1.0 - float(mark.age) / life, 1.8)
		var tint := Color(0.08, 0.10, 0.12, 0.28 * fade)
		draw_line(mark.start, mark.end, tint, float(mark.width), true)
	for puff in puffs:
		var progress := float(puff["age"]) / float(puff["life"])
		var fade := (1.0 - progress) * (1.0 - progress)
		var point: Vector2 = puff["point"]
		var radius := float(puff["radius"]) * (1.0 + progress * 1.8)
		var tint: Color = puff["color"]
		tint.a = 0.24 * fade
		draw_circle(point, radius, tint)
		tint.a = 0.15 * fade
		draw_circle(point + Vector2(radius * 0.28, -radius * 0.20), radius * 0.62, tint)
		if str(puff["surface"]) == "GRASS":
			# A few quick-fading grass blades curl off the moving rear tires.
			var blade := Color(.34, .47, .25, .23 * fade)
			draw_line(point + Vector2(-radius * .28, radius * .12),
				point + Vector2(-radius * .43, -radius * .55), blade, 2.0, true)
			draw_line(point + Vector2(radius * .18, radius * .26),
				point + Vector2(radius * .30, -radius * .50), blade, 1.6, true)
